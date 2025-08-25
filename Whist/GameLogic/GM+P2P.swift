//
//  GM+P2P.swift
//  Whist
//
//  Created by Tony Buffard on 2025-05-24.
//

import Foundation
import SwiftUI
import WebRTC
import FirebaseFirestore

extension GameManager {
    
    func updateLocalPlayer(_ playerId: PlayerId, name: String, image: Image) {
        guard let playerIndex = gameState.players.firstIndex(where: { $0.id == playerId }) else {
            logger.log("Error: Player with ID \(playerId) not found in gameState during update.")
            return
        }
        
        let player = gameState.players[playerIndex]
        player.username = name
        if player.image == nil {
            player.image = image
        }
        
        player.tablePosition = .local
        
        logger.log("Player \(playerId) updated successfully with name: \(name)")
        
        // Log connected players
        let connectedUsernames = gameState.players.filter { $0.isP2PConnected }.map { $0.username }
        logger.log("Players connected: \(connectedUsernames.joined(separator: ", "))")
        displayPlayers() // Log detailed player status
        
        if !gameState.playOrder.isEmpty {
            gameState.updatePlayerReferences()
        }
    }
    
    // MARK: - Signaling Setup
    
    func startNetworkingIfNeeded() {
        guard !preferences.playerId.isEmpty else {
            print("🚫 Cannot start networking: playerId is empty.")
            return
        }
        
        guard !networkingStarted else {
            return
        }
        
        Task {
            networkingStarted = true
            
            let localPlayerIdEnum = PlayerId(rawValue: preferences.playerId)!
            let otherPlayerIds = PlayerId.allCases.filter { $0 != localPlayerIdEnum }
            
            // 1. Setup PresenceManager's callback for peer changes
            PresenceManager.shared.onPeerPresenceChanged = { [weak self] (changedPeerId, isOnline) in
                self?.handlePeerPresenceChange(peerId: changedPeerId, isOnline: isOnline)
            }
            // 2. Start monitoring other peers
            PresenceManager.shared.startMonitoringPeerPresence(for: otherPlayerIds, localPlayerId: localPlayerIdEnum)
            
            await clearSignalingDataIfNeeded()
            
            // Assign FSM callbacks
            signalingManager.onOfferReceived = { [weak self] (fromId, sdp) in
                self?.handleReceivedOffer(from: fromId, sdp: sdp)
            }
            signalingManager.onAnswerReceived = { [weak self] (fromId, sdp) in
                self?.handleReceivedAnswer(from: fromId, sdp: sdp)
            }
            signalingManager.onRemoteIceCandidateReceived = { [weak self] (fromId, candidate) in
                self?.handleReceivedRemoteIceCandidate(from: fromId, candidate: candidate)
            }
            
            setupConnectionManagerCallbacks(localPlayerId: PlayerId(rawValue: preferences.playerId)!)
            signalingManager.setupFirebaseListeners(localPlayerId: PlayerId(rawValue: preferences.playerId)!)
            setupSignaling()
        }
    }
    
    private func clearSignalingDataIfNeeded() async {
        // MODIFICATION: Only clear for the local player
        guard let localPlayerId = PlayerId(rawValue: preferences.playerId) else { // Make sure to get localPlayerId correctly
            logger.log("⚠️ Cannot clear signaling data: localPlayerId not set or invalid from preferences.")
            return
        }
        
        logger.debug("Clearing signaling data for local player: \(localPlayerId.rawValue).")
        do {
            // This clears documents where localPlayerId is the SENDER (e.g., localPlayer_to_peerX)
            try await self.signalingManager.clearSignalingData(for: localPlayerId.rawValue)
            logger.logRTC("Successfully initiated clearing of signaling data for \(localPlayerId.rawValue).")
        } catch {
            logger.log("🚨 Error initiating clearing of signaling data for \(localPlayerId.rawValue): \(error.localizedDescription)")
        }
    }
    
