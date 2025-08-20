//
//  P2PConnectionManager.swift
//  Whist
//
//  Created by Tony Buffard on 2025-04-19.
//

import Foundation
import WebRTC

class P2PConnectionManager: NSObject {
    static let shared = P2PConnectionManager()

    // CHANGE: Rename dataChannels to outgoingDataChannels for clarity
    private var outgoingDataChannels: [PlayerId: RTCDataChannel] = [:]
    // ADD: Dictionary to map incoming data channels to their peer ID
    private var incomingDataChannelsMap: [RTCDataChannel: PlayerId] = [:]
    private var remoteCandidates: [PlayerId: [RTCIceCandidate]] = [:]
    private var pendingIceCandidates: [PlayerId: [RTCIceCandidate]] = [:]
    // Queue of unsent messages for each peer. Messages are flushed when the
    // corresponding data channel becomes available.
    private var messageQueues: [PlayerId: [String]] = [:]
    
    var peerConnections: [PlayerId: RTCPeerConnection] = [:]
    var onMessageReceived: ((PlayerId, String) -> Void)?
    var onConnectionEstablished: ((PlayerId) -> Void)?
    var onIceCandidateGenerated: ((PlayerId, RTCIceCandidate) -> Void)?
    var onIceConnectionStateChanged: ((_ peerId: PlayerId, _ newState: RTCIceConnectionState) -> Void)?
    var onSignalingStateChanged: ((_ peerId: PlayerId, _ newState: RTCSignalingState) -> Void)?
    var onError: ((PlayerId, Error) -> Void)?

    enum Secrets {
        static var username: String {
            getValue(for: "TURNUsername")
        }

        static var credential: String {
            getValue(for: "TURNCredential")
        }

        private static func getValue(for key: String) -> String {
            guard let path = Bundle.main.path(forResource: "Secrets", ofType: "plist"),
                  let dict = NSDictionary(contentsOfFile: path),
                  let value = dict[key] as? String else {
                fatalError("Missing or invalid key \(key) in Secrets.plist")
            }
            return value
        }
    }

    private let factory: RTCPeerConnectionFactory = {
        RTCInitializeSSL()
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
    }()

