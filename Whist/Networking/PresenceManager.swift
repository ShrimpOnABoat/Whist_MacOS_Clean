//
//  PresenceManager.swift
//  Whist
//
//  Created by Tony Buffard on 2025-04-22.
//


import FirebaseDatabase

class PresenceManager: ObservableObject {
    static let shared = PresenceManager()
    
    private var databaseRef: DatabaseReference?
    private var connectedRef: DatabaseReference? // For .info/connected
    private var userStatusRef: DatabaseReference? // For status/<playerId>
    private var localPlayerId: String? // Store the local player's ID
    private var connectedHandle: DatabaseHandle?
    private var localPlayerState: PlayerState = .idle
    
    private var peerStatusListeners: [String: DatabaseHandle] = [:] // To keep track of listeners
    // Callback to inform GameManager
    var onPeerPresenceChanged: ((_ peerId: PlayerId, _ isOnline: Bool) -> Void)?
    var onPeerStateChanged: ((_ peerId: PlayerId, _ state: PlayerState) -> Void)?
    
    // 1. Add a property to store the current session ID
    // Make it private(set) so it can only be set internally, but readable externally
    private(set) public var currentSessionId: String
    // 2. Keep track of peers' session IDs to detect restarts
    private var peerSessionIds: [PlayerId: String] = [:]
    
    init() {
        // Initialize with a new UUID, but this will be preserved across game clears
        self.currentSessionId = UUID().uuidString
    }
    
    // 3. Helper to get a peer's session ID
    func getSessionId(for peerId: PlayerId) -> String? {
        return peerSessionIds[peerId]
    }
    
    func configure(with playerId: String) {
        guard localPlayerId != playerId || connectedHandle == nil else { return }
        stopMonitoringPeerPresence()
        if let connectedHandle {
            connectedRef?.removeObserver(withHandle: connectedHandle)
        }
        if localPlayerId != nil, localPlayerId != playerId {
            goOfflineManually()
            userStatusRef?.cancelDisconnectOperations()
            peerSessionIds.removeAll()
            localPlayerState = .idle
        }
        self.localPlayerId = playerId
        self.databaseRef = Database.database().reference()
        self.connectedRef = databaseRef?.child(".info/connected")
        self.userStatusRef = databaseRef?.child("status/\(playerId)")
        
        // Monitor connection state to Firebase
        connectedHandle = connectedRef?.observe(.value) { [weak self] snapshot in
            guard let self = self, let connected = snapshot.value as? Bool, connected else {
                logger.log("[Presence] Not connected to Firebase Realtime Database.")
                return
            }
            guard self.localPlayerId == playerId, let statusRef = self.userStatusRef else { return }

            // Register server-side cleanup before advertising this session online.
            statusRef.onDisconnectUpdateChildValues([
                "online": false,
                "last_seen": ServerValue.timestamp()
            ]) { [weak self] error, _ in
                guard let self, self.localPlayerId == playerId else { return }
                if let error {
                    logger.log("[Presence] Could not register disconnect cleanup: \(error.localizedDescription)")
                    return
                }
                statusRef.setValue([
                    "online": true,
                    "last_seen": ServerValue.timestamp(),
                    "sessionId": self.currentSessionId,
                    "state": self.localPlayerState.rawValue
                ]) { error, _ in
                    if let error {
                        logger.log("[Presence] Could not publish online status: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func publishPlayerState(_ state: PlayerState) {
        localPlayerState = state
        userStatusRef?.updateChildValues(["state": state.rawValue]) { error, _ in
            if let error {
                logger.log("[Presence] Could not publish player state: \(error.localizedDescription)")
            }
        }
    }
    
    func startMonitoringPeerPresence(for peerIds: [PlayerId], localPlayerId: PlayerId) {
        guard let dbRef = databaseRef else {
            print("[Presence] Error: Database reference not configured.")
            return
        }
        
        logger.log("[Presence] Starting to monitor peers: \(peerIds.map { $0.rawValue }.joined(separator: ", ")) excluding self (\(localPlayerId.rawValue))")
        
        for peerId in peerIds {
            if peerId == localPlayerId { continue } // Don't monitor self
            
            let peerStatusRef = dbRef.child("status/\(peerId.rawValue)")
            
            // Remove previous listener for this peer to avoid duplicates if called multiple times
            if let existingHandle = peerStatusListeners[peerId.rawValue] {
                peerStatusRef.removeObserver(withHandle: existingHandle)
                logger.log("[Presence] Removed existing listener for \(peerId.rawValue).")
            }
            
            let handle = peerStatusRef.observe(.value, with: { [weak self] snapshot in
                DispatchQueue.main.async { [weak self] in
                    self?.handlePeerStatus(snapshot.value as? [String: Any], for: peerId)
                }
            }, withCancel: { error in
                logger.log("[Presence] Peer listener for \(peerId.rawValue) failed: \(error.localizedDescription)")
            })
            peerStatusListeners[peerId.rawValue] = handle
            logger.log("[Presence] Added listener for \(peerId.rawValue).")
        }
    }

    /// Apply presence and its latest action status together, including after a
    /// late join or reconnect. Older clients may omit the state field.
    func handlePeerStatus(_ value: [String: Any]?, for peerId: PlayerId) {
        let isOnline = value?["online"] as? Bool ?? false
        let remoteSessionId = value?["sessionId"] as? String
        let lastKnownSessionId = peerSessionIds[peerId]
        if let remoteSessionId {
            peerSessionIds[peerId] = remoteSessionId
        }
        if isOnline, let remoteSessionId, let lastKnownSessionId,
           remoteSessionId != lastKnownSessionId {
            logger.log("[Presence] Peer \(peerId.rawValue) restarted. Forcing disconnect cleanup.")
            onPeerPresenceChanged?(peerId, false)
        }
        logger.log("[Presence] Peer \(peerId.rawValue) is now \(isOnline ? "ONLINE" : "OFFLINE").")
        onPeerPresenceChanged?(peerId, isOnline)
        if isOnline, let rawState = value?["state"] as? String,
           let state = PlayerState(rawValue: rawState) {
            onPeerStateChanged?(peerId, state)
        }
    }
    
    func goOfflineManually() {
        guard let userStatusRef = userStatusRef, let playerId = self.localPlayerId else { return }
        logger.log("[Presence] Setting user \(playerId) to OFFLINE manually.")
        userStatusRef.updateChildValues([
            "online": false,
            "last_seen": ServerValue.timestamp()
        ])
        // Important: Cancel the onDisconnect operations since we are manually going offline.
        // Otherwise, if the app quits right after this, onDisconnect might overwrite it.
        // However, for simplicity and most app lifecycle, just setting to false might be enough.
        // For full control, you'd cancel onDisconnects:
        // userStatusRef.cancelDisconnectOperations()
    }
    
    func stopMonitoringPeerPresence() {
        guard let dbRef = databaseRef else { return }
        for (peerIdString, handle) in peerStatusListeners {
            let peerStatusRef = dbRef.child("status/\(peerIdString)")
            peerStatusRef.removeObserver(withHandle: handle)
        }
        peerStatusListeners.removeAll()
    }
    
    deinit {
        stopMonitoringPeerPresence()
    }
    
    // TODO: checkPresence(of: playerId)
}