    private func setupSignaling() {
        guard !preferences.playerId.isEmpty else {
            logger.log("setupSignaling: Cannot setup, playerId is empty.")
            return
        }
        
        let localPlayerId = PlayerId(rawValue: preferences.playerId)!
        let otherPlayerIds = PlayerId.allCases.filter { $0 != localPlayerId }
        
        logger.debug("Setting up signaling for \(localPlayerId). Implementing deterministic offer chain.")
        
        Task {
            for peerId in otherPlayerIds {
                if peerId == localPlayerId { continue } // Can't connect to myself
                
                // Determine if the local player should offer to this peer
                var iShouldOffer = false
                switch localPlayerId {
                case .dd:
                    if peerId == .gg { iShouldOffer = true}
                case .gg:
                    if peerId == .toto { iShouldOffer = true}
                case .toto:
                    if peerId == .dd { iShouldOffer = true}
                }
                
                // Before checking presence, set a state
                self.updatePlayerConnectionPhase(playerId: peerId, phase: .initiating)
                
                if !gameState.getPlayer(by: peerId).firebasePresenceOnline {
                    logger.logRTC("Signaling: Peer \(peerId.rawValue) is offline. Will not attempt to offer/answer now.")
                    self.updatePlayerConnectionPhase(playerId: peerId, phase: .idle)
                    continue // Move to the next peer
                }
                
                if iShouldOffer {
                    logger.debug("\(localPlayerId.rawValue) is designated offerer to \(peerId.rawValue). Creating an offer...")
                    self.updatePlayerConnectionPhase(playerId: peerId, phase: .offering)
                    
                    let myOfferToThemDocRef = Firestore.firestore().collection("signaling").document("\(localPlayerId.rawValue)_to_\(peerId.rawValue)")
                    let myOfferSnapshot = try? await myOfferToThemDocRef.getDocument()
                    if let existingOfferData = myOfferSnapshot?.data(), existingOfferData["offer"] != nil {
                        logger.logRTC("Offer from \(localPlayerId.rawValue) to \(peerId.rawValue) already exists. Asusming it's being processed or waiting for answer.")
                        if self.gameState.getPlayer(by: peerId).connectionPhase == .offering {
                            self.updatePlayerConnectionPhase(playerId: peerId, phase: .waitingForAnswer)
                        }
                        continue // Skip creating a new offer if one is already in flight
                    }
                    
                    connectionManager.createOffer(to: peerId) { [weak self] _, result in
                        guard let self = self else {
                            logger.log("GM: attemptP2PConnection: createOffer completion - self is nil for peer \(peerId.rawValue)")
                            return
                        }
                        logger.logRTC("GM: attemptP2PConnection: createOffer completion for \(peerId.rawValue). Result: \(result)")
                        
                        switch result {
                        case .success(let sdp):
                            logger.logRTC("GM: attemptP2PConnection: Offer successfully created for \(peerId.rawValue). Attempting to send via signaling.")
                            Task {
                                do {
                                    try await self.signalingManager.sendOffer(from: localPlayerId, to: peerId, sdp: sdp)
                                    logger.logRTC("GM: attemptP2PConnection: Offer SENT successfully from \(localPlayerId.rawValue) to \(peerId.rawValue).")
                                    self.updatePlayerConnectionPhase(playerId: peerId, phase: .waitingForAnswer)
                                    self.connectionManager.flushPendingIce(for: peerId)
                                } catch {
                                    logger.log("GM: attemptP2PConnection: Error SENDING offer from \(localPlayerId.rawValue) to \(peerId.rawValue): \(error.localizedDescription)")
                                    self.updatePlayerConnectionPhase(playerId: peerId, phase: .failed)
                                }
                            }
                        case .failure(let error):
                            logger.log("GM: attemptP2PConnection: Failed to CREATE offer for \(peerId.rawValue): \(error.localizedDescription)")
                            self.updatePlayerConnectionPhase(playerId: peerId, phase: .failed)
                        }
                    }
                } else {
                    logger.debug("\(localPlayerId.rawValue) is designated answerer for \(peerId.rawValue). Will wait for offer via listener.")
                    self.updatePlayerConnectionPhase(playerId: peerId, phase: .waitingForOffer)
                }
            }
        }
    }
    
    func decodeAndProcessAction(from peerId: PlayerId, message: String) {
        logger.log("Decoding and processing action from \(peerId)...")
        guard let actionData = message.data(using: .utf8) else {
            logger.log("Failed to convert message string to Data from \(peerId)")
            return
        }
        
        do {
            let gameAction = try JSONDecoder().decode(GameAction.self, from: actionData)
            logger.log("Successfully decoded action: \(gameAction.type)")
            // Use handleReceivedAction to process or queue the action
            handleReceivedAction(gameAction)
        } catch {
            logger.log("Failed to decode GameAction from \(peerId): \(error.localizedDescription)")
            logger.log("Raw message data: \(message)") // Log the raw message on error
        }
    }
    
