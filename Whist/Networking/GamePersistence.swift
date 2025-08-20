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

    func saveGameState(_ state: GameState) async {
        do {
            try await firebaseService.saveGameState(state)
            logger.log("GameState saved successfully to Firebase.")
        } catch {
            logger.log("Error saving game state to Firebase: \(error.localizedDescription)")
        }
    }

    func loadGameState() async -> GameState? {
        do {
            let state = try await firebaseService.loadGameState()
            logger.log("GameState successfully loaded from Firebase.")
            return state
        } catch {
            logger.log("Error loading game state from Firebase: \(error.localizedDescription)")
            logger.log("No saved game state found or error occurred in Firebase.")
            return nil
        }
    }

    func clearSavedGameState() async {
        do {
            try await firebaseService.deleteCurrentGameState()
            logger.log("Cleared saved game state from Firebase via GamePersistence.")
        } catch {
            logger.log("Error clearing saved game state from Firebase via GamePersistence: \(error.localizedDescription)")
        }
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

    /// Deletes all saved GameAction entries from Firestore.
    func clearGameActions() async {
        do {
            try await firebaseService.deleteAllGameActions()
            logger.log("Cleared all game actions from Firebase via GamePersistence.")
        } catch {
            logger.log("Error clearing game actions from Firebase: \(error.localizedDescription)")
        }
    }
    
}
