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

class FirebaseService: GameActionStore {
    static let shared = FirebaseService()
    private let db = Firestore.firestore()
    private let gameStatesCollection = "gameStates"
    private let currentGameActionDocumentId = "current"
    private let gameActionsCollection = "gameActions"
    private let scoresCollection = "scores"
    private let latestGameInsightsCollection = "latestGameInsights"
    private let gameInsightsHistoryCollection = "gameInsightsHistory"
    private let gameInsightMetricStatsCollection = "gameInsightMetricStats"
    private let countersCollection = "counters"
    private let counterId = "counter"
    
    // MARK: - Monotonic Action Sequence (Counter)
    
    /// Allocate the sequence and save its action in one server transaction. Retrying
    /// the same document ID after a lost acknowledgement returns the original action.
    func commitGameAction(_ draft: GameAction, documentID: String) async throws -> GameAction {
        let counterRef = db.collection(countersCollection).document(counterId)
        let actionRef = db.collection(gameActionsCollection).document(documentID)
        let result = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let existing = try transaction.getDocument(actionRef)
                if existing.exists {
                    return try JSONEncoder().encode(existing.data(as: GameAction.self))
                }
                let counter = try transaction.getDocument(counterRef)
                let sequence = (counter.data()?["next"] as? NSNumber)?.intValue ?? 1
                let action = GameAction(playerId: draft.playerId, type: draft.type,
                                        payload: draft.payload, timestamp: draft.timestamp,
                                        sequence: sequence, context: draft.context)
                try transaction.setData(from: action, forDocument: actionRef)
                transaction.setData(["next": sequence + 1], forDocument: counterRef, merge: true)
                return try JSONEncoder().encode(action)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        guard let data = result as? Data else {
            throw NSError(domain: "FirebaseService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Missing committed game action"])
        }
        return try JSONDecoder().decode(GameAction.self, from: data)
    }

    /// Listen to one small counter document. Fetch move data only when P2P did
    /// not deliver it; normal traffic does not need a second copy of every move.
    func observeActionSequence(_ onChange: @escaping (Result<Int, Error>) -> Void) -> GameActionObservation {
        let listener = db.collection(countersCollection).document(counterId)
            .addSnapshotListener(includeMetadataChanges: true) { snapshot, error in
                if let error {
                    Task { @MainActor in onChange(.failure(error)) }
                    return
                }
                guard let snapshot, !snapshot.metadata.isFromCache,
                      !snapshot.metadata.hasPendingWrites else { return }
                let next = (snapshot.data()?["next"] as? NSNumber)?.intValue ?? 1
                Task { @MainActor in onChange(.success(max(0, next - 1))) }
            }
        return GameActionObservation { listener.remove() }
    }

    /// Reads the current value of the monotonic action sequence counter from Firestore.
    /// If the document or field is missing, returns 1 as the initial default.
    func getCurrentActionSequence() async throws -> Int {
        let ref = db.collection(countersCollection).document(counterId)
        let snapshot = try await ref.getDocument()
        if let data = snapshot.data(), let value = data["next"] as? NSNumber {
            return Int(truncating: value)
        } else {
            return 1
        }
    }
    
    // MARK: - Game Actions
    
    func saveGameAction(_ action: GameAction) async throws {
        let data = try Firestore.Encoder().encode(action)
        try await db.collection(gameActionsCollection)
            .document("sequence-\(action.sequence)").setData(data)
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
        
        // Defensive dedupe for rare sequence collisions/races:
        // keep only the newest document per sequence number.
        var dedupedBySequence: [Int64: DecodedAction] = [:]
        var unsequenced: [DecodedAction] = []
        var duplicateSequenceCount = 0
        for item in decoded {
            guard let sequence = item.sequence else {
                unsequenced.append(item)
                continue
            }
            if let existing = dedupedBySequence[sequence] {
                duplicateSequenceCount += 1
                let existingTS = existing.timestamp ?? .distantPast
                let candidateTS = item.timestamp ?? .distantPast
                if candidateTS >= existingTS {
                    dedupedBySequence[sequence] = item
                }
            } else {
                dedupedBySequence[sequence] = item
            }
        }
        if duplicateSequenceCount > 0 {
            logger.log("Detected \(duplicateSequenceCount) duplicate gameActions sequence values. Keeping latest timestamp per sequence.")
        }
        let normalizedDecoded = Array(dedupedBySequence.values) + unsequenced
        
        let sorted = normalizedDecoded.sorted { lhs, rhs in
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

    func resetActionSequenceCounter() async throws {
        try await db.collection(countersCollection)
            .document(counterId)
            .setData(["next": NSNumber(value: 1)], merge: true)
        logger.log("Successfully reset action sequence counter to 1.")
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

    // MARK: - Game Insights

    func saveLatestGameInsights(_ summary: GameInsightsSummary) async throws {
        try db.collection(latestGameInsightsCollection)
            .document("latest")
            .setData(from: summary)
        try db.collection(gameInsightsHistoryCollection)
            .document(summary.id)
            .setData(from: summary)
    }

    func loadLatestGameInsights() async throws -> GameInsightsSummary? {
        let snapshot = try await db.collection(latestGameInsightsCollection)
            .document("latest")
            .getDocument()
        guard snapshot.exists else { return nil }
        return try snapshot.data(as: GameInsightsSummary.self)
    }

    func loadGameInsightMetricStats(keys: [String]) async throws -> [String: GameInsightMetricStats] {
        guard !keys.isEmpty else { return [:] }
        var result: [String: GameInsightMetricStats] = [:]
        let uniqueKeys = Array(Set(keys))
        for key in uniqueKeys {
            let snap = try await db.collection(gameInsightMetricStatsCollection)
                .document(key)
                .getDocument()
            if snap.exists, let stats = try? snap.data(as: GameInsightMetricStats.self) {
                result[key] = stats
            }
        }
        return result
    }

    func saveGameInsightMetricStats(_ statsByKey: [String: GameInsightMetricStats]) async throws {
        guard !statsByKey.isEmpty else { return }
        let batch = db.batch()
        for (key, stats) in statsByKey {
            let ref = db.collection(gameInsightMetricStatsCollection).document(key)
            try batch.setData(from: stats, forDocument: ref)
        }
        try await batch.commit()
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
        let snap = try await q.getDocuments(source: .server)
        return try snap.documents.compactMap { try $0.data(as: GameAction.self) }
    }
}