    private func setupConnectionManagerCallbacks(localPlayerId: PlayerId) {
        logger.logRTC(" GM Setup: Setting up P2PConnectionManager callbacks for \(localPlayerId.rawValue).")
        
        connectionManager.onIceCandidateGenerated = { [weak self] (peerId, candidate) in
            // ADD: Log callback execution start
            logger.logRTC(" GM Callback: onIceCandidateGenerated called for peer \(peerId.rawValue).")
            guard let self = self else {
                logger.logRTC(" GM Callback: ERROR - self is nil in onIceCandidateGenerated.")
                return
            }
            // Update phase if it's still in offering/answering
            let player = self.gameState.getPlayer(by: peerId)
            if [.offering, .answering, .waitingForAnswer, .waitingForOffer, .initiating].contains(player.connectionPhase) {
                self.updatePlayerConnectionPhase(playerId: peerId, phase: .exchangingNetworkInfo)
            }
            logger.logRTC(" GM Callback: Starting Task to send ICE candidate from \(localPlayerId.rawValue) to \(peerId.rawValue).")
            Task {
                logger.logRTC(" GM Callback Task: Inside Task. Attempting to send ICE candidate via signalingManager...")
                do {
                    try await self.signalingManager.sendIceCandidate(from: localPlayerId, to: peerId, candidate: candidate)
                    logger.logRTC(" GM Callback Task: signalingManager.sendIceCandidate successful for \(peerId.rawValue).")
                } catch {
                    logger.log(" GM Callback Task: ERROR calling signalingManager.sendIceCandidate for \(peerId.rawValue): \(error)")
                }
            }
        }
        
        connectionManager.onConnectionEstablished = { [weak self] peerId in
            guard let self = self else { return }
            logger.logRTC("✅ P2P Connection established with \(peerId.rawValue)")
            self.cancelConnectionTimer(for: peerId)
            self.updatePlayerConnectionPhase(playerId: peerId, phase: .connected)
            
            // Catchup in case actions were sent while we were offline
            self.scheduleCatchUp(reason: "P2P connection established with \(peerId.rawValue)")
        }
        
        connectionManager.onMessageReceived = { [weak self] (peerId, message) in
            guard let self = self else { return }
            logger.log("📩 P2P Message received from \(peerId.rawValue)")
            self.decodeAndProcessAction(from: peerId, message: message)
        }
        
        connectionManager.onError = { [weak self] (peerId, error) in
            Task { @MainActor in
                guard let self = self else { return }
                logger.log("❌ P2P Error with \(peerId.rawValue): \(error.localizedDescription)")
                self.cancelConnectionTimer(for: peerId)
                self.cancelIceDisconnectionTimer(for: peerId)
                self.updatePlayerConnectionPhase(playerId: peerId, phase: .failed)
            }
        }
        
        connectionManager.onIceConnectionStateChanged = { [weak self] (peerId, newState) in
            Task { @MainActor in
                guard let self = self else { return }
                let player = self.gameState.getPlayer(by: peerId)
                logger.logRTC("GM: ICE Connection State for \(peerId.rawValue) changed to \(newState.rawValue). Current P2P phase: \(player.connectionPhase.rawValue)")

                switch newState {
                case .connected, .completed:
                    self.cancelIceDisconnectionTimer(for: peerId) // Successfully connected or reconnected
                    // Only update to .connected if not already there.
                    // If it was .iceReconnecting, this means recovery was successful.
                    if player.connectionPhase != .connected {
                        logger.logRTC("GM: ICE for \(peerId.rawValue) is now \(newState.rawValue). Updating phase to .connected.")
                        self.updatePlayerConnectionPhase(playerId: peerId, phase: .connected)
                    } else {
                        logger.logRTC("GM: ICE for \(peerId.rawValue) is \(newState.rawValue), phase already .connected.")
                    }
                    
                    // Catchup in case actions were sent while we were offline
                    self.scheduleCatchUp(reason: "ICE \(newState.rawValue) for \(peerId.rawValue)")

                case .disconnected:
                    // ICE connection is temporarily lost. Try to recover.
                    // Only start recovery if we are in a state that expects an active connection
                    // or already trying to connect/reconnect.
                    if player.connectionPhase == .connected ||
                       player.connectionPhase == .connecting ||
                       player.connectionPhase == .exchangingNetworkInfo ||
                       player.connectionPhase == .iceReconnecting { // If already reconnecting, restart timer
                        logger.logRTC("GM: ICE for \(peerId.rawValue) is .disconnected. Updating phase to .iceReconnecting and starting recovery timer.")
                        self.updatePlayerConnectionPhase(playerId: peerId, phase: .iceReconnecting)
                        self.startIceDisconnectionTimer(for: peerId)
                    } else {
                        logger.logRTC("GM: ICE for \(peerId.rawValue) is .disconnected, but current phase \(player.connectionPhase.rawValue) does not warrant ICE recovery attempt now (e.g., still in SDP negotiation or already failed/idle).")
                    }

                case .failed, .closed:
                    // These are handled by connectionManager.onError, which will set phase to .failed.
                    // We also cancel any lingering ICE recovery timer here just in case.
                    logger.logRTC("GM: ICE for \(peerId.rawValue) is \(newState.rawValue). This should be handled by P2PCM's onError. Cancelling ICE recovery timer if any.")
                    self.cancelIceDisconnectionTimer(for: peerId)
                    // If not already failed, mark it as such.
                    // The onError callback in P2PCM should lead to updatePlayerConnectionPhase(.failed)
                    if player.connectionPhase != .failed && player.connectionPhase != .disconnected {
                         // This is a fallback; onError should primarily handle this.
                         self.updatePlayerConnectionPhase(playerId: peerId, phase: .failed)
                         self.connectionManager.closeConnection(for: peerId) // Ensure cleanup
                    }


                case .checking:
                    // Player's phase might be .connecting or .exchangingNetworkInfo
                    // If it was .iceReconnecting, this is a good sign.
                    if player.connectionPhase == .iceReconnecting {
                        logger.logRTC("GM: ICE for \(peerId.rawValue) is .checking (was .iceReconnecting). Recovery seems in progress.")
                    } else if player.connectionPhase != .connected &&
                              player.connectionPhase != .failed &&
                              player.connectionPhase != .disconnected {
                        // Update to .connecting if in an earlier phase like .exchangingNetworkInfo
                        if [.initiating, .offering, .waitingForAnswer, .answering, .waitingForOffer, .exchangingNetworkInfo].contains(player.connectionPhase) {
                            self.updatePlayerConnectionPhase(playerId: peerId, phase: .connecting)
                        }
                    }
                case .new:
                    logger.logRTC("GM: ICE for \(peerId.rawValue) is .new.")
                default:
                    logger.logRTC("GM: ICE for \(peerId.rawValue) entered an unknown state: \(newState.rawValue).")
                }
            }
        }
        
        connectionManager.onSignalingStateChanged = { [weak self] (peerId, newState) in
            guard self != nil else { return }
            logger.logRTC("GM: Signaling State for \(peerId) changed to \(newState.rawValue)")
        }
        
        logger.log(" GM Setup: Finished setting up P2PConnectionManager callbacks.")// ADD: Log setup finish
    }
    
