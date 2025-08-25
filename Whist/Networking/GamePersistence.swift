//
//  GamePersistence.swift
//  Whist
//  Created by Tony Buffard on 2025-01-21.
//  Handles saving and loading GameState to/from Firebase Firestore.

import Foundation

class GamePersistence {
    private let firebaseService = FirebaseService.shared

    init() {
        logger.log("GamePersistence initialized for Firebase.")
    }

    func saveGameAction(_ action: GameAction) async {
        do {
            try await firebaseService.saveGameAction(action)
            logger.log("Game action saved successfully to Firebase.")
        } catch {
            logger.log("Error saving game action to Firebase: \(error.localizedDescription)")
        }
    }

    /// Loads all saved GameAction entries from Firestore.
    func loadGameActions() async -> [GameAction]? {
        do {
            let actions = try await firebaseService.loadGameAction()
            logger.log("Loaded \(actions.count) game actions from Firebase via GamePersistence.")
            return actions
        } catch {
            logger.log("Error loading game actions from Firebase: \(error.localizedDescription)")
            return nil
        }
    }

    /// Deletes all saved GameAction entries from Firestore and resets the action sequence.
    func clearGameActions() async {
        do {
            try await firebaseService.deleteAllGameActions()
            try await firebaseService.resetActionSequence()
            logger.log("Cleared all game actions and reset sequence in Firebase via GamePersistence.")
        } catch {
            logger.log("Error clearing game actions or resetting sequence in Firebase via GamePersistence: \(error.localizedDescription)")
        }
    }
    
}
