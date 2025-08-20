//
//  CardView.swift
//  Whist
//
//  Created by Tony Buffard on 2024-11-18.
//  Visual representation of a card.

import SwiftUI

// MARK: CardView

struct CardView: View {
    @EnvironmentObject var gameManager: GameManager
    @ObservedObject var card: Card // Observe changes in the card
    @State private var hovered = false
    @State private var pulse: CGFloat = 0
    
    // These come from the parent:
    let isSelected: Bool      // Is this card currently selected?
    let canSelect: Bool       // Can we select more cards, or have we hit the limit?
    let onTap: () -> Void     // Callback to parent for toggling selection
    var dynamicSize: DynamicSize
    
    // Compute if this card should be greyed out based on the hovered suit
    private var shouldGreyOut: Bool {
        // Only apply to local player's hand cards that are face up
        if gameManager.hoveredSuit != nil &&
           !card.isFaceDown &&
            (card.isPlayable || gameManager.gameState.currentPhase == .choosingTrump) &&
           gameManager.gameState.localPlayer?.hand.contains(where: { $0.id == card.id }) == true {
            return card.suit != gameManager.hoveredSuit
        }
        return false
    }

    var body: some View {
        ZStack {
            // The card image:
            if card.isFaceDown && !card.isLastTrick {
                Image("Card_back")
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(4)
            } else {
                Image("\(card.suit.rawValue)_\(card.rank.rawValue)")
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(4)
                    .brightness(shouldGreyOut ? -0.3 : 0) // Slightly darken non-matching suits
            }
        }
        .frame(width: dynamicSize.cardWidth, height: dynamicSize.cardHeight)
        .overlay(
            ZStack {
                if isSelected {
                    // Outer gradient border with animated glow
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            LinearGradient(colors: [Color.cyan, Color.blue, Color.purple],
                                           startPoint: .topLeading,
                                           endPoint: .bottomTrailing),
                            lineWidth: 3
                        )
                        .shadow(color: Color.blue.opacity(0.55), radius: 6 + 10 * pulse)
                        .onAppear {
                            pulse = 0
                            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                                pulse = 1
                            }
                        }
                        .onDisappear {
                            pulse = 0
                        }

                    // Thin inner highlight to make the card pop on light/dark backgrounds
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                        .blendMode(.overlay)
                }
            }
        )
        .scaleEffect(isSelected ? 1.02 + 0.01 * pulse : 1.0)
        .offset(y: (hovered || isSelected) && (card.isPlayable || gameManager.gameState.currentPhase == .discard) ? -dynamicSize.cardHoverOffset : 0)
        .opacity(card.isPlaceholder ? 0.0 : 1.0)
        .contentShape(Rectangle())
        .onHover { hovering in
            // Only allow hover effects when we are in discard phase (if selection is allowed)
            // or when the card is playable.
            guard gameManager.gameState.currentPhase == .discard
                    ? canSelect || isSelected
                    : card.isPlayable
            else { return }
            
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                hovered = hovering
                
                // Only update the hovered suit for the local player's hand
                if hovering && !card.isFaceDown {
                    gameManager.hoveredSuit = card.suit
                } else if !hovering && gameManager.hoveredSuit == card.suit {
                    gameManager.hoveredSuit = nil
                }
            }
        }
        .onTapGesture {
            handleCardTap()
        }
    }
    
    private func handleCardTap() {
        // 1. If we’re in “discard” phase, handle discarding:
        if gameManager.gameState.currentPhase == .discard {
            if card.rank == .two && gameManager.gameState.localPlayer?.place == 2 {
                gameManager.cancelTrumpChoice()
            }
            // Let the parent do the toggling logic
            if canSelect || isSelected {
                onTap()
            }
            return
        }
        
        // 2. If we’re in some other phase, e.g. playing a trick:
        if !card.isFaceDown && card.isPlayable {
            card.isPlayable = false
            if card.rank != .two {
                let event = NSEvent.modifierFlags
                card.playAnimationType = event.contains(.shift) ? .impact : event.contains(.control) ? .failure : .normal
                gameManager.playCard(card) {
                    card.playAnimationType = .normal
                    gameManager.checkAndAdvanceStateIfNeeded()
                }
            } else {
                gameManager.selectTrumpSuit(card) {
                    gameManager.checkAndAdvanceStateIfNeeded()
                }
            }
        } else {
            if gameManager.gameState.players.contains(where: { $0.trickCards.contains(where: { $0.id == card.id }) }) {
                gameManager.showLastTrick.toggle()
            }
        }
    }
}

// MARK: TransformableCardView

struct TransformableCardView: View {
    @EnvironmentObject var gameManager: GameManager
    var dynamicSize: DynamicSize

    @ObservedObject var card: Card // Observe changes
    let scale: CGFloat
    let rotation: Double
    let xOffset: CGFloat
    let yOffset: CGFloat

    // These come from the parent:
    let isSelected: Bool      // Is this card currently selected?
    let canSelect: Bool       // Can we select more cards, or have we hit the limit?
    let onTap: () -> Void     // Callback to parent for toggling selection
    
    init(card: Card, scale: CGFloat = 1.0, rotation: Double = 0, xOffset: CGFloat = 0, yOffset: CGFloat = 0, isSelected: Bool = false, canSelect: Bool = false, onTap: @escaping () -> Void = {}, dynamicSize: DynamicSize ) {
        self.card = card
        self.scale = scale
        self.rotation = rotation
        self.xOffset = xOffset
        self.yOffset = yOffset
        self.isSelected = isSelected
        self.canSelect = canSelect
        self.onTap = onTap
        self.dynamicSize = dynamicSize
    }
    
    var body: some View {
        CardView(card: card, isSelected: isSelected, canSelect: canSelect, onTap: onTap, dynamicSize: dynamicSize)
            .frame(width: dynamicSize.cardWidth * scale, height: dynamicSize.cardHeight * scale)
            .scaleEffect(scale)
            .rotationEffect(Angle(degrees: rotation))
            .offset(x: xOffset, y: yOffset)
            .overlay(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: CardTransformPreferenceKey.self, value: [
                            card.id: CardState(
                                position: CGPoint(
                                    x: geometry.frame(in: .named("contentArea")).midX + xOffset,
                                    y: geometry.frame(in: .named("contentArea")).midY + yOffset
                                ),
                                rotation: rotation,
                                scale: scale,
                                zIndex: Double(10)
                            )
                        ])
                }
            )
    }
}

    
// MARK: - Preview

struct CardView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a sample card
        let sampleCard = Card(suit: .hearts, rank: .ace)
        sampleCard.isFaceDown = false
        sampleCard.isPlayable = true
        
        let scale = CGFloat.random(in: 0.8...1.2)
        let rotation = Double.random(in: -35...35)

        return
            GeometryReader { geometry in
                let dynamicSize = DynamicSize(from: geometry)
                TransformableCardView(card: sampleCard, scale: scale, rotation: rotation, xOffset: 0, yOffset: 0, dynamicSize: dynamicSize)
                    .previewDisplayName("Card View Preview")
                    .previewLayout(.sizeThatFits)
                    .frame(width: 100, height: 150)
            
        }
    }
}