    // Helper to update phase and trigger UI refresh
    @MainActor
    private func updatePlayerConnectionPhase(playerId: PlayerId, phase: P2PConnectionPhase) {
        guard let playerIndex = gameState.players.firstIndex(where: { $0.id == playerId }) else {
            logger.log("Error: Player \(playerId) not found to update connection phase.")
            return
        }
        if gameState.players[playerIndex].connectionPhase != phase {
            cancelConnectionTimer(for: playerId)
            cancelIceDisconnectionTimer(for: playerId)
            gameState.players[playerIndex].connectionPhase = phase
            logger.logRTC("Player \(playerId) phase -> \(phase.rawValue)")
            
            // Start new timer based on phase
            switch phase {
            case .waitingForOffer:
                startConnectionTimer(for: playerId, timeout: offerWaitTimeout, timedOutPhase: phase)
            case .waitingForAnswer:
                startConnectionTimer(for: playerId, timeout: answerWaitTimeout, timedOutPhase: phase)
            case .exchangingNetworkInfo, .connecting: // Group these as post-SDP exchange
                startConnectionTimer(for: playerId, timeout: iceExchangeTimeout, timedOutPhase: phase)
            case .offering, .answering: // These phases should also have a timeout if they get stuck before transitioning
                startConnectionTimer(for: playerId, timeout: answerWaitTimeout, timedOutPhase: phase) // Reuse answerWait or a specific one
            case .connected, .failed, .disconnected, .idle, .initiating, .iceReconnecting:
                // No timer needed or implicitly covered, existing timer already cancelled.
                break
            }
            
            displayPlayers()
            
            if phase == .connected {
                checkAndAdvanceStateIfNeeded()
            }
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
    
    private func startConnectionTimer(for peerId: PlayerId, timeout: TimeInterval, timedOutPhase: P2PConnectionPhase) {
        // Ensure no duplicate timer
        connectionAttemptTimers[peerId]?.invalidate()
        
        logger.logRTC("GM: Starting \(timeout)s connection timer for \(peerId.rawValue) (phase: \(timedOutPhase.rawValue)).")
        let timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let strongSelf = self,
                      let player = strongSelf.gameState.players.first(where: { $0.id == peerId }),
                      player.connectionPhase == timedOutPhase else {
                    logger.logRTC("GM: Connection timer fired for \(peerId.rawValue) (was in \(timedOutPhase.rawValue)), but state already changed or self deallocated. Ignoring.")
                    self?.connectionAttemptTimers.removeValue(forKey: peerId) // Clean up entry
                    return
                }
                logger.logRTC("GM: Connection timer FIRED for \(peerId.rawValue) (phase: \(timedOutPhase.rawValue)).")
                strongSelf.handleConnectionTimeout(for: peerId, timedOutPhase: timedOutPhase)
            }
        }
        connectionAttemptTimers[peerId] = timer
    }
    
    private func cancelConnectionTimer(for peerId: PlayerId) {
        if let timer = connectionAttemptTimers[peerId] {
            timer.invalidate()
            connectionAttemptTimers.removeValue(forKey: peerId)
            logger.logRTC("GM: Cancelled connection timer for \(peerId.rawValue).")
        }
    }
    
    
    @MainActor
    private func handleConnectionTimeout(for peerId: PlayerId, timedOutPhase: P2PConnectionPhase) {
        logger.log("GM: Handling connection TIMEOUT for \(peerId.rawValue). Player was in phase: \(timedOutPhase.rawValue).")
        
        // Mark as failed first
        updatePlayerConnectionPhase(playerId: peerId, phase: .failed) // This will also cancel the timer
        
        // Clean up local WebRTC resources for this peer
        connectionManager.closeConnection(for: peerId)
        
        let localPlayerId = PlayerId(rawValue: preferences.playerId)!
        
        Task {
            logger.logRTC("GM: Timeout - Attempting to clear signaling documents between \(localPlayerId.rawValue) and \(peerId.rawValue).")
            do {
                // Clear signaling documents for this specific pair
                try await FirebaseSignalingManager.shared.clearSignalingDocuments(between: localPlayerId, and: peerId)
                logger.logRTC("GM: Timeout - Successfully cleared signaling documents for pair involving \(peerId.rawValue).")
                
                // After clearing, if the peer is still marked as online by PresenceManager,
                // try to re-initiate the connection.
                if let player = gameState.players.first(where: { $0.id == peerId }), player.firebasePresenceOnline {
                    logger.logRTC("GM: Timeout - Peer \(peerId.rawValue) is still online. Re-attempting P2P connection.")
                    // Add a small delay before re-attempting to avoid rapid fire retries
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                    if player.firebasePresenceOnline { // Re-check after delay
                        attemptP2PConnection(with: peerId)
                    } else {
                        logger.logRTC("GM: Timeout - Peer \(peerId.rawValue) went offline during timeout handling delay.")
                        updatePlayerConnectionPhase(playerId: peerId, phase: .disconnected) // Or .idle
                    }
                } else {
                    logger.logRTC("GM: Timeout - Peer \(peerId.rawValue) is not online or not found. Will not auto-retry now.")
                    // The phase is already .failed. If they come back online, presence will trigger new attempt.
                }
            } catch {
                logger.log("GM: Timeout - FAILED to clear signaling documents for pair involving \(peerId.rawValue): \(error.localizedDescription)")
                // Connection is already marked as .failed.
            }
        }
    }
    
