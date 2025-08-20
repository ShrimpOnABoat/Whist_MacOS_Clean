//
//  PresenceManager.swift
//  Whist
//
//  Created by Tony Buffard on 2025-04-22.
//


import FirebaseDatabase
import FirebaseAuth

class PresenceManager: ObservableObject {
    static let shared = PresenceManager()
    
    private var databaseRef: DatabaseReference?
    private var connectedRef: DatabaseReference? // For .info/connected
    private var userStatusRef: DatabaseReference? // For status/<playerId>
    private var localPlayerId: String? // Store the local player's ID

    private var peerStatusListeners: [String: DatabaseHandle] = [:] // To keep track of listeners
    // Callback to inform GameManager
    var onPeerPresenceChanged: ((_ peerId: PlayerId, _ isOnline: Bool) -> Void)?
    private init() {}

    func configure(with playerId: String) {
        self.localPlayerId = playerId
        self.databaseRef = Database.database().reference()
        self.connectedRef = databaseRef?.child(".info/connected")
        self.userStatusRef = databaseRef?.child("status/\(playerId)")
     
        // Monitor connection state to Firebase
        connectedRef?.observe(.value) { [weak self] snapshot in
            guard let self = self, let connected = snapshot.value as? Bool, connected else {
                logger.log("[Presence] Not connected to Firebase Realtime Database.")
                // If desired, you could also try to set status to offline here,
                // but onDisconnect should primarily handle this.
                return
            }

            logger.log("[Presence] Connected to Firebase Realtime Database. Setting presence for \(playerId).")

            // Data to write when connected
            let presenceData: [String: Any] = [
                "online": true,
                "last_seen": ServerValue.timestamp() // Use server timestamp
            ]

            // Set current status to online
            self.userStatusRef?.setValue(presenceData) { error, _ in
                if let error = error {
                    logger.log("[Presence] Error setting user online: \(error.localizedDescription)")
                } else {
                    logger.log("[Presence] User \(playerId) set to ONLINE.")
                }
            }

            // Set up onDisconnect to mark user as offline
            self.userStatusRef?.onDisconnectUpdateChildValues([
                "online": false,
                "last_seen": ServerValue.timestamp()
            ]) { error, _ in
                if let error = error {
                    logger.log("[Presence] Error setting onDisconnect: \(error.localizedDescription)")
                } else {
                    logger.log("[Presence] onDisconnect handler set for \(playerId).")
                }
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
            
            let handle = peerStatusRef.observe(.value) { [weak self] snapshot in
                guard let self = self else { return }
                var isOnline = false
                if let value = snapshot.value as? [String: Any],
                   let onlineStatus = value["online"] as? Bool {
                    isOnline = onlineStatus
                }
                logger.log("[Presence] Peer \(peerId.rawValue) is now \(isOnline ? "ONLINE" : "OFFLINE").")
                DispatchQueue.main.async { [weak self] in
                    self?.onPeerPresenceChanged?(peerId, isOnline)
                }
            }
            peerStatusListeners[peerId.rawValue] = handle
            logger.log("[Presence] Added listener for \(peerId.rawValue).")
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
