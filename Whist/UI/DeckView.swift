//
//  DeckView.swift
//  Whist
//
//  Created by Tony Buffard on 2024-12-05.
//

import SwiftUI

struct DeckView: View {
    @EnvironmentObject var gameManager: GameManager
    @ObservedObject var gameState: GameState
    var dynamicSize: DynamicSize

    // Cache random transforms for each card (to ensure consistent shuffle during the animation)
    @State private var randomOffsets: [String: CGSize] = [:]
    @State private var randomRotations: [String: Double] = [:]
    
    init(gameState: GameState, dynamicSize: DynamicSize) {
        self.gameState = gameState
        self.dynamicSize = dynamicSize
    }
    
    var body: some View {
        ZStack {
            if gameState.deck.isEmpty {
                // Empty deck placeholder
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray, style: StrokeStyle(lineWidth: 2, dash: [5, 5]))
                    .frame(width: dynamicSize.cardWidth * GameConstants.deckCardsScale, height: dynamicSize.cardHeight * GameConstants.deckCardsScale)
                    .overlay(
                        Text("Deck")
                            .font(.caption)
                            .foregroundColor(.gray)
                    )
            } else {
                ForEach(Array(gameState.deck.enumerated()), id: \.offset) { index, card in
                    let baseOffset = CGSize(width: CGFloat(index) * GameConstants.deckOffset.x,
                                            height: CGFloat(index) * GameConstants.deckOffset.y)
                    
                    // Use random offset/rotation if shuffling
                    let shuffleOffset = randomOffsets[card.id] ?? .zero
                    let shuffleRotation = randomRotations[card.id] ?? 0
                    
                    TransformableCardView(card: card,
                                          scale: GameConstants.deckCardsScale,
                                          xOffset: gameManager.isShuffling ? shuffleOffset.width : baseOffset.width,
                                          yOffset: gameManager.isShuffling ? shuffleOffset.height : baseOffset.height,
                                          dynamicSize: dynamicSize)
                    .rotationEffect(.degrees(gameManager.isShuffling ? shuffleRotation : 0))
                    .zIndex(Double(index)) // Higher index on top
                }
            }
        }
        .padding()
        .onAppear {
            // Pass the simulateShuffle function to the GameManager
            gameManager.shuffleCallback = { newDeck, completion in
                self.simulateShuffle(newDeck: newDeck, completion: completion)
            }
        }
        // Animate deck changes (e.g., when a card is drawn or discarded)
        .animation(.default, value: gameState.deck)
    }
    
    func simulateShuffle(newDeck: [Card], completion: @escaping () -> Void) {
        // Play a shuffle sound
        gameManager.playSound(named: "card shuffle")
        
        // Generate random transforms for each card
        randomOffsets = gameState.deck.reduce(into: [:]) { dict, card in
            dict[card.id] = CGSize(
                width: CGFloat.random(in: -GameConstants.deckShuffleOffset...GameConstants.deckShuffleOffset),
                height: CGFloat.random(in: -GameConstants.deckShuffleOffset...GameConstants.deckShuffleOffset)
            )
        }
        randomRotations = gameState.deck.reduce(into: [:]) { dict, card in
            dict[card.id] = Double.random(in: -GameConstants.deckShuffleAngle...GameConstants.deckShuffleAngle) // random angle
        }
        
        // Start shuffling animation
        withAnimation(.easeInOut(duration: GameConstants.deckShuffleDuration / 3)) {
            gameManager.isShuffling = true
        }
        
        // Shake it up a bit during the animation
        DispatchQueue.main.asyncAfter(deadline: .now() + GameConstants.deckShuffleDuration / 3) {
            withAnimation(.easeInOut(duration: GameConstants.deckShuffleDuration / 3)) {
                gameState.deck = newDeck // Update the logical order of the deck

                randomOffsets = gameState.deck.reduce(into: [:]) { dict, card in
                    dict[card.id] = CGSize(
                        width: CGFloat.random(in: -GameConstants.deckShuffleOffset...GameConstants.deckShuffleOffset),
                        height: CGFloat.random(in: -GameConstants.deckShuffleOffset...GameConstants.deckShuffleOffset)
                    )
                }
                randomRotations = gameState.deck.reduce(into: [:]) { dict, card in
                    dict[card.id] = Double.random(in: -GameConstants.deckShuffleAngle...GameConstants.deckShuffleAngle)
                }
            }
        }
        
        // Finalize shuffle and update the deck state
        DispatchQueue.main.asyncAfter(deadline: .now() + GameConstants.deckShuffleDuration * 2 / 3) {
            withAnimation(.easeInOut(duration: GameConstants.deckShuffleDuration / 3)) {
                gameManager.isShuffling = false
            }
            completion()
        }
    }
}