    // MARK: Handler methods
    @MainActor
    func handleReceivedOffer(from peerId: PlayerId, sdp: RTCSessionDescription) {
        guard gameState.getPlayer(by: peerId).firebasePresenceOnline else {
            logger.logRTC("GM: handleReceivedOffer: Received offer from \(peerId.rawValue), but they are marked as OFFLINE. Ignoring stale offer.")
            // Optionally, try to delete the stale offer document here:
            // Task {
            //     let localPlayerId = PlayerId(rawValue: preferences.playerId)!
            //     try? await FirebaseSignalingManager.shared.clearSignalingDocuments(between: peerId, and: localPlayerId) // Clears both ways, or just peerId_to_localPlayerId
            // }
            return
        }
        logger.logRTC("GM: handleReceivedOffer: CALLED for \(peerId.rawValue). SDP Type: \(sdp.type.rawValue). Current phase for \(peerId.rawValue): \(self.gameState.getPlayer(by: peerId).connectionPhase.rawValue)")
        
        // Pull or create the RTCPeerConnection for this peer
        let connection = connectionManager.makePeerConnection(for: peerId)
        // Only accept if WebRTC is in a state that can take a new remote offer
        var iShouldOffer = false // Recalculate my role with respect to peerId
        let localPlayerId = PlayerId(rawValue: preferences.playerId)!
        switch localPlayerId {
        case .dd: if peerId == .gg { iShouldOffer = true }
        case .gg: if peerId == .toto { iShouldOffer = true }
        case .toto: if peerId == .dd { iShouldOffer = true }
        }
        
        if iShouldOffer && (connection.signalingState == .haveLocalOffer || connection.signalingState == .stable) {
            // I am the offerer, and I've either sent an offer or connection is stable.
            // This incoming offer is either a glare case or a duplicate.
            logger.logRTC("GM: handleReceivedOffer: I am designated offerer (\(localPlayerId.rawValue) to \(peerId.rawValue)) and my state is \(connection.signalingState.rawValue). Ignoring incoming offer from \(peerId.rawValue) to prevent glare or reprocessing.")
            return
        }
        
        if !iShouldOffer { // I am the designated answerer...
            // ... and I have already processed an offer and sent an answer (my PC state for them is stable, or I'm exchanging ICE).
            // RTCSignalingState.stable (0) means negotiation is complete.
            // RTCSignalingState.haveLocalPrAnswer / haveRemotePrAnswer also indicate I've answered.
            // If player's connectionPhase indicates I've already answered or connected...
            let playerForPeer = gameState.getPlayer(by: peerId)
            if playerForPeer.connectionPhase == .answering ||
                playerForPeer.connectionPhase == .exchangingNetworkInfo ||
                playerForPeer.connectionPhase == .connecting ||
                playerForPeer.connectionPhase == .connected {
                if connection.signalingState == .stable {
                    logger.logRTC("GM: handleReceivedOffer: I am designated answerer (\(localPlayerId.rawValue) for \(peerId.rawValue)), but my PlayerPhase for them is \(playerForPeer.connectionPhase.rawValue) and PC state is stable. Ignoring likely duplicate/late offer from \(peerId.rawValue).")
                    return
                }
            }
            
        }
        
        // If signaling state is stable, and we receive an offer, it's a re-negotiation or a late/duplicate.
        // If we are not expecting an offer (e.g., we sent one), we might need to handle glare.
        // For now, let's assume if we get here, we should process it if we haven't established a connection yet.
        // The key is the `connection.signalingState` before setting remote description.
        // It should be `stable` (initial state) or `haveRemoteOffer` (if a previous offer was received but not answered yet).
        // It should NOT be `haveLocalOffer` (I sent offer, waiting for answer) or `haveLocalPrAnswer` or `haveRemotePrAnswer`.
        
        if connection.signalingState != .stable && connection.signalingState != .haveRemoteOffer {
            // This check is a bit too simple, need to consider re-negotiation.
            // For initial connection, if I'm the answerer, my state for them should be .stable or .waitingForOffer which maps to .stable PC state.
            logger.logRTC("GM: handleReceivedOffer: Received offer from \(peerId.rawValue), but my SignalingState for them is \(connection.signalingState.rawValue). This might be unexpected. Proceeding cautiously.")
        }
        
        // Update phase: we are now going to answer
        self.updatePlayerConnectionPhase(playerId: peerId, phase: .answering)
        
        Task { // Perform async WebRTC operations
            
            // Create answer
            self.connectionManager.createAnswer(to: peerId, from: sdp) { [weak self] answeredPeerId, result in
                guard let self = self else { return }
                switch result {
                case .success(let answerSdp):
                    logger.logRTC("GM: Created answer for \(answeredPeerId). Sending...")
                    Task {
                        do {
                            try await self.signalingManager.sendAnswer(from: PlayerId(rawValue: self.preferences.playerId)!, to: answeredPeerId, sdp: answerSdp)
                            logger.logRTC("GM: Successfully sent answer to \(answeredPeerId)")
                            // Now we are waiting for the connection to establish, ICE exchange is likely ongoing
                            // The phase might already be .exchangingNetworkInfo due to local ICE generation
                            // or can be explicitly set.
                            if self.gameState.getPlayer(by: answeredPeerId).connectionPhase != .exchangingNetworkInfo {
                                self.updatePlayerConnectionPhase(playerId: answeredPeerId, phase: .exchangingNetworkInfo) // Or a more specific "WaitingForConnection"
                            }
                            self.connectionManager.flushPendingIce(for: answeredPeerId)
                            
                            // Clear the offer field in Firestore (optional, but good practice)
                            let offerPath = "offer"
                            let docId = self.signalingManager.documentName(from: answeredPeerId, to: PlayerId(rawValue: self.preferences.playerId)!) // FSM needs public documentName
                            try? await Firestore.firestore().collection("signaling").document(docId).updateData([offerPath: FieldValue.delete()])
                            logger.logRTC("GM: Cleared offer field for \(answeredPeerId) in \(docId)")
                        } catch {
                            logger.log("GM: Error sending answer to \(answeredPeerId): \(error)")
                            self.updatePlayerConnectionPhase(playerId: answeredPeerId, phase: .failed)
                        }
                    }
                case .failure(let err):
                    logger.log("GM: Failed to create answer for \(answeredPeerId): \(err)")
                    self.updatePlayerConnectionPhase(playerId: answeredPeerId, phase: .failed)
                }
            }
            
        }
    }
    
