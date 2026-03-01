//
//  FirebaseSignalingManager.swift
//  Whist
//
//  Created by Tony Buffard on 2025-04-19.
//

// FirebaseSignalingManager.swift
// Manages the WebRTC signaling layer using Firebase Firestore

import Foundation
import FirebaseFirestore
import WebRTC

class FirebaseSignalingManager {
    static let shared = FirebaseSignalingManager()
    
    // Callbacks for GameManager
    var onOfferReceived: ((_ fromId: PlayerId, _ sdp: RTCSessionDescription) -> Void)?
    var onAnswerReceived: ((_ fromId: PlayerId, _ sdp: RTCSessionDescription) -> Void)?
    var onRemoteIceCandidateReceived: ((_ fromId: PlayerId, _ candidate: RTCIceCandidate) -> Void)?
    
    private var listenerRegistrations: [ListenerRegistration] = []
    private let db = Firestore.firestore()
    private let listenerStateQueue = DispatchQueue(label: "Whist.FirebaseSignalingManager.listener-state")
    private let iceSendQueue = DispatchQueue(label: "Whist.FirebaseSignalingManager.ice-send")
    private var lastProcessedOfferByDocId: [String: String] = [:]
    private var lastProcessedAnswerByDocId: [String: String] = [:]
    private var processedCandidatesByDocId: [String: Set<String>] = [:]
    private var pendingIceCandidateStringsByDocId: [String: [String]] = [:]
    private var iceFlushWorkItemsByDocId: [String: DispatchWorkItem] = [:]
    private let iceBatchDebounce: TimeInterval = 0.3
    
    var validateSession: ((_ peerId: PlayerId, _ incomingSessionId: String?) -> Bool)?
    
    func documentName(from: PlayerId, to: PlayerId) -> String {
        return "\(from.rawValue)_to_\(to.rawValue)"
    }
    
    func sendOffer(from senderId: PlayerId, to receiverId: PlayerId, sdp: RTCSessionDescription, sessionId: String) async throws {
        let docId = documentName(from: senderId, to: receiverId)
        let offerData: [String: Any] = [
            "offer": sdp.sdp,
            "sessionId": sessionId
        ]
        logger.logRTC("Firebase [\(docId)]: Sending offer")
        try await db.collection("signaling").document(docId).setData(offerData, merge: true)
    }
    
    func sendAnswer(from senderId: PlayerId, to receiverId: PlayerId, sdp: RTCSessionDescription, sessionId: String) async throws {
        let docId = documentName(from: senderId, to: receiverId)
        let answerData: [String: Any] = [
            "answer": sdp.sdp,
            "sessionId": sessionId
        ]
        logger.logRTC("Firebase [\(docId)]: Sending answer")
        try await db.collection("signaling").document(docId).setData(answerData, merge: true)
    }
    
    func sendIceCandidate(from senderId: PlayerId, to receiverId: PlayerId, candidate: RTCIceCandidate, sessionId: String) async throws {
        let docId = documentName(from: senderId, to: receiverId)
        let candidateDict: [String: String] = [
            "sdp": candidate.sdp,
            "sdpMid": candidate.sdpMid ?? "",
            "sdpMLineIndex": String(candidate.sdpMLineIndex),
            "sid": sessionId
        ]
        guard let candidateData = try? JSONEncoder().encode(candidateDict),
              let candidateString = String(data: candidateData, encoding: .utf8) else {
            logger.log("Error encoding ICE candidate to JSON string")
            return
        }

        queueIceCandidateString(candidateString, forDocumentId: docId)
    }
    
    private func extractIds(from docId: String) -> (from: PlayerId, to: PlayerId)? {
        let parts = docId.split(separator: "_to_")
        guard parts.count == 2,
              let fromId = PlayerId(rawValue: String(parts[0])),
              let toId = PlayerId(rawValue: String(parts[1])) else {
            return nil
        }
        return (from: fromId, to: toId)
    }
    
