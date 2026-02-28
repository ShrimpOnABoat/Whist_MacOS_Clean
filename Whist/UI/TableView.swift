//
//  TableView.swift
//  Whist
//
//  Created by Tony Buffard on 2024-12-06.
//

import SwiftUI

struct TableView: View {
    @EnvironmentObject var gameManager: GameManager
    @ObservedObject var gameState: GameState
    @Binding var showRoundHistory: Bool
    let showWaitingPanelInPlace: Bool
    var dynamicSize: DynamicSize
    @State private var showAllInsights: Bool = false
    
    enum Mode {
        case tricks, trumps
    }
    
    let mode: Mode

    init(gameState: GameState, dynamicSize: DynamicSize, showRoundHistory: Binding<Bool> = .constant(false), showWaitingPanelInPlace: Bool = true, mode: Mode = .tricks) {
        self.gameState = gameState
        self.mode = mode
        self.dynamicSize = dynamicSize
        self._showRoundHistory = showRoundHistory
        self.showWaitingPanelInPlace = showWaitingPanelInPlace
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if gameManager.gameState.currentPhase == .waitingToStart {
                    if !showWaitingPanelInPlace {
                        EmptyView()
                    } else if gameManager.isFirstGame {
                        VStack {
                            Button(action: {
                                gameManager.startNewGameAction()
                            }) {
                                Text("Nouvelle partie")
                                    .font(.system(size: scaledFont(18, min: 14, max: 32), weight: .semibold))
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 14)
                                    .background(Color.green.opacity(0.9))
                                    .foregroundColor(.white)
                                    .cornerRadius(9)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 9)
                                            .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    } else {
                        VStack(spacing: 14) {
                            if let winner = gameManager.lastGameWinner {
                                Text("🎉🎊 BRAVO \(winner.rawValue.uppercased()) 🎊🎉")
                                    .font(.system(size: scaledFont(30, min: 22, max: 52), weight: .bold))
                                    .foregroundColor(.yellow)
                                    .shadow(radius: 5)
                                    .multilineTextAlignment(.center)
                            } else {
                                Text("🃏 Nouvelle partie")
                                    .font(.system(size: scaledFont(30, min: 22, max: 52), weight: .bold))
                                    .foregroundColor(.white)
                                    .shadow(radius: 5)
                                    .multilineTextAlignment(.center)
                            }

                            Text(dynamicHeaderSentence())
                                .font(.system(size: scaledFont(18, min: 14, max: 30), weight: .semibold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 8)

                            let topFacts = Array(gameManager.latestGameInsightFacts.prefix(3))
                            if !topFacts.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Faits marquants")
                                        .font(.system(size: scaledFont(15, min: 13, max: 28), weight: .bold))
                                        .foregroundColor(.white)
                                    ForEach(Array(topFacts.enumerated()), id: \.element.id) { index, fact in
                                        Text("\(index + 1). \(fact.text)")
                                            .font(.system(size: scaledFont(12, min: 12, max: 24)))
                                            .foregroundColor(.white.opacity(0.96))
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .frame(maxWidth: 540, alignment: .leading)
                            }

                            HStack(spacing: 12) {
                                Button(action: {
                                    showRoundHistory = true
                                }) {
                                    Text("Détails")
                                        .font(.system(size: scaledFont(15, min: 12, max: 24), weight: .semibold))
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 14)
                                        .background(Color.white.opacity(0.18))
                                        .foregroundColor(.white)
                                        .cornerRadius(9)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 9)
                                                .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())

                                Button(action: {
                                    gameManager.startNewGameAction()
                                }) {
                                    Text(gameManager.hasDeferredStartNewGame ? "Rejoindre la partie" : "Nouvelle partie")
                                        .font(.system(size: scaledFont(15, min: 12, max: 24), weight: .semibold))
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 14)
                                        .background(Color.green.opacity(0.9))
                                        .foregroundColor(.white)
                                        .cornerRadius(9)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 9)
                                                .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())

                                Button(action: {
                                    showAllInsights = true
                                }) {
                                    Text("Tous les insights")
                                        .font(.system(size: scaledFont(15, min: 12, max: 24), weight: .semibold))
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 14)
                                        .background(Color.white.opacity(0.18))
                                        .foregroundColor(.white)
                                        .cornerRadius(9)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 9)
                                                .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .frame(maxWidth: 660)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 22)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.green.opacity(0.8))
                                .shadow(radius: 12)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.5), lineWidth: 1.2)
                        )
                        .transition(.scale)
                        .sheet(isPresented: $showAllInsights) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Tous les insights")
                                    .font(.system(size: scaledFont(22, min: 18, max: 34), weight: .bold))
                                    .foregroundColor(.white)
                                if gameManager.latestGameAllInsightFacts.isEmpty {
                                    Text("Aucun insight disponible pour cette partie.")
                                        .font(.system(size: scaledFont(15, min: 12, max: 24)))
                                        .foregroundColor(.white.opacity(0.9))
                                } else {
                                    ScrollView {
                                        VStack(alignment: .leading, spacing: 10) {
                                            ForEach(Array(gameManager.latestGameAllInsightFacts.enumerated()), id: \.element.id) { index, fact in
                                                Text("\(index + 1). \(fact.text)")
                                                    .font(.system(size: scaledFont(15, min: 12, max: 24)))
                                                    .foregroundColor(.white.opacity(0.95))
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(20)
                            .frame(minWidth: 600, minHeight: 500)
                            .background(Color.black.opacity(0.85))
                        }
                    }
                } else {
                    switch mode {
                    case .tricks:
                        // Default: Display cards on the table
                        displayTrickCards(dynamicSize: dynamicSize)
                    case .trumps:
                        // Display trump cards
                        displayTrumpCards(dynamicSize: dynamicSize)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Display Trick Cards
    private func displayTrickCards(dynamicSize: DynamicSize) -> some View {
        ZStack {
            let offset = dynamicSize.tableOffset
            
            if let localPlayer = gameState.localPlayer,
               let localIndex = gameState.playOrder.firstIndex(of: localPlayer.id),
               localIndex < gameState.table.count {
                let card = gameState.table[localIndex]
                TransformableCardView(card: card, rotation: card.rotation + card.randomAngle, xOffset: card.randomOffset.x, yOffset: card.offset + card.randomOffset.y, dynamicSize: dynamicSize)
                    .zIndex(Double(localIndex))
            }
            
            if let leftPlayer = gameState.leftPlayer,
               let leftIndex = gameState.playOrder.firstIndex(of: leftPlayer.id),
               leftIndex < gameState.table.count {
                let card = gameState.table[leftIndex]
                TransformableCardView(card: card, rotation: card.rotation + card.randomAngle + CGFloat(90), xOffset: -offset + card.offset + card.randomOffset.x, yOffset: -offset + card.randomOffset.y, dynamicSize: dynamicSize)
                    .zIndex(Double(leftIndex))
            }
            
            if let rightPlayer = gameState.rightPlayer,
               let rightIndex = gameState.playOrder.firstIndex(of: rightPlayer.id),
               rightIndex < gameState.table.count {
                let card = gameState.table[rightIndex]
                TransformableCardView(card: card, rotation: card.rotation + card.randomAngle + CGFloat(90), xOffset: offset + card.offset + card.randomOffset.x, yOffset: -offset + card.randomOffset.y, dynamicSize: dynamicSize)
                    .zIndex(Double(rightIndex))
            }
        }
    }
    
    // MARK: - Display Trump Cards
    private func displayTrumpCards(dynamicSize: DynamicSize) -> some View {
        let trumpCards = gameState.table
            .sorted { card1, card2 in
                // Sort by suit order: hearts, clubs, diamonds, spades
                let suitOrder: [Suit: Int] = [.hearts: 0, .clubs: 1, .diamonds: 2, .spades: 3]
                return suitOrder[card1.suit] ?? 0 < suitOrder[card2.suit] ?? 0
            }

        return HStack(spacing: 20) {
            ForEach(trumpCards) { card in
                TransformableCardView(
                    card: card,
                    rotation: 0, // No rotation for trump cards
                    xOffset: 0,
                    yOffset: 0,
                    dynamicSize: dynamicSize
                )
            }
        }
        .frame(alignment: .center)
    }

    private func dynamicHeaderSentence() -> String {
//        if let firstFact = gameManager.latestGameInsightFacts.first {
//            return firstFact.text
//        }
        if let winner = gameManager.lastGameWinner {
            return "\(winner.rawValue.uppercased()) a dominé cette partie avec brio."
        }
        return "Prenez le temps de revoir la partie, puis rejoignez quand vous êtes prêt."
    }

    private var uiScale: CGFloat {
        min(max(dynamicSize.proportion, 0.8), 1.7)
    }

    private func scaledFont(_ base: CGFloat, min minSize: CGFloat, max maxSize: CGFloat) -> CGFloat {
        min(max(base * uiScale, minSize), maxSize)
    }
}