    @MainActor
    func handleReceivedAnswer(from peerId: PlayerId, sdp: RTCSessionDescription) {
        logger.logRTC("GM: Handling received ANSWER from \(peerId.rawValue)")
        
        guard let connection = connectionManager.peerConnections[peerId] else {
            logger.log("GM: Warning: Received answer from \(peerId), but no peer connection exists. THIS SHOULD NOT HAPPEN IF OFFER WAS SENT.")
            // This path indicates a logic error, as an offerer should always have a PC.
            // Potentially the PC was closed prematurely or never properly established on the offerer's side.
            self.updatePlayerConnectionPhase(playerId: peerId, phase: .failed)
            return
        }
        
        // CRITICAL: Only process answer if we are expecting one
        if connection.signalingState == .haveLocalOffer {
            logger.logRTC("GM: SignalingState is haveLocalOffer for \(peerId), proceeding to set remote answer.")
            self.updatePlayerConnectionPhase(playerId: peerId, phase: .exchangingNetworkInfo) // Or .connecting
            
            Task {
                do {
                    try await connection.setRemoteDescription(sdp) // This is an async RTC method
                    logger.logRTC("GM: Remote answer from \(peerId) set successfully.")
                    self.connectionManager.flushPendingIce(for: peerId)
                    
                    // Clear the answer field in Firestore
                    let answerPath = "answer"
                    // The document is named by the ANSWERER_to_OFFERER
                    let docId = self.signalingManager.documentName(from: peerId, to: PlayerId(rawValue: self.preferences.playerId)!)
                    try? await Firestore.firestore().collection("signaling").document(docId).updateData([answerPath: FieldValue.delete()])
                    logger.logRTC("GM: Cleared answer field for \(peerId) in \(docId)")
                    
                } catch {
                    logger.log("GM: Failed to set remote answer from \(peerId): \(error.localizedDescription)")
                    self.updatePlayerConnectionPhase(playerId: peerId, phase: .failed)
                }
            }
        } else {
            logger.logRTC("GM: Received answer from \(peerId), but SignalingState is \(connection.signalingState.rawValue) (expected haveLocalOffer). Ignoring duplicate/late answer.")
            // If already stable, and connection is good, no action needed.
            // If some other state, it might indicate an issue, but processing answer now is wrong.
        }
    }
    
    
    @MainActor
    func handleReceivedRemoteIceCandidate(from peerId: PlayerId, candidate: RTCIceCandidate) {
        let player = self.gameState.getPlayer(by: peerId)
        logger.logRTC("Handling received ICE candidate from \(peerId.rawValue). Current phase for peer \(peerId.rawValue) is \(player.connectionPhase.rawValue).")

        var iAmOffererToThisPeer = false
        let localPlayerId = PlayerId(rawValue: preferences.playerId)!
        switch localPlayerId {
            case .dd: if peerId == .gg { iAmOffererToThisPeer = true }
            case .gg: if peerId == .toto { iAmOffererToThisPeer = true }
            case .toto: if peerId == .dd { iAmOffererToThisPeer = true }
        }

        if !iAmOffererToThisPeer { // I am the ANSWERER for this peer
            // If I am an answerer and still waiting for an offer, or in idle/initiating,
            // receiving remote ICE should NOT change my overall connection phase for this peer yet.
            // The phase should only advance to .answering or .exchangingNetworkInfo *after* I've processed their offer.
            if player.connectionPhase == .waitingForOffer || player.connectionPhase == .idle || player.connectionPhase == .initiating {
                 logger.logRTC("Answerer (for \(peerId.rawValue)) received remote ICE while in phase \(player.connectionPhase.rawValue). Storing ICE, but NOT changing phase to .exchangingNetworkInfo yet.")
            } else if player.connectionPhase == .answering && player.connectionPhase != .exchangingNetworkInfo && player.connectionPhase != .connecting && player.connectionPhase != .connected {
                // If I'm in .answering (meaning offer processed, answer being created/sent)
                // then it's appropriate to move to .exchangingNetworkInfo.
                // This transition might also be triggered by my *own* ICE generation callback.
                 logger.logRTC("Answerer (for \(peerId.rawValue)) in .answering phase received remote ICE. Transitioning to .exchangingNetworkInfo.")
                self.updatePlayerConnectionPhase(playerId: peerId, phase: .exchangingNetworkInfo)
            }
        } else { // I am the OFFERER for this peer
            // If I'm offerer, sent offer, waiting for answer. Receiving their ICE means they are working on it.
            // Transitioning to .exchangingNetworkInfo is reasonable.
            // This might also be triggered by my *own* ICE generation callback.
            if (player.connectionPhase == .offering || player.connectionPhase == .waitingForAnswer) &&
               player.connectionPhase != .exchangingNetworkInfo && player.connectionPhase != .connecting && player.connectionPhase != .connected {
                 logger.logRTC("Offerer (for \(peerId.rawValue)) in \(player.connectionPhase.rawValue) phase received remote ICE. Transitioning to .exchangingNetworkInfo.")
                self.updatePlayerConnectionPhase(playerId: peerId, phase: .exchangingNetworkInfo)
            }
        }
        // If already in .exchangingNetworkInfo, .connecting, .connected, no further phase change related to this is needed here.

        P2PConnectionManager.shared.addIceCandidate(candidate, for: peerId) { error in
            if let error = error {
                // Log the localized description of the error
                logger.log("Error adding received ICE candidate from \(peerId): \(error.localizedDescription)")
            }
        }
    }
    