    func setupFirebaseListeners(localPlayerId: PlayerId) {
        logger.logRTC(" Firebase Listeners: Setting up for \(localPlayerId.rawValue)")
        
        listenerRegistrations.forEach { $0.remove() }
        listenerRegistrations.removeAll()
        listenerStateQueue.sync {
            lastProcessedOfferByDocId.removeAll()
            lastProcessedAnswerByDocId.removeAll()
            processedCandidatesByDocId.removeAll()
        }

        for peerId in PlayerId.allCases where peerId != localPlayerId {
            let docId = documentName(from: peerId, to: localPlayerId)
            let listener = db.collection("signaling").document(docId).addSnapshotListener { [weak self] snapshot, error in
                self?.handleIncomingDocumentSnapshot(snapshot, error: error, from: peerId, to: localPlayerId, docId: docId)
            }
            listenerRegistrations.append(listener)
        }
        
        logger.logRTC(" Firebase Listeners: Setup complete for \(localPlayerId.rawValue)")
    }

    func clearSignalingData(for playerId: String) async throws {
        let signalingRef = db.collection("signaling")
        let batch = db.batch()
        var docsToDeleteCount = 0
        
        let outgoingQuery = signalingRef.whereField(FieldPath.documentID(), isGreaterThanOrEqualTo: "\(playerId)_to_").whereField(FieldPath.documentID(), isLessThan: "\(playerId)_to_\u{f8ff}")
        
        do {
            let outgoingDocs = try await outgoingQuery.getDocuments()
            for document in outgoingDocs.documents {
                batch.deleteDocument(document.reference)
                docsToDeleteCount += 1
                logger.logRTC("Firebase: Queued deletion for outgoing doc: \(document.documentID)")
            }
            
            if docsToDeleteCount > 0 {
                logger.logRTC("Firebase: Committing batch delete for \(docsToDeleteCount) signaling documents related to \(playerId).")
                try await batch.commit()
                logger.logRTC("Firebase: Successfully cleared signaling data for \(playerId).")
            } else {
                logger.logRTC("Firebase: No signaling documents found to clear for \(playerId).")
            }
        } catch {
            logger.log("Firebase: Error clearing signaling data for \(playerId): \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Deletes the signaling documents exchanged between two players in both directions.
    func clearSignalingDocuments(between localPlayerId: PlayerId, and peerId: PlayerId) async throws {
        let signalingRef = db.collection("signaling")
        let docIds = [
            documentName(from: localPlayerId, to: peerId),
            documentName(from: peerId, to: localPlayerId)
        ]
        for docId in docIds {
            logger.logRTC("Firebase: Deleting signaling document \(docId)")
            try await signalingRef.document(docId).delete()
        }
        logger.logRTC("Firebase: Cleared signaling documents between \(localPlayerId.rawValue) and \(peerId.rawValue)")
    }
    
    deinit {
        listenerRegistrations.forEach { $0.remove() }
    }

    private func handleIncomingDocumentSnapshot(_ snapshot: DocumentSnapshot?, error: Error?, from fromId: PlayerId, to _: PlayerId, docId: String) {
        if let error {
            logger.log("Firebase listener error for \(docId): \(error.localizedDescription)")
            return
        }

        guard let snapshot else { return }

        guard snapshot.exists, let data = snapshot.data() else {
            listenerStateQueue.sync {
                lastProcessedOfferByDocId.removeValue(forKey: docId)
                lastProcessedAnswerByDocId.removeValue(forKey: docId)
                processedCandidatesByDocId.removeValue(forKey: docId)
            }
            return
        }

        processOfferIfNeeded(from: fromId, docId: docId, data: data)
        processAnswerIfNeeded(from: fromId, docId: docId, data: data)
        processIceCandidatesIfNeeded(from: fromId, docId: docId, data: data)
    }

    private func processOfferIfNeeded(from fromId: PlayerId, docId: String, data: [String: Any]) {
        guard let offerSdp = data["offer"] as? String else { return }
        guard let incomingSessionId = data["sessionId"] as? String else {
            logger.logRTC("Offer listener: missing sessionId for doc \(docId). Skipping.")
            return
        }
        guard validateSession?(fromId, incomingSessionId) ?? true else {
            logger.logRTC("Ignoring OFFER from \(fromId) due to Session ID mismatch or missing.")
            return
        }

        let shouldProcess = listenerStateQueue.sync { () -> Bool in
            if lastProcessedOfferByDocId[docId] == offerSdp { return false }
            lastProcessedOfferByDocId[docId] = offerSdp
            return true
        }
        guard shouldProcess else { return }

        logger.logRTC("✅ VALID Session OFFER received from \(fromId).")
        let remoteSdp = RTCSessionDescription(type: .offer, sdp: offerSdp)
        onOfferReceived?(fromId, remoteSdp)
    }

    private func processAnswerIfNeeded(from fromId: PlayerId, docId: String, data: [String: Any]) {
        guard let answerSdp = data["answer"] as? String else { return }
        guard let incomingSessionId = data["sessionId"] as? String else {
            logger.logRTC("Answer listener: missing sessionId for doc \(docId). Skipping.")
            return
        }
        guard validateSession?(fromId, incomingSessionId) ?? true else {
            return
        }

        let shouldProcess = listenerStateQueue.sync { () -> Bool in
            if lastProcessedAnswerByDocId[docId] == answerSdp { return false }
            lastProcessedAnswerByDocId[docId] = answerSdp
            return true
        }
        guard shouldProcess else { return }

        logger.logRTC("✅ VALID Session ANSWER received from \(fromId).")
        let remoteSdp = RTCSessionDescription(type: .answer, sdp: answerSdp)
        onAnswerReceived?(fromId, remoteSdp)
    }

    private func processIceCandidatesIfNeeded(from fromId: PlayerId, docId: String, data: [String: Any]) {
        guard let candidateStrings = data["iceCandidates"] as? [String], !candidateStrings.isEmpty else { return }

        for candidateString in candidateStrings {
            let shouldDecode = listenerStateQueue.sync { () -> Bool in
                var processed = processedCandidatesByDocId[docId] ?? Set<String>()
                if processed.contains(candidateString) {
                    return false
                }
                processed.insert(candidateString)
                processedCandidatesByDocId[docId] = processed
                return true
            }

            guard shouldDecode else { continue }
            guard let candidateData = candidateString.data(using: .utf8),
                  let json = try? JSONDecoder().decode([String: String].self, from: candidateData) else {
                continue
            }

            guard let incomingSid = json["sid"], !incomingSid.isEmpty else {
                logger.logRTC("ICE listener: candidate missing sid for doc \(docId). Skipping candidate.")
                continue
            }
            guard validateSession?(fromId, incomingSid) ?? true else {
                continue
            }

            guard let sdp = json["sdp"],
                  let sdpMid = json["sdpMid"],
                  let idxStr = json["sdpMLineIndex"],
                  let idx = Int32(idxStr) else {
                continue
            }

            let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: idx, sdpMid: sdpMid)
            logger.logRTC("Received ICE Candidate from \(fromId.rawValue). Invoking onRemoteIceCandidateReceived callback.")
            onRemoteIceCandidateReceived?(fromId, candidate)
        }
    }

    private func queueIceCandidateString(_ candidateString: String, forDocumentId docId: String) {
        iceSendQueue.async {
            self.pendingIceCandidateStringsByDocId[docId, default: []].append(candidateString)
            self.iceFlushWorkItemsByDocId[docId]?.cancel()

            let workItem = DispatchWorkItem { [weak self] in
                self?.flushIceCandidateBatch(forDocumentId: docId)
            }
            self.iceFlushWorkItemsByDocId[docId] = workItem
            self.iceSendQueue.asyncAfter(deadline: .now() + self.iceBatchDebounce, execute: workItem)
        }
    }

    private func flushIceCandidateBatch(forDocumentId docId: String) {
        iceFlushWorkItemsByDocId.removeValue(forKey: docId)
        let candidateStrings = pendingIceCandidateStringsByDocId.removeValue(forKey: docId) ?? []

        guard !candidateStrings.isEmpty else { return }

        Task {
            do {
                let candidateDataForFirestore: [String: Any] = [
                    "iceCandidates": FieldValue.arrayUnion(candidateStrings)
                ]
                logger.logRTC("Firebase [\(docId)]: Sending \(candidateStrings.count) ICE candidate(s)")
                try await db.collection("signaling").document(docId).setData(candidateDataForFirestore, merge: true)
            } catch {
                logger.log("Firebase [\(docId)]: Failed to send batched ICE candidates: \(error.localizedDescription)")
            }
        }
    }
}
