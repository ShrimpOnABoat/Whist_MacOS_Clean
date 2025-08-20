//
//  ContentView.swift
//  Whist
//
//  Created by Tony Buffard on 2024-11-18.
//  Main view that decides which screen to display.

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var gameManager: GameManager
    @EnvironmentObject private var preferences: Preferences
    
    var body: some View {
        ZStack {
            // Show MatchMakingView when the game is waiting for players OR until setup game begins
            if gameManager.gameState.currentPhase == .waitingForPlayers {
                MatchMakingView()
                    .environmentObject(gameManager)
                    .environmentObject(preferences)
            } else {
                // Game is in progress
                GameView()
                    .environmentObject(gameManager)
                    .environmentObject(preferences)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Start P2P networking when view appears or playerId changes
        .onAppear {
            identifyAndUpdateLocalPlayer()
            gameManager.startNetworkingIfNeeded()
        }
        .onChange(of: preferences.playerId) { _ in
            identifyAndUpdateLocalPlayer()
//            gameManager.startNetworkingIfNeeded()
        }
    }
    // Helper function to avoid code duplication
    private func identifyAndUpdateLocalPlayer() {
        guard !preferences.playerId.isEmpty,
              let localId = PlayerId(rawValue: preferences.playerId) else {
            logger.log("ContentView: PlayerId not set, cannot identify local player.")
            return
        }
        logger.log("ContentView: Identifying local player as \(localId)")
        // Find the matching placeholder image (or set a default)
        let placeholderImage: Image
        switch localId {
        case .dd: placeholderImage = Image(systemName: "figure.pool.swim.circle.fill")
        case .gg: placeholderImage = Image(systemName: "safari.fill")
        case .toto: placeholderImage = Image(systemName: "figure.run.treadmill.circle.fill")
        }
        // Call the GameManager function to update the player object
        gameManager.updateLocalPlayer(localId, name: localId.rawValue, image: placeholderImage)
    }
}