    @MainActor
    private func handlePeerPresenceChange(peerId: PlayerId, isOnline: Bool) {
        logger.logRTC("Handling presence change for \(peerId.rawValue). Online: \(isOnline)")
        
        let player = gameState.getPlayer(by: peerId)
        player.firebasePresenceOnline = isOnline
        
        if isOnline {
            // Peer came online or is confirmed online.
            // Only attempt connection if currently idle, failed, or disconnected from P2P.
            let currentPhase = player.connectionPhase
            if currentPhase == .idle || currentPhase == .failed || currentPhase == .disconnected {
                logger.logRTC("Peer \(peerId.rawValue) is online and in phase '\(currentPhase.rawValue)'. Attempting P2P connection.")
                attemptP2PConnection(with: peerId)
            } else {
                logger.logRTC("Peer \(peerId.rawValue) is online, P2P phase '\(currentPhase.rawValue)' indicates attempt in progress/established. No new action.")
            }
        } else {
            // Peer went offline.
            logger.logRTC("Peer \(peerId.rawValue) went offline.")
            self.cancelConnectionTimer(for: peerId)
            self.cancelIceDisconnectionTimer(for: peerId)
            // Update connection status
            if player.isP2PConnected ||
                [.initiating, .offering, .waitingForAnswer, .answering, .waitingForOffer, .exchangingNetworkInfo, .connecting].contains(player.connectionPhase) {
                updatePlayerConnectionPhase(playerId: peerId, phase: .disconnected) // Sets phase
            } else {
                // If it wasn't even WebRTC connected, ensure its phase reflects it's gone
                updatePlayerConnectionPhase(playerId: peerId, phase: .idle) // Or a new "PeerOffline" phase
            }
            
            // Clear any related signaling data for this peer if appropriate.
            connectionManager.closeConnection(for: peerId)
        }
        
        displayPlayers()
    }
    
    @MainActor
    private func attemptP2PConnection(with peerId: PlayerId) {
        let localPlayerId = PlayerId(rawValue: preferences.playerId)!
        let player = gameState.getPlayer(by: peerId) // Get the player object
        let previousConnectionPhase = player.connectionPhase

        logger.logRTC("GM: Attempting P2P with \(peerId.rawValue). Peer's previous P2P phase: \(player.connectionPhase.rawValue), Firebase Online: \(player.firebasePresenceOnline)")

        var iShouldOffer = false
        switch localPlayerId {
            case .dd: if peerId == .gg { iShouldOffer = true }
            case .gg: if peerId == .toto { iShouldOffer = true }
            case .toto: if peerId == .dd { iShouldOffer = true }
        }

        // Reset phase to initiating to ensure fresh start, timers get cancelled.
        self.updatePlayerConnectionPhase(playerId: peerId, phase: .initiating)

        if iShouldOffer {
            logger.debug("\(localPlayerId.rawValue) is designated offerer to \(peerId.rawValue). Creating an offer...")
            self.updatePlayerConnectionPhase(playerId: peerId, phase: .offering)

            Task {
                let offerDocId = "\(localPlayerId.rawValue)_to_\(peerId.rawValue)"
                let myOfferToThemDocRef = Firestore.firestore().collection("signaling").document(offerDocId)

                let wasPreviouslyDisconnectedOrFailed = previousConnectionPhase == .disconnected || previousConnectionPhase == .failed
                if wasPreviouslyDisconnectedOrFailed {
                     logger.logRTC("Offerer \(localPlayerId.rawValue): Peer \(peerId.rawValue) is rejoining. Clearing any old offer \(offerDocId) before sending a new one.")
                     try? await myOfferToThemDocRef.delete()
                }

                connectionManager.createOffer(to: peerId) { [weak self] _, result in
                    guard let self = self else { return }
                    switch result {
                    case .success(let sdp):
                        Task {
                            do {
                                logger.logRTC("GM: Offerer \(localPlayerId.rawValue) SENDING NEW offer to rejoining/new peer \(peerId.rawValue).")
                                try await self.signalingManager.sendOffer(from: localPlayerId, to: peerId, sdp: sdp)
                                self.updatePlayerConnectionPhase(playerId: peerId, phase: .waitingForAnswer)
                                self.connectionManager.flushPendingIce(for: peerId)
                            } catch {
                                logger.log("GM: Error SENDING offer to \(peerId.rawValue) (rejoin attempt): \(error.localizedDescription)")
                                self.updatePlayerConnectionPhase(playerId: peerId, phase: .failed)
                            }
                        }
                    case .failure(let error):
                        logger.log("GM: Failed to CREATE offer for \(peerId.rawValue) (rejoin attempt): \(error.localizedDescription)")
                        self.updatePlayerConnectionPhase(playerId: peerId, phase: .failed)
                    }
                }
            }
        } else { // I am ANSWERER to this peer
            logger.debug("\(localPlayerId.rawValue) is designated answerer for \(peerId.rawValue). Will wait for offer via listener.")
            self.updatePlayerConnectionPhase(playerId: peerId, phase: .waitingForOffer)
            // Listener (onOfferReceived) will handle it.
        }
    }

