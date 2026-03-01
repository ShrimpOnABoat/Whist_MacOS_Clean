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

    private let stateQueue = DispatchQueue(label: "Whist.P2PConnectionManager.state")
    private var outgoingDataChannels: [PlayerId: RTCDataChannel] = [:]
    private var incomingDataChannelsMap: [RTCDataChannel: PlayerId] = [:]
    private var peerIdByConnectionId: [ObjectIdentifier: PlayerId] = [:]
    private var remoteCandidatesAwaitingDescription: [PlayerId: [RTCIceCandidate]] = [:]
    private var earlyRemoteCandidates: [PlayerId: [RTCIceCandidate]] = [:]
    private var messageQueues: [PlayerId: [String]] = [:]
    private var pendingLocalIceCandidates: [PlayerId: [RTCIceCandidate]] = [:]
    
    private var peerConnections: [PlayerId: RTCPeerConnection] = [:]
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
        if let pc = stateQueue.sync(execute: { peerConnections[peerId] }) {
             if stateQueue.sync(execute: { outgoingDataChannels[peerId] == nil }) {
                 createAndStoreOutgoingDataChannel(for: peerId, on: pc)
             }
            return pc
        }
        guard let pc = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            logger.fatalErrorAndLog("P2PConnectionManager: failed to create RTCPeerConnection")
        }
        stateQueue.sync {
            peerConnections[peerId] = pc
            peerIdByConnectionId[ObjectIdentifier(pc)] = peerId
        }
        createAndStoreOutgoingDataChannel(for: peerId, on: pc)
        return pc
    }

    private func createAndStoreOutgoingDataChannel(for peerId: PlayerId, on pc: RTCPeerConnection) {
         let dataChannelConfig = RTCDataChannelConfiguration()
         dataChannelConfig.isOrdered = true
         if let channel = pc.dataChannel(forLabel: peerId.rawValue, configuration: dataChannelConfig) {
             channel.delegate = self // Also set delegate for outgoing channel state changes
             stateQueue.sync {
                 outgoingDataChannels[peerId] = channel
             }
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
        let channelsAndConnections = stateQueue.sync {
            let outgoing = Array(outgoingDataChannels.values)
            let incoming = Array(incomingDataChannelsMap.keys)
            let connections = Array(peerConnections.values)
            outgoingDataChannels.removeAll()
            incomingDataChannelsMap.removeAll()
            peerConnections.removeAll()
            peerIdByConnectionId.removeAll()
            remoteCandidatesAwaitingDescription.removeAll()
            earlyRemoteCandidates.removeAll()
            pendingLocalIceCandidates.removeAll()
            messageQueues.removeAll()
            return (outgoing, incoming, connections)
        }

        channelsAndConnections.0.forEach { $0.close() }
        channelsAndConnections.1.forEach { $0.close() }
        channelsAndConnections.2.forEach { $0.close() }
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
             strongSelf.applyBufferedRemoteCandidates(for: peerId, on: connection)
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
        let pc = existingPeerConnection(for: peerId) ?? makePeerConnection(for: peerId)

        pc.setRemoteDescription(sdp) { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                 logger.log("Error setting remote description for \(peerId): \(error)")
                completion(error)
                return
            }
             logger.logRTC("Successfully set remote description for \(peerId). Type: \(sdp.type.rawValue)")
            self.applyBufferedRemoteCandidates(for: peerId, on: pc)
            completion(nil)
        }
    }

    func addIceCandidate(_ candidate: RTCIceCandidate, for peerId: PlayerId, completion: ((Error?) -> Void)? = nil) {
        guard let pc = existingPeerConnection(for: peerId) else {
             logger.logRTC("addIceCandidate: No peer connection found for \(peerId). Buffering remote candidate.")
             stateQueue.sync {
                 earlyRemoteCandidates[peerId, default: []].append(candidate)
             }
             completion?(nil)
             return
        }

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
             logger.logRTC("addIceCandidate: Remote description not set yet for \(peerId). Buffering remote candidate.")
            stateQueue.sync {
                remoteCandidatesAwaitingDescription[peerId, default: []].append(candidate)
            }
            completion?(nil)
        }
    }

     func flushPendingIce(for peerId: PlayerId) {
         let pending = stateQueue.sync { pendingLocalIceCandidates.removeValue(forKey: peerId) ?? [] }
         guard !pending.isEmpty else { return }
         logger.logRTC("Flushing \(pending.count) pending *local* ICE candidates for \(peerId).")
         for candidate in pending {
             onIceCandidateGenerated?(peerId, candidate)
         }
    }

    func sendMessage(_ message: String) -> Bool {
        let buffer = RTCDataBuffer(data: message.data(using: .utf8)!, isBinary: false)
        let channels = stateQueue.sync { outgoingDataChannels }
        guard !channels.isEmpty else {
            logger.log("No data channels available, cannot send message")
            return false
        }

        var allSent = true
        
        for (peerId, channel) in channels {
            if channel.readyState == .open {
                #if DEBUG
                let delay = Double.random(in: 0.1...0.8) // Simulate 100ms to 800ms delay
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    let sent = channel.sendData(buffer)
                    if !sent {
                        logger.log("Simulated lag: Failed to send message to \(peerId)")
                        self.stateQueue.async {
                            self.messageQueues[peerId, default: []].append(message)
                        }
                    } else {
                        logger.logRTC("Simulated lag: Message sent to \(peerId) after \(Int(delay * 1000))ms")
                    }
                }
                #else
                let sent = channel.sendData(buffer)
                if !sent {
                    logger.log("Failed to send message to \(peerId)")
                    stateQueue.sync {
                        self.messageQueues[peerId, default: []].append(message)
                    }
                    allSent = false
                } else {
                    logger.logRTC("Message sent to \(peerId) on channel \(channel)")
                }
                #endif
            } else {
                logger.log("Data channel to \(peerId) not open, queueing message")
                stateQueue.sync {
                    self.messageQueues[peerId, default: []].append(message)
                }
                allSent = false
            }
        }
        return allSent
    }
    
    /// Attempts to send any queued messages for the specified peer.
    private func flushMessageQueue(for peerId: PlayerId) {
        guard let channel = stateQueue.sync(execute: { outgoingDataChannels[peerId] }), channel.readyState == .open else { return }
        var queue = stateQueue.sync { messageQueues.removeValue(forKey: peerId) ?? [] }
        while !queue.isEmpty {
            let msg = queue.removeFirst()
            let buffer = RTCDataBuffer(data: msg.data(using: .utf8)!, isBinary: false)
            if !channel.sendData(buffer) {
                logger.log("Failed to flush queued message to \(peerId)")
                stateQueue.sync {
                    messageQueues[peerId] = [msg] + queue
                }
                return
            } else {
                logger.logRTC("Flushed queued message to \(peerId)")
            }
        }
    }

    func signalingState(for peerId: PlayerId) -> RTCSignalingState? {
        existingPeerConnection(for: peerId)?.signalingState
    }

    private func existingPeerConnection(for peerId: PlayerId) -> RTCPeerConnection? {
        stateQueue.sync { peerConnections[peerId] }
    }

    private func peerId(for peerConnection: RTCPeerConnection) -> PlayerId? {
        stateQueue.sync { peerIdByConnectionId[ObjectIdentifier(peerConnection)] }
    }

    private func applyBufferedRemoteCandidates(for peerId: PlayerId, on pc: RTCPeerConnection) {
        let candidates = stateQueue.sync {
            let early = earlyRemoteCandidates.removeValue(forKey: peerId) ?? []
            let waiting = remoteCandidatesAwaitingDescription.removeValue(forKey: peerId) ?? []
            return early + waiting
        }

        guard !candidates.isEmpty else { return }

        logger.logRTC("Applying \(candidates.count) buffered remote ICE candidates for \(peerId).")
        for candidate in candidates {
            pc.add(candidate) { error in
                if let error = error {
                    logger.log("Error adding buffered ICE candidate for \(peerId): \(error)")
                } else {
                    logger.logRTC("Successfully added buffered ICE candidate for \(peerId).")
                }
            }
        }
    }
}