    private lazy var config: RTCConfiguration = {
        let config = RTCConfiguration()
        config.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.relay.metered.ca:80"]),
            RTCIceServer(
                urlStrings: ["turn:na.relay.metered.ca:80"],
                username: Secrets.username,
                credential: Secrets.credential
            ),
            RTCIceServer(
                urlStrings: ["turn:na.relay.metered.ca:80?transport=tcp"],
                username: Secrets.username,
                credential: Secrets.credential
            ),
            RTCIceServer(
                urlStrings: ["turn:na.relay.metered.ca:443"],
                username: Secrets.username,
                credential: Secrets.credential
            ),
            RTCIceServer(
                urlStrings: ["turns:na.relay.metered.ca:443?transport=tcp"],
                username: Secrets.username,
                credential: Secrets.credential
            )
        ]
        config.sdpSemantics = .unifiedPlan
        config.iceTransportPolicy = .all
        return config
    }()

    private let constraints = RTCMediaConstraints(
        mandatoryConstraints: nil,
        optionalConstraints: ["DtlsSrtpKeyAgreement": kRTCMediaConstraintsValueTrue]
    )

    /// Creates or returns an existing RTCPeerConnection for the given peerId,
    /// sets this class as its delegate, and initializes a data channel.
    func makePeerConnection(for peerId: PlayerId) -> RTCPeerConnection {
        if let pc = peerConnections[peerId] {
             // Ensure an outgoing data channel exists if the connection already exists
             if outgoingDataChannels[peerId] == nil, let pc = peerConnections[peerId] {
                 createAndStoreOutgoingDataChannel(for: peerId, on: pc)
             }
            return pc
        }
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            logger.fatalErrorAndLog("P2PConnectionManager: failed to create RTCPeerConnection")
        }
        peerConnections[peerId] = pc
        // Create and store the outgoing data channel
        createAndStoreOutgoingDataChannel(for: peerId, on: pc)
        return pc
    }

    // ADD: Helper function to create and store the outgoing data channel
    private func createAndStoreOutgoingDataChannel(for peerId: PlayerId, on pc: RTCPeerConnection) {
         let dataChannelConfig = RTCDataChannelConfiguration()
         dataChannelConfig.isOrdered = true
         // Use the peerId (recipient) as the label for the outgoing channel
         if let channel = pc.dataChannel(forLabel: peerId.rawValue, configuration: dataChannelConfig) {
             channel.delegate = self // Also set delegate for outgoing channel state changes
             outgoingDataChannels[peerId] = channel // Store in outgoing map
             logger.logRTC("Created and stored outgoing data channel labeled '\(peerId.rawValue)' for peer \(peerId.rawValue)")
         } else {
             logger.log("Error: Failed to create outgoing data channel for \(peerId.rawValue)")
         }
    }

    private override init() {
        super.init()
    }

    deinit { cleanup() }

    func cleanup() {
        // Close both outgoing and incoming channels
        outgoingDataChannels.values.forEach { $0.close() }
        incomingDataChannelsMap.keys.forEach { $0.close() } // Close incoming channels
        peerConnections.values.forEach { $0.close() }
        outgoingDataChannels.removeAll()
        incomingDataChannelsMap.removeAll() // Clear incoming map
        peerConnections.removeAll()
        remoteCandidates.removeAll()
    }

    func createOffer(to peerId: PlayerId, completion: @escaping (PlayerId, Result<RTCSessionDescription, Error>) -> Void) {
        logger.logRTC("CALLED for peer \(peerId.rawValue)")
        let connection = makePeerConnection(for: peerId)

        connection.offer(for: constraints) { [weak self] (sdp: RTCSessionDescription?, error: Error?) in
            guard self != nil else {
                logger.log("Completion invoked but self is nil for \(peerId.rawValue)")
                return
            }

            if let error = error {
                logger.log("FAILED to create offer for \(peerId.rawValue). Error: \(error.localizedDescription)")
                completion(peerId, .failure(error))
                return
            }

            guard let sdp = sdp else {
                let offerError = NSError(domain: "P2PConnectionManager", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Failed to create offer, SDP is nil"])
                logger.log("FAILED for \(peerId.rawValue). SDP is nil.")
                completion(peerId, .failure(offerError))
                return
            }

            logger.logRTC("Offer SDP CREATED for \(peerId.rawValue). Type: \(sdp.type.rawValue). Now setting local description.")

            connection.setLocalDescription(sdp) { (error: Error?) in
                if let error = error {
                    logger.log("setLocalDescription FAILED for offer to \(peerId.rawValue). Error: \(error.localizedDescription)")
                    completion(peerId, .failure(error))
                    return
                }
                logger.logRTC("Local description (offer) SET SUCCESSFULLY for \(peerId.rawValue). Calling completion.")
                completion(peerId, .success(sdp))
            }
        }
        logger.logRTC("Native offer method CALLED for \(peerId.rawValue). Waiting for its completion.")
    }

    func createAnswer(to peerId: PlayerId, from remoteSDP: RTCSessionDescription, completion: @escaping (PlayerId, Result<RTCSessionDescription, Error>) -> Void) {
        logger.logRTC("P2PCM: createAnswer: CALLED for peer \(peerId.rawValue), from remoteSDP type: \(remoteSDP.type.rawValue)")

        let connection = makePeerConnection(for: peerId)
        logger.logRTC("P2PCM: createAnswer: Setting remote description (offer) for \(peerId.rawValue).")

        // Ensure remote description is set before creating answer (moved from original setRemoteDescription logic for clarity)
         connection.setRemoteDescription(remoteSDP) { [weak self] error in
             guard let strongSelf = self else {
                 logger.log("P2PCM: createAnswer: setRemoteDescription completion - self is nil for \(peerId.rawValue)")
                 return
             }
             if let error = error {
                 logger.log("P2PCM: createAnswer: FAILED setting remote description (offer) for \(peerId.rawValue): \(error.localizedDescription)")
                 completion(peerId, .failure(error))
                 return
             }
             logger.logRTC("P2PCM: createAnswer: Remote description (offer) SET SUCCESSFULLY for \(peerId.rawValue). Now creating actual answer SDP.")

             // Now create the answer
             connection.answer(for: strongSelf.constraints) { (sdp: RTCSessionDescription?, error: Error?) in
                if let error = error {
                    logger.log("P2PCM: createAnswer: FAILED to generate answer SDP for \(peerId.rawValue). Error: \(error.localizedDescription)")
                    completion(peerId, .failure(error))
                    return
                }

                 guard let sdp = sdp else {
                     let answerError = NSError(domain: "P2PConnectionManager", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Failed to create answer, SDP is nil"])
                     logger.log("P2PCM: createAnswer: FAILED for \(peerId.rawValue). Answer SDP is nil.")
                     completion(peerId, .failure(answerError))
                     return
                     
                }
                 logger.logRTC("P2PCM: createAnswer: Answer SDP CREATED for \(peerId.rawValue). Type: \(sdp.type.rawValue). Now setting local description.")

                connection.setLocalDescription(sdp) { (error: Error?) in
                    if let error = error {
                        logger.log("P2PCM: createAnswer: setLocalDescription (answer) FAILED for \(peerId.rawValue). Error: \(error.localizedDescription)")

                        completion(peerId, .failure(error))
                        return
                    }
                    logger.logRTC("P2PCM: createAnswer: Local description (answer) SET SUCCESSFULLY for \(peerId.rawValue). Calling completion.")
                    completion(peerId, .success(sdp))
                }
            }
        }
        logger.logRTC("P2PCM: createAnswer: Native setRemoteDescription and answer methods CALLED for \(peerId.rawValue). Waiting for completions.")

    }

    func setRemoteDescription(for peerId: PlayerId, _ sdp: RTCSessionDescription, completion: @escaping (Error?) -> Void) {
        let pc = peerConnections[peerId] ?? makePeerConnection(for: peerId)

        pc.setRemoteDescription(sdp) { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                 logger.log("Error setting remote description for \(peerId): \(error)")
                completion(error)
                return
            }
             logger.logRTC("Successfully set remote description for \(peerId). Type: \(sdp.type.rawValue)")


            // Apply any stored remote candidates once remote description is set
            // Ensure this doesn't conflict with ICE candidate handling elsewhere
            if let candidates = self.remoteCandidates[peerId], !candidates.isEmpty {
                logger.logRTC("Applying \(candidates.count) stored remote ICE candidates for \(peerId).")
                for candidate in candidates {
                    pc.add(candidate) { error in
                        if let error = error {
                            logger.log("Error adding stored ICE candidate for \(peerId): \(error)")
                        } else {
                            logger.logRTC("Successfully added stored ICE candidate for \(peerId).")
                        }
                    }
                }
                 self.remoteCandidates.removeValue(forKey: peerId) // Clear applied candidates
            }
            completion(nil)
        }
    }

    func addIceCandidate(_ candidate: RTCIceCandidate, for peerId: PlayerId, completion: ((Error?) -> Void)? = nil) {
        guard let pc = peerConnections[peerId] else {
             logger.logRTC("addIceCandidate: No peer connection found for \(peerId). Storing candidate.")
             pendingIceCandidates[peerId, default: []].append(candidate) // Store candidate if PC doesn't exist yet
             completion?(nil)
             return
        }

        // Check remote description state before adding candidate
        if pc.remoteDescription != nil {
             logger.logRTC("addIceCandidate: Remote description exists for \(peerId). Adding candidate immediately.")
            pc.add(candidate) { error in
                completion?(error)
                if let error = error {
                    logger.log("Error adding ICE candidate for \(peerId): \(error)")
                } else {
                     logger.logRTC("Successfully added ICE candidate for \(peerId)")
                }
            }
        } else {
             logger.logRTC("addIceCandidate: Remote description not set yet for \(peerId). Storing candidate in remoteCandidates.")
             // Store in remoteCandidates to be applied when setRemoteDescription completes
            remoteCandidates[peerId, default: []].append(candidate)
            completion?(nil)
        }
    }

     func flushPendingIce(for peerId: PlayerId) {
         guard let _ = peerConnections[peerId], let pending = pendingIceCandidates[peerId], !pending.isEmpty else { return }
         logger.logRTC("Flushing \(pending.count) pending *local* ICE candidates for \(peerId).")
         for candidate in pending {
             // Send pending local candidates via signaling
             onIceCandidateGenerated?(peerId, candidate)
         }
         pendingIceCandidates[peerId]?.removeAll() // Clear
    }

    func sendMessage(_ message: String) -> Bool {
        let buffer = RTCDataBuffer(data: message.data(using: .utf8)!, isBinary: false)
        var allSent = true
        
        for (peerId, channel) in outgoingDataChannels {
            if channel.readyState == .open {
                #if DEBUG
                let delay = Double.random(in: 0.1...0.8) // Simulate 100ms to 800ms delay
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    let sent = channel.sendData(buffer)
                    if !sent {
                        logger.log("Simulated lag: Failed to send message to \(peerId)")
                        self.messageQueues[peerId, default: []].append(message)
                    } else {
                        logger.logRTC("Simulated lag: Message sent to \(peerId) after \(Int(delay * 1000))ms")
                    }
                }
                #else
                let sent = channel.sendData(buffer)
                if !sent {
                    logger.log("Failed to send message to \(peerId)")
                    self.messageQueues[peerId, default: []].append(message)
                    allSent = false
                } else {
                    logger.logRTC("Message sent to \(peerId) on channel \(channel)")
                }
                #endif
            } else {
                logger.log("Data channel to \(peerId) not open, queueing message")
                self.messageQueues[peerId, default: []].append(message)
                allSent = false
            }
        }
        return allSent
    }
    
    /// Attempts to send any queued messages for the specified peer.
    private func flushMessageQueue(for peerId: PlayerId) {
        guard let channel = outgoingDataChannels[peerId], channel.readyState == .open else { return }
        var queue = messageQueues[peerId] ?? []
        while !queue.isEmpty {
            let msg = queue.removeFirst()
            let buffer = RTCDataBuffer(data: msg.data(using: .utf8)!, isBinary: false)
            if !channel.sendData(buffer) {
                logger.log("Failed to flush queued message to \(peerId)")
                messageQueues[peerId] = [msg] + queue
                return
            } else {
                logger.logRTC("Flushed queued message to \(peerId)")
            }
        }
        messageQueues[peerId] = queue
    }
}

