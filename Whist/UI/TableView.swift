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
                    } else {
                        VStack {
                            Button(action: {
                                gameManager.startNewGameAction()
                            }) {
                                Text("Nouvelle partie")
                                    .font(.system(size: 18, weight: .semibold))
                                    .padding(.vertical, 9)
                                    .padding(.horizontal, 16)
                                    .gameActionCapsule()
                            }
                            .buttonStyle(GameHoverLiftButtonStyle(isActive: true))
                            .buttonStyle(PlainButtonStyle())
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
}
