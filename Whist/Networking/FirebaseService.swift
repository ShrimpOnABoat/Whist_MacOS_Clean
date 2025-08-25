//
//  FirebaseService.swift
//  Whist
//
//  Created by Tony Buffard on 2025-04-19.
//

// FirebaseService.swift
// Handles all Firebase read/write operations for game state and score history.

import Foundation
import FirebaseFirestore

class FirebaseService {
    static let shared = FirebaseService()
    private let db = Firestore.firestore()
    private let gameStatesCollection = "gameStates"
    private let currentGameActionDocumentId = "current"
    private let gameActionsCollection = "gameActions"
    private let scoresCollection = "scores"
    private let countersCollection = "counters"
    private let counterId = "counter"
    
    // MARK: - Monotonic Action Sequence (Counter)
    
    /// Returns the next strictly increasing sequence number for actions.
    /// The counter is stored in Firestore at: counters/{gameId}
    /// Field: "next" (Int). If missing, it initializes to 1.
    /// This uses a Firestore transaction to guarantee atomicity across clients.
    func nextActionSequence() async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            db.runTransaction({ (transaction, errorPointer) -> Any? in
                let counterRef = self.db.collection(self.countersCollection).document(self.counterId)
                var current: Int = 1
                do {
                    let snapshot = try transaction.getDocument(counterRef)
                    if snapshot.exists {
                        if let value = snapshot.data()?["next"] as? NSNumber {
                            current = Int(truncating: value)
                        } else {
                            current = 1
                        }
                    } else {
                        current = 1
                    }
                    // Assign this value and bump for next time
                    transaction.setData(["next": NSNumber(value: current + 1)], forDocument: counterRef, merge: true)
                    return NSNumber(value: current)
                } catch let err as NSError {
                    errorPointer?.pointee = err
                    return nil
                }
            }, completion: { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if let number = result as? NSNumber {
                    continuation.resume(returning: Int(truncating: number))
                } else {
                    continuation.resume(throwing: NSError(domain: "FirebaseService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate sequence"]))
                }
            })
        }
    }
    
    /// Resets the monotonic action sequence for a given game.
    /// This should be called right at the start of a new game, before any
    /// actions are saved. It sets `counters/{gameId}.next` back to 1.
    /// Uses a transaction so the write is atomic if other clients are around.
    func resetActionSequence() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            db.runTransaction({ (transaction, errorPointer) -> Any? in
                let counterRef = self.db.collection(self.countersCollection).document(self.counterId)
                transaction.setData(["next": NSNumber(value: 1)], forDocument: counterRef, merge: true)
                return true as NSNumber
            }, completion: { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    logger.log("Reset action sequence to 1")
                    continuation.resume(returning: ())
                }
            })
        }
    }
    
    // MARK: - Game Actions
    
    func saveGameAction(_ action: GameAction) async throws {
        try db.collection(gameActionsCollection)
            .addDocument(from: action)
    }
    
    func loadGameAction() async throws -> [GameAction] {
        let snapshot = try await db.collection(gameActionsCollection).getDocuments()
        
        // Decode actions, but also capture their sequence (if any) and timestamp for sorting.
        struct DecodedAction {
            let action: GameAction
            let sequence: Int64?
            let timestamp: Date?
        }
        
        let decoded: [DecodedAction] = snapshot.documents.compactMap { doc in
            guard let action = try? doc.data(as: GameAction.self) else { return nil }
            let seqAny = doc.data()["sequence"]
            let seq: Int64? = (seqAny as? NSNumber)?.int64Value
            let ts: Date? = {
                if let ts = doc.data()["timestamp"] as? Timestamp {
                    return ts.dateValue()
                }
                return nil
            }()
            return DecodedAction(action: action, sequence: seq, timestamp: ts)
        }
        
        let sorted = decoded.sorted { lhs, rhs in
            switch (lhs.sequence, rhs.sequence) {
            case let (l?, r?):
                if l != r { return l < r }
                // tie-breaker: timestamp (server time) if available
                return (lhs.timestamp ?? .distantPast) < (rhs.timestamp ?? .distantPast)
            case (nil, nil):
                // No sequence on either: fall back to timestamp
                return (lhs.timestamp ?? .distantPast) < (rhs.timestamp ?? .distantPast)
            case (nil, _?):
                // Place unsequenced (legacy) before/after? Choose timestamp order but keep them before sequenced if older.
                // We will order by timestamp and place before if older than first sequenced timestamp.
                return true
            case (_?, nil):
                return false
            }
        }.map { $0.action }
        
        logger.log("Loaded \(sorted.count) game actions from Firebase.")
        return sorted
    }
    
    func deleteAllGameActions() async throws {
        let collectionRef = db.collection(gameActionsCollection)
        var lastSnapshot: QuerySnapshot? = nil
        var totalDeleted = 0
        repeat {
            var query: Query = collectionRef.limit(to: 400)
            if let last = lastSnapshot?.documents.last {
                query = query.start(afterDocument: last)
            }
            let snapshot = try await query.getDocuments()
            guard !snapshot.documents.isEmpty else { break }
            let batch = db.batch()
            snapshot.documents.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
            totalDeleted += snapshot.documents.count
            lastSnapshot = snapshot
        } while lastSnapshot != nil
        logger.log("Successfully deleted \(totalDeleted) game actions from collection \(gameActionsCollection).")
    }
    
    // MARK: - GameScore
    
    func saveGameScore(_ score: GameScore) async throws {
        let id = score.id.uuidString
        try db.collection(scoresCollection)
            .document(id)
            .setData(from: score)
    }
    
    func saveGameScores(_ scores: [GameScore]) async throws {
        let batch = db.batch()
        let scoresRef = db.collection(scoresCollection)
        for score in scores {
            let docRef = scoresRef.document(score.id.uuidString)
            try batch.setData(from: score, forDocument: docRef)
        }
        try await batch.commit()
        logger.log("Successfully saved \(scores.count) scores in a batch.")
    }
    
    /// Attempts to load actions ordered by the `sequence` field directly in Firestore.
    /// If the composite index is missing in the project, this is functionally equivalent to `loadGameAction()`.
    func loadGameActionsOrderedBySequence() async throws -> [GameAction] {
        do {
            let snapshot = try await db.collection(gameActionsCollection)
                .order(by: "sequence")
                .getDocuments()
            let actions = snapshot.documents.compactMap { try? $0.data(as: GameAction.self) }
            logger.log("Loaded \(actions.count) game actions from Firebase ordered by sequence.")
            return actions
        } catch {
            // Fall back to generic loader (which sorts in-memory by sequence if present).
            logger.log("Falling back to in-memory sorting for game actions: \(String(describing: error))")
            return try await loadGameAction()
        }
    }
    
    func loadScores(for year: Int? = nil) async throws -> [GameScore] {
        var query: Query = db.collection(scoresCollection)
            .order(by: "date", descending: true)
        
        if let year = year,
           let calendar = Optional(Calendar.current),
           let startDate = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
           let endDate = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)) {
            query = query.whereField("date", isGreaterThanOrEqualTo: startDate)
                .whereField("date", isLessThan: endDate)
        }
        
        let snapshot = try await query.getDocuments()
        let scores = snapshot.documents.compactMap { document -> GameScore? in
            try? document.data(as: GameScore.self)
        }
        logger.log("Successfully loaded \(scores.count) scores\(year == nil ? "" : " for year \(year!)").")
        return scores
    }
    
    func deleteGameScore(id: String) async throws {
        try await db.collection(scoresCollection).document(id).delete()
        logger.log("Successfully deleted score with ID: \(id)")
    }
    
    func deleteAllGameScores() async throws {
        let collectionRef = db.collection(scoresCollection)
        var count = 0
        var lastSnapshot: DocumentSnapshot? = nil
        
        repeat {
            let batch = db.batch()
            var query = collectionRef.limit(to: 400)
            if let lastSnapshot = lastSnapshot {
                query = query.start(afterDocument: lastSnapshot)
            }
            
            let snapshot = try await query.getDocuments()
            guard !snapshot.documents.isEmpty else { break }
            
            snapshot.documents.forEach { batch.deleteDocument($0.reference) }
            try await batch.commit()
            
            count += snapshot.documents.count
            lastSnapshot = snapshot.documents.last
            
        } while lastSnapshot != nil
        
        logger.log("Successfully deleted \(count) scores from collection \(scoresCollection).")
    }
    
    // FirebaseService
    func loadGameActions(sequenceGreaterThanOrEqual start: Int,
                         sequenceLessThanOrEqual end: Int?) async throws -> [GameAction] {
        var q = db.collection(gameActionsCollection)
            .whereField("sequence", isGreaterThanOrEqualTo: start)
        if let end = end {
            q = q.whereField("sequence", isLessThanOrEqualTo: end)
        }
        q = q.order(by: "sequence", descending: false)
        let snap = try await q.getDocuments()
        return try snap.documents.compactMap { try $0.data(as: GameAction.self) }
    }
}