extension P2PConnectionManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        logger.logRTC("Signaling state changed: \(stateChanged.rawValue)")
        if let peerId = peerConnections.first(where: { $0.value == peerConnection })?.key {
            onSignalingStateChanged?(peerId, stateChanged)
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        logger.logRTC("Stream added")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        logger.logRTC("Stream removed")
    }
    
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        logger.logRTC("Negotiation needed")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        logger.logRTC("ICE connection state changed for PC (\(peerConnection.description)) to: \(newState.rawValue)")
        
        if let peerId = peerConnections.first(where: { $0.value == peerConnection })?.key {
            logger.logRTC("P2P Delegate: Matched PC to peerId: \(peerId.rawValue)")
            onIceConnectionStateChanged?(peerId, newState)

            switch newState {
            case .connected, .completed:
                logger.logRTC("ICE connection for peer \(peerId.rawValue) is now \(newState.rawValue).")
            case .failed, .closed:
                logger.logRTC("ICE connection for peer \(peerId.rawValue) FAILED or CLOSED (state: \(newState.rawValue)). Calling onError.")
                let error = NSError(domain: "P2PConnectionManager", code: 1004, userInfo: [NSLocalizedDescriptionKey: "ICE connection state for \(peerId.rawValue): \(newState.rawValue)"])
                onError?(peerId, error)
            case .disconnected:
                logger.logRTC("ICE connection for peer \(peerId.rawValue) is DISCONNECTED. GameManager will attempt recovery.")
            case .checking:
                logger.logRTC("ICE connection for peer \(peerId.rawValue) is CHECKING.")
            case .new:
                 logger.logRTC("ICE connection for peer \(peerId.rawValue) is NEW.")
            default:
                logger.logRTC("ICE connection for peer \(peerId.rawValue) changed to UNKNOWN state: \(newState.rawValue).")
            }
        } else {
            logger.logRTC("ICE state changed, but couldn't find peerId for this peerConnection.")
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        logger.logRTC("ICE gathering state changed: \(newState.rawValue)")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        logger.logRTC(" P2P Delegate: peerConnection(_:didGenerate:) called.")
        logger.logRTC(" P2P Delegate: Candidate SDP: \(candidate.sdp)")
        
        guard let peerId = peerConnections.first(where: { $0.value == peerConnection })?.key else {
             logger.log(" P2P Delegate: ERROR - Could not find peerId for this peerConnection.")
            return
        }
         logger.logRTC(" P2P Delegate: Found peerId: \(peerId.rawValue)")

        if onIceCandidateGenerated != nil {
             logger.logRTC(" P2P Delegate: onIceCandidateGenerated callback IS set. Calling it now for \(peerId.rawValue).")
            Task { @MainActor in
                onIceCandidateGenerated?(peerId, candidate)
            }
        } else {
             logger.log(" P2P Delegate: ERROR - onIceCandidateGenerated callback is NIL.")
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        logger.logRTC("ICE candidates removed")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        logger.logRTC("Data channel opened with label: \(dataChannel.label)")
        dataChannel.delegate = self
        // Update the dedicated data channel for the corresponding peerId
        if let peerId = peerConnections.first(where: { $0.value == peerConnection })?.key {
            incomingDataChannelsMap[dataChannel] = peerId
            Task { @MainActor in
                onConnectionEstablished?(peerId)
            }
        }
        
        for peerConnection in peerConnections {
            logger.logRTC("🍐 Peer \(peerConnection.key) connected to \(peerConnection.value)")
        }
        for dataChannel in outgoingDataChannels {
            logger.logRTC("🏁 Peer \(dataChannel.key) connected to \(dataChannel.value)")
        }
    }
}

