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
            //            throw NSError(domain: "FirebaseSignalingManager", code: 2001, userInfo: [NSLocalizedDescriptionKey: "Failed to encode ICE candidate"])
            return
        }
        
        let candidateDataForFirestore: [String: Any] = [
            "iceCandidates": FieldValue.arrayUnion([candidateString])
        ]
        logger.logRTC("Firebase [\(docId)]: Sending ICE candidate")
        try await db.collection("signaling").document(docId).setData(candidateDataForFirestore, merge: true)
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
        
        // Ensure we don't add duplicate listeners if called multiple times
        listenerRegistrations.forEach { $0.remove() }
        listenerRegistrations.removeAll()
        
        // Listen for Offers sent TO me
        let offerListener = listenForOffer(for: localPlayerId) { [weak self] (fromId, sdpString) in
            guard let self = self else { return }
            logger.logRTC("Received OFFER from \(fromId.rawValue). Invoking onOfferReceived callback.")
            let remoteSdp = RTCSessionDescription(type: .offer, sdp: sdpString)
            self.onOfferReceived?(fromId, remoteSdp)
        }
        listenerRegistrations.append(offerListener)
        
        // Listen for Answers sent TO me
        let answerListener = listenForAnswer(for: localPlayerId) { [weak self] (fromId, sdpString) in
            guard let self = self else { return }
            logger.logRTC(" Received ANSWER from \(fromId.rawValue). Invoking onAnswerReceived callback.")
            let remoteSdp = RTCSessionDescription(type: .answer, sdp: sdpString)
            self.onAnswerReceived?(fromId, remoteSdp)
        }
        listenerRegistrations.append(answerListener)
        
        // Listen for ICE Candidates sent TO me
        let candidateListener = listenForIceCandidates(for: localPlayerId) { [weak self] (fromId, candidate) in
            guard self != nil else { return }
            logger.logRTC("Received ICE Candidate from \(fromId.rawValue). Invoking onRemoteIceCandidateReceived callback.")
            self?.onRemoteIceCandidateReceived?(fromId, candidate)
        }
        listenerRegistrations.append(candidateListener)
        
        logger.logRTC(" Firebase Listeners: Setup complete for \(localPlayerId.rawValue)")
    }
    
    func listenForOffer(for localPlayerId: PlayerId, handler: @escaping (_ fromId: PlayerId, _ sdp: String) -> Void) -> ListenerRegistration {
        var lastProcessedOffer: String?
        
        return db.collection("signaling").addSnapshotListener { [weak self] querySnapshot, error in
            guard let self = self, let snapshot = querySnapshot else { return }
            
            snapshot.documentChanges.forEach { diff in
                if diff.type == .added || diff.type == .modified {
                    let docId = diff.document.documentID
                    if let ids = self.extractIds(from: docId), ids.to == localPlayerId {
                        let data = diff.document.data()
                        
                        guard let offerSdp = data["offer"] as? String else {
                            return
                        }
                        
                        // DEDUPLICATION CHECK:
                        // If the offer SDP hasn't changed since the last update, ignore it.
                        // This prevents re-triggering "Received OFFER" logic when ICE candidates are added.
                        if let last = lastProcessedOffer, last == offerSdp {
                            return
                        }
                        
                        // SESSION CHECK
                        guard let incomingSessionId = data["sessionId"] as? String else {
                            logger.logRTC("Offer listener: missing sessionId for doc \(docId). Skipping.")
                            return
                        }
                        logger.logRTC("Offer listener: validating sid \(incomingSessionId) from \(ids.from.rawValue)")
                        if let validate = self.validateSession, !validate(ids.from, incomingSessionId) {
                            logger.logRTC("Ignoring OFFER from \(ids.from) due to Session ID mismatch or missing.")
                            return
                        }
                        
                        logger.logRTC("✅ VALID Session OFFER received from \(ids.from).")
                        lastProcessedOffer = offerSdp
                        handler(ids.from, offerSdp)
                    }
                }
            }
        }
    }
    
    func listenForAnswer(for localPlayerId: PlayerId, handler: @escaping (_ fromId: PlayerId, _ sdp: String) -> Void) -> ListenerRegistration {
        var lastProcessedAnswer: String?
        
        return db.collection("signaling").addSnapshotListener { [weak self] querySnapshot, error in
            guard let self = self, let snapshot = querySnapshot else { return }
            
            snapshot.documentChanges.forEach { diff in
                // Optional: keep this diagnostic to see full doc content
                logger.logRTC("diff.document.data(): \(diff.document.data())")
                
                if diff.type == .added || diff.type == .modified {
                    let docId = diff.document.documentID
                    if let ids = self.extractIds(from: docId), ids.to == localPlayerId {
                        let data = diff.document.data()
                        
                        guard let answerSdp = data["answer"] as? String else {
                            return
                        }
                        
                        // DEDUPLICATION CHECK:
                        // If the answer SDP hasn't changed, ignore it.
                        if let last = lastProcessedAnswer, last == answerSdp {
                            return
                        }
                        
                        // SESSION CHECK
                        guard let incomingSessionId = data["sessionId"] as? String else {
                            logger.logRTC("Answer listener: missing sessionId for doc \(docId). Skipping.")
                            return
                        }
                        logger.logRTC("Answer listener: validating sid \(incomingSessionId) from \(ids.from.rawValue)")
                        if let validate = self.validateSession, !validate(ids.from, incomingSessionId) {
                            // Don't log this too loudly or it spams, but useful for debug
                            // logger.logRTC("Ignoring ANSWER from \(ids.from) - Session Mismatch.")
                            return
                        }
                        
                        logger.logRTC("✅ VALID Session ANSWER received from \(ids.from).")
                        lastProcessedAnswer = answerSdp
                        handler(ids.from, answerSdp)
                    }
                }
            }
        }
    }
    
    func listenForIceCandidates(for localPlayerId: PlayerId, handler: @escaping (_ fromId: PlayerId, _ candidate: RTCIceCandidate) -> Void) -> ListenerRegistration {
        var processedCandidatesByDocId = [String: Set<String>]()
        
        return db.collection("signaling").addSnapshotListener { [weak self] querySnapshot, error in
            guard let self = self, let snapshot = querySnapshot else { return }
            
            snapshot.documentChanges.forEach { diff in
                let docId = diff.document.documentID
                
                // Clear cache on remove
                if diff.type == .removed {
                    processedCandidatesByDocId.removeValue(forKey: docId)
                    return
                }
                
                if diff.type == .added || diff.type == .modified {
                    if let ids = self.extractIds(from: docId), ids.to == localPlayerId {
                        guard let candidateStrings = diff.document.data()["iceCandidates"] as? [String] else { return }
                        
                        if processedCandidatesByDocId[docId] == nil { processedCandidatesByDocId[docId] = Set<String>() }
                        
                        for candidateString in candidateStrings {
                            if processedCandidatesByDocId[docId]?.contains(candidateString) == false {
                                // Decode JSON
                                if let candidateData = candidateString.data(using: .utf8),
                                   let json = try? JSONDecoder().decode([String: String].self, from: candidateData) {
                                    
                                    // SESSION CHECK FOR ICE
                                    guard let incomingSid = json["sid"], !incomingSid.isEmpty else {
                                        logger.logRTC("ICE listener: candidate missing sid for doc \(docId). Skipping candidate.")
                                        processedCandidatesByDocId[docId]?.insert(candidateString) // avoid reprocessing
                                        continue
                                    }
                                    logger.logRTC("ICE listener: validating sid \(incomingSid) from \(ids.from.rawValue)")
                                    if let validate = self.validateSession, !validate(ids.from, incomingSid) {
                                        // Skip this specific candidate, it belongs to an old session
                                        processedCandidatesByDocId[docId]?.insert(candidateString) // avoid reprocessing
                                        continue
                                    }
                                    
                                    if let sdp = json["sdp"],
                                       let sdpMid = json["sdpMid"],
                                       let idxStr = json["sdpMLineIndex"],
                                       let idx = Int32(idxStr) {
                                        let candidate = RTCIceCandidate(sdp: sdp, sdpMLineIndex: idx, sdpMid: sdpMid)
                                        handler(ids.from, candidate)
                                        processedCandidatesByDocId[docId]?.insert(candidateString)
                                    } else {
                                        // malformed candidate JSON; mark as processed to avoid infinite retries
                                        processedCandidatesByDocId[docId]?.insert(candidateString)
                                    }
                                } else {
                                    // failed to decode; mark as processed to avoid loops
                                    processedCandidatesByDocId[docId]?.insert(candidateString)
                                }
                            }
                        }
                    }
                }
            }
        }
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
}
