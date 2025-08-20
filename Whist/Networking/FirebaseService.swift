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
    private let currentGameStateDocumentId = "current"
    private let gameStatesCollection = "gameStates"
    private let currentGameActionDocumentId = "current"
    private let gameActionsCollection = "gameActions"
    private let scoresCollection = "scores"

    // MARK: - GameState

    func saveGameState(_ state: GameState) async throws {
        try db.collection(gameStatesCollection)
            .document(currentGameStateDocumentId)
            .setData(from: state)
    }

    func loadGameState() async throws -> GameState {
        let snapshot = try await db.collection(gameStatesCollection)
            .document(currentGameStateDocumentId)
            .getDocument()
        return try snapshot.data(as: GameState.self)
    }

    func deleteCurrentGameState() async throws {
        try await db.collection(gameStatesCollection)
            .document(currentGameStateDocumentId)
            .delete()
        logger.log("Successfully deleted game state document: \(currentGameStateDocumentId)")
    }

    // MARK: - GameState

    func saveGameAction(_ action: GameAction) async throws {
        try db.collection(gameActionsCollection)
            .addDocument(from: action)
    }

    func loadGameAction() async throws -> [GameAction] {
        let snapshot = try await db.collection(gameActionsCollection)
            .order(by: "timestamp") // optional: ensure chronological order if actions include a timestamp field
            .getDocuments()
        let actions = snapshot.documents.compactMap { doc in
            return try? doc.data(as: GameAction.self)
        }
        logger.log("Loaded \(actions.count) game actions from Firebase.")
        return actions
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
}