extension P2PConnectionManager: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        logger.logRTC("Signaling state changed: \(stateChanged.rawValue)")
        if let peerId = peerId(for: peerConnection) {
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
        
        if let peerId = peerId(for: peerConnection) {
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
        
        guard let peerId = peerId(for: peerConnection) else {
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
             stateQueue.sync {
                 pendingLocalIceCandidates[peerId, default: []].append(candidate)
             }
             logger.log(" P2P Delegate: onIceCandidateGenerated callback is NIL. Buffering local ICE.")
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        logger.logRTC("ICE candidates removed")
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        logger.logRTC("Data channel opened with label: \(dataChannel.label)")
        dataChannel.delegate = self
        if let peerId = peerId(for: peerConnection) {
            stateQueue.sync {
                incomingDataChannelsMap[dataChannel] = peerId
            }
            Task { @MainActor in
                onConnectionEstablished?(peerId)
            }
        }
        
        let connections = stateQueue.sync { peerConnections }
        let outgoingChannels = stateQueue.sync { outgoingDataChannels }
        for peerConnection in connections {
            logger.logRTC("🍐 Peer \(peerConnection.key) connected to \(peerConnection.value)")
        }
        for dataChannel in outgoingChannels {
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
            if let peerId = stateQueue.sync(execute: { incomingDataChannelsMap[dataChannel] }) {
                Task { @MainActor in
                    onConnectionEstablished?(peerId)
                    flushMessageQueue(for: peerId)
                }
            } else if let peerId = stateQueue.sync(execute: { outgoingDataChannels.first(where: { $0.value === dataChannel })?.key }) {
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
           let peerId = stateQueue.sync(execute: { incomingDataChannelsMap[dataChannel] }) {
            logger.logRTC("Received message from \(peerId): \(message)")
            onMessageReceived?(peerId, message)
        } else if buffer.isBinary {
            logger.log("Received binary data of size: \(buffer.data.count) bytes")
        } else {
            logger.log("Received data could not be decoded as UTF-8 text")
        }
    }
    
    func closeConnection(for peerId: PlayerId) {
        let resources = stateQueue.sync { () -> (RTCPeerConnection?, RTCDataChannel?, [RTCDataChannel]) in
            let pc = peerConnections.removeValue(forKey: peerId)
            if let pc {
                peerIdByConnectionId.removeValue(forKey: ObjectIdentifier(pc))
            }
            let outgoing = outgoingDataChannels.removeValue(forKey: peerId)
            let incoming = incomingDataChannelsMap.filter { $0.value == peerId }.map { $0.key }
            for channel in incoming {
                incomingDataChannelsMap.removeValue(forKey: channel)
            }
            remoteCandidatesAwaitingDescription.removeValue(forKey: peerId)
            earlyRemoteCandidates.removeValue(forKey: peerId)
            pendingLocalIceCandidates.removeValue(forKey: peerId)
            messageQueues.removeValue(forKey: peerId)
            return (pc, outgoing, incoming)
        }

        if let pc = resources.0 {
            pc.close()
            logger.logRTC("P2P: Closed connection and removed PC for \(peerId.rawValue)")
        }
        if let dc = resources.1 {
            dc.close()
        }
        let channelsToClose = resources.2
        for channel in channelsToClose {
            channel.close()
        }
    }
}
