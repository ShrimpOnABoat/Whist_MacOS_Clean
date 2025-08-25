//
//  ScoreBoardView.swift
//  Whist
//
//  Created by Tony Buffard on 2024-11-18.
//  Shows current scores with tricks and player positions.

import SwiftUI

struct ScoreBoardView: View {
    @EnvironmentObject var gameManager: GameManager
    var dynamicSize: DynamicSize

        
    var body: some View {
        let round = gameManager.gameState.round
        let roundString = round < 4 ? "\(round)/3" : "\(round - 2)"
        
        // Display order: left player, then local player, then right player
        let playOrder: [PlayerId] = {
            if let leftId = gameManager.gameState.leftPlayer?.id,
               let localId = gameManager.gameState.localPlayer?.id,
               let rightId = gameManager.gameState.rightPlayer?.id {
                return [leftId, localId, rightId]
            } else {
                // Fallback to whatever order the players are currently stored in
                return gameManager.gameState.players.map { $0.id }
            }
        }()
        
        VStack(spacing: dynamicSize.vstackScoreSpacing) {
            // Round number
            Text("Tour \(roundString)")
                .font(.system(size: dynamicSize.roundSize))
                .fontWeight(.bold)

            // Header row: Player IDs
            HStack {
                ForEach(playOrder, id: \.self) { id in
                    HStack(spacing: 2) {
                        if gameManager.gameState.getPlayer(by: id).onlyWins {
                            Circle()
                                .fill(Color.red)
                                .frame(width: dynamicSize.dotSize, height: dynamicSize.dotSize)
                        }
                        Text(id.displayName)
                            .font(.system(size: dynamicSize.nameSize))
                            .bold(true)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Tricks and Scores row
            HStack {
                ForEach(playOrder, id: \.self) { id in
                    let player = gameManager.gameState.getPlayer(by: id)
                    let score: Int = round > 1 ? player.scores.last ?? 0 : 0
                    let tricks: Int = {
                        if gameManager.allPlayersBet() {
                            return player.announcedTricks.reduce(0, +)
                        } else if round > 1 {
                            if player.announcedTricks.count == round {
                                return player.announcedTricks.dropLast().reduce(0, +)
                            } else {
                                return player.announcedTricks.reduce(0, +)
                            }
                        } else {
                            return 0
                        }
                    }()

                    return AnyView( // Use AnyView to wrap the view and make the return type explicit
                        HStack {
                            Text("\(tricks)")
                                .font(.system(size: dynamicSize.scoreSize))
                            
                            HStack(spacing: 0) {
                                Text("\(score)")
                                    .font(.system(size: dynamicSize.scoreSize))
                                    .fontWeight(.bold)
                                if player.onlyWinsBonus {
                                    Text("+5")
                                        .font(.system(size: dynamicSize.scoreSize * 0.6))
                                        .fontWeight(.bold)
                                        .foregroundColor(.green)
                                        .baselineOffset(dynamicSize.scoreSize * 0.3)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    )
                }
            }

            // Announced tricks for the round
            HStack {
                ForEach(playOrder, id: \.self) { id in
                    let player = gameManager.gameState.getPlayer(by: id)
                    HStack {
                        // Announced Tricks
                        if (round < 4 || gameManager.allPlayersBet()) && (player.announcedTricks.count >= round && round > 0) {
                            let announcedTricks = player.announcedTricks[round - 1]
                            
                            Text("\(announcedTricks)")
                                .font(.system(size: dynamicSize.announceSize))
                                .bold(true)
                                .foregroundColor(.primary)
                        } else if gameManager.gameState.currentPhase.isBeforePlayingPhase {
                            let roundModifiers = determineRoundModifiers()
                            let mod = roundModifiers[id] ?? 0
                            if mod == -1 {
                                Text("🎲")
                                    .font(.system(size: dynamicSize.announceSize))
                            } else if mod == 1 {
                                OneCardIcon(size: dynamicSize.announceSize)
                            } else if mod == 2 {
                                TwoCardsIcon(size: dynamicSize.announceSize)
                            } else {
                                Text("")
                                    .font(.system(size: dynamicSize.announceSize))
                            }
                        } else {
                            Text(" ")
                                .font(.system(size: dynamicSize.announceSize))
                                .bold(true)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .background(betsColor(for: gameManager))
            .cornerRadius(5)
        }
        .padding()
        .background(Color.white.opacity(0.5))
        .cornerRadius(12)
        .shadow(radius: 5)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white, lineWidth: 2)
        )
    }
    
    func betsColor(for gameManager: GameManager) -> Color {
        let round = gameManager.gameState.round
        
        if round < 4 || !gameManager.allPlayersBet() {
            return Color.white.opacity(0)
        }
        
        let tricksSum = gameManager.gameState.players.reduce(0) { sum, player in
            sum + (player.announcedTricks.count >= round ? player.announcedTricks[round - 1] : 0)
        }
        let targetTricks = max(round - 2, 1)

        // Dynamic red or blue color based on the difference
        let difference = CGFloat(abs(tricksSum - targetTricks))

        if tricksSum > targetTricks {
            // Red for sum greater than target
            return Color.red.opacity(difference * 0.2)
        } else {
            // Blue for sum less than target
            return Color.blue.opacity(difference * 0.2)
        }
    }
    
    func determineRoundModifiers() -> [PlayerId: Int] {
        // Calculate the number of cards to deal to each player
        // or if first player has to bet randomly
        var cardsPerPlayer = [PlayerId: Int]() // PlayerId -> Cards to deal
        for player in gameManager.gameState.players {
            var extraCards = 0
            
            if gameManager.gameState.round > 3 {
                if player.place == 1 {
                    // Compute scores for all players
                    let currentScores = gameManager.gameState.players.map { $0.scores.last ?? 0 }
                    // Sort scores in descending order
                    let sortedScores = currentScores.sorted(by: >)
                    if let highest = sortedScores.first, let second = sortedScores.dropFirst().first,
                       highest > 0 && highest >= second * 2 {
                        extraCards = -1 // random bet
                    } else {
                        extraCards = 0
                    }

                } else if player.place == 2 {
                    if player.monthlyLosses > 1 && gameManager.gameState.round < 12 {
                        extraCards = 2
                    } else {
                        extraCards = 1
                    }
                    
                } else if player.place == 3 {
                    extraCards = 1
                    let playerScore = player.scores[safe: gameManager.gameState.round - 2] ?? 0
                    let secondPlayerScore = gameManager.gameState.players
                        .map { $0.scores.last ?? 0 }
                        .sorted(by: >)
                        .dropFirst()
                        .first ?? 0
                    
                    if player.monthlyLosses > 0 || Double(playerScore) <= 0.5 * Double(secondPlayerScore) {
                        extraCards = 2
                    }
                }
            }
            
            // Cap extra cards to the number of cards left in the deck for the last round
            if gameManager.gameState.round == 12 && extraCards == 2,
               let secondPlayer = gameManager.gameState.players[safe: 1],
               let thirdPlayer = gameManager.gameState.players[safe: 2],
               secondPlayer.scores[safe: gameManager.gameState.round - 2] != thirdPlayer.scores[safe: gameManager.gameState.round - 2] {
                extraCards = 1
            }
            
            cardsPerPlayer[player.id] = extraCards
            
        }

        return cardsPerPlayer
    }
}

struct TwoCardsIcon: View {
    var size: CGFloat = 30
    
    private var cardWidth: CGFloat { size * 0.72 }
    private var cardHeight: CGFloat { size }
    private var radius: CGFloat { size * 0.12 }
    
    private func cardBackground() -> some View {
        ZStack {
            // Paper gradient
            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(
                    colors: [Color.white, Color(white: 0.96)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            // Soft border
            RoundedRectangle(cornerRadius: radius)
                .stroke(Color.black.opacity(0.18), lineWidth: 1)
            // Subtle top sheen
            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.35), .clear],
                    startPoint: .top, endPoint: .center
                ))
                .blendMode(.screen)
        }
        .frame(width: cardWidth, height: cardHeight)
        .shadow(color: .black.opacity(0.10), radius: size * 0.12, x: size * 0.05, y: size * 0.05)
    }
    
    var body: some View {
        ZStack {
            // Back card
            cardBackground()
                .overlay(
                    Image(systemName: "suit.spade.fill")
                        .font(.system(size: size * 0.56))
                        .foregroundColor(.black)
                        .shadow(radius: size * 0.02)
                )
                .rotationEffect(.degrees(-10))
                .offset(x: -size * 0.10)
            
            // Front card
            cardBackground()
                .overlay(
                    Image(systemName: "suit.heart.fill")
                        .font(.system(size: size * 0.56))
                        .foregroundColor(.red)
                        .shadow(radius: size * 0.02)
                )
                .rotationEffect(.degrees(10))
                .offset(x: size * 0.10)
        }
        .background(Color.clear)
        .accessibilityLabel("Two cards modifier")
    }
}

struct OneCardIcon: View {
    var size: CGFloat = 30
    
    private var cardWidth: CGFloat { size * 0.72 }
    private var cardHeight: CGFloat { size }
    private var radius: CGFloat { size * 0.12 }
    
    private func cardBackground() -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(
                    colors: [Color.white, Color(white: 0.96)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
            RoundedRectangle(cornerRadius: radius)
                .stroke(Color.black.opacity(0.18), lineWidth: 1)
            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(0.35), .clear],
                    startPoint: .top, endPoint: .center
                ))
                .blendMode(.screen)
        }
        .frame(width: cardWidth, height: cardHeight)
        .shadow(color: .black.opacity(0.10), radius: size * 0.12, x: size * 0.05, y: size * 0.05)
    }

    var body: some View {
        cardBackground()
            .overlay(
                Image(systemName: "suit.spade.fill")
                    .font(.system(size: size * 0.56))
                    .foregroundColor(.black)
                    .shadow(radius: size * 0.02)
            )
            .background(Color.clear)
            .accessibilityLabel("One card modifier")
    }
}