    @MainActor
    private func startIceDisconnectionTimer(for peerId: PlayerId) {
        // Cancel any existing timer for this peer first
        cancelIceDisconnectionTimer(for: peerId)

        logger.logRTC("GM: Starting \(iceDisconnectionRecoveryTimeout)s ICE disconnection recovery timer for \(peerId.rawValue).")
        let timer = Timer.scheduledTimer(withTimeInterval: iceDisconnectionRecoveryTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleIceDisconnectionTimeout(for: peerId)
            }
        }
        iceDisconnectionTimers[peerId] = timer
    }

    @MainActor
    private func cancelIceDisconnectionTimer(for peerId: PlayerId) {
        if let timer = iceDisconnectionTimers[peerId] {
            timer.invalidate()
            iceDisconnectionTimers.removeValue(forKey: peerId)
            logger.logRTC("GM: Cancelled ICE disconnection recovery timer for \(peerId.rawValue).")
        }
    }

    @MainActor
    private func handleIceDisconnectionTimeout(for peerId: PlayerId) {
        guard let player = gameState.players.first(where: { $0.id == peerId }) else {
            logger.logRTC("GM: ICE Disconnection Timer: Peer \(peerId.rawValue) not found.")
            iceDisconnectionTimers.removeValue(forKey: peerId) // Clean up just in case
            return
        }

        // Check if the connection recovered or failed further *before* the timer fired and changed phase
        if player.connectionPhase != .iceReconnecting {
            logger.logRTC("GM: ICE Disconnection Timer fired for \(peerId.rawValue), but phase is now \(player.connectionPhase.rawValue). Assuming resolved or handled elsewhere.")
            iceDisconnectionTimers.removeValue(forKey: peerId) // Ensure cleanup if timer fired for an old state
            return
        }

        logger.logRTC("GM: ICE Disconnection TIMEOUT for \(peerId.rawValue). ICE did not recover from .disconnected state. Marking as failed.")
        iceDisconnectionTimers.removeValue(forKey: peerId) // Remove the fired timer

        // Treat as a full P2P failure for this peer
        updatePlayerConnectionPhase(playerId: peerId, phase: .failed) // This will also cancel other timers
        connectionManager.closeConnection(for: peerId) // Clean up WebRTC resources

        // Optionally, attempt to reconnect if peer is still "online" according to Firebase Presence
        if player.firebasePresenceOnline {
            logger.logRTC("GM: ICE Disconnection Timeout - Peer \(peerId.rawValue) is still Firebase-online. Attempting full P2P reconnection.")
            Task {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                    if gameState.getPlayer(by: peerId).firebasePresenceOnline { // Re-check after delay
                         attemptP2PConnection(with: peerId)
                    } else {
                        logger.logRTC("GM: ICE Disconnection Timeout - Peer \(peerId.rawValue) went offline during retry delay.")
                        updatePlayerConnectionPhase(playerId: peerId, phase: .disconnected) // Mark as fully disconnected
                    }
                } catch {
                     logger.log("GM: ICE Disconnection Timeout - Sleep interrupted during retry prep for \(peerId.rawValue).")
                }
            }
        } else {
            logger.logRTC("GM: ICE Disconnection Timeout - Peer \(peerId.rawValue) is not Firebase-online. Will not auto-retry P2P now.")
        }
    }
    
    //MARK: CatchUp
    func scheduleCatchUp(reason: String) {
        guard canCatchUp else {
            logger.debug("Cannot catch up now.")
            return
        }
        catchUpWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            logger.log("🔄 Catch-up triggered (\(reason)). From seq \(self.lastAppliedSequence + 1)")
            self.requestCatchUp(from: self.lastAppliedSequence + 1)
        }
        catchUpWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