extension P2PConnectionManager: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        logger.logRTC("Data channel state changed to: \(dataChannel.readyState.rawValue)")

        switch dataChannel.readyState {
        case .open:
            logger.logRTC("Data channel is open and ready to use")
            if let peerId = incomingDataChannelsMap[dataChannel] {
                Task { @MainActor in
                    onConnectionEstablished?(peerId)
                    flushMessageQueue(for: peerId)
                }
            } else if let peerId = outgoingDataChannels.first(where: { $0.value === dataChannel })?.key {
                Task { @MainActor in
                    onConnectionEstablished?(peerId)
                    flushMessageQueue(for: peerId)
                }
            }
        case .closed:
            logger.logRTC("Data channel closed")
        case .connecting:
            logger.logRTC("Data channel connecting")
        case .closing:
            logger.logRTC("Data channel closing")
        @unknown default:
            logger.logRTC("Unknown data channel state: \(dataChannel.readyState.rawValue)")
        }
    }
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        if !buffer.isBinary, let message = String(data: buffer.data, encoding: .utf8),
           let peerId = incomingDataChannelsMap[dataChannel] {
            logger.logRTC("Received message from \(peerId): \(message)")
            onMessageReceived?(peerId, message)
        } else if buffer.isBinary {
            logger.log("Received binary data of size: \(buffer.data.count) bytes")
        } else {
            logger.log("Received data could not be decoded as UTF-8 text")
        }
    }
    
    func closeConnection(for peerId: PlayerId) {
        if let pc = peerConnections[peerId] {
            pc.close()
            peerConnections.removeValue(forKey: peerId)
            logger.logRTC("P2P: Closed connection and removed PC for \(peerId.rawValue)")
        }
        if let dc = outgoingDataChannels[peerId] {
            dc.close()
            outgoingDataChannels.removeValue(forKey: peerId)
        }
        // Also find and close/remove incoming data channels associated with this peerId
        let channelsToClose = incomingDataChannelsMap.filter { $0.value == peerId }.map { $0.key }
        for channel in channelsToClose {
            channel.close()
            incomingDataChannelsMap.removeValue(forKey: channel)
        }
        
        remoteCandidates.removeValue(forKey: peerId)
        pendingIceCandidates.removeValue(forKey: peerId)
        messageQueues.removeValue(forKey: peerId)
    }
}
