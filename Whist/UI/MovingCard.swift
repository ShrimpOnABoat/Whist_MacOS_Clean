//
//  MovingCard.swift
//  Whist
//
//  Created by Tony Buffard on 2025-02-13.
//

import SwiftUI

// MARK: - MovingCard Class

class MovingCard: Identifiable, ObservableObject {
    let id: UUID = UUID()
    let card: Card
    let from: CardPlace
    let to: CardPlace
    let placeholderCard: Card
    let fromState: CardState
    @Published var toState: CardState? = nil
    
    // Initializer
    init(card: Card,from: CardPlace, to: CardPlace, placeholderCard: Card, fromState: CardState) {
        self.card = card
        self.from = from
        self.to = to
        self.placeholderCard = placeholderCard
        self.fromState = fromState
    }
}
extension MovingCard: CustomStringConvertible {
    var description: String {
        return "\(card)"
    }
}
// MARK: - MovingCardView

struct MovingCardView: View {
    @EnvironmentObject var gameManager: GameManager
    @ObservedObject var movingCard: MovingCard
    var dynamicSize: DynamicSize
    
    @State private var position: CGPoint
    @State private var rotation: Double
    @State private var scale: CGFloat
    @State private var hasAnimated: Bool = false // To ensure animation occurs only once
    @State private var animationDuration: TimeInterval = 0.4
    // Special animation state variables
    @State private var offsetY: CGFloat = 0
    
    init(movingCard: MovingCard, dynamicSize: DynamicSize) {
        self.movingCard = movingCard
        self.dynamicSize = dynamicSize
        _position = State(initialValue: movingCard.fromState.position)
        _rotation = State(initialValue: movingCard.fromState.rotation)
        _scale = State(initialValue: movingCard.fromState.scale)
    }

    var body: some View {
        // elevate the card a little
        CardView(card: movingCard.card, isSelected: false, canSelect: false, onTap: {}, dynamicSize: dynamicSize)
            .frame(width: dynamicSize.cardWidth, height: dynamicSize.cardHeight)
            .rotationEffect(.degrees(rotation))
            .scaleEffect(scale)
            .position(position)
            .shadow(
                color: Color.black.opacity(0.3),
                radius: movingCard.card.elevation / 4,
                x: movingCard.card.elevation,
                y: movingCard.card.elevation
            )
            .onAppear {
                movingCard.card.elevation = 5
            }
            .onChange(of: movingCard.toState) { newToState in
                guard let toState = newToState, !hasAnimated else { return }
                hasAnimated = true

                switch movingCard.card.playAnimationType {
                case .normal:
                    if movingCard.to == .table { movingCard.card.isFaceDown = false } // Show the card if playCard
                    // For normal moves, add a random spin and animate directly to the target state.
                    let randomSpin: Double = {
                        if [.localPlayer, .leftPlayer, .rightPlayer].contains(movingCard.from) {
                            return Double([-360, 0, 360].randomElement() ?? 0)
                        } else {
                            return 0
                        }
                    }()
                    gameManager.playSound(named: "play card")
                    withAnimation(Animation.timingCurve(0.4, 0, 0.2, 1, duration: animationDuration)) {
                        self.rotation = toState.rotation + randomSpin
                        self.scale = toState.scale
                        self.position = toState.position
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
                        logger.log("Finalizing move for \(movingCard.card) with normal animation")
                        gameManager.finalizeMove(movingCard)
                    }

                case .impact, .failure:
                    // --- Common "Suspense" part: Make the card appear to float higher than before ---
                    let shouldBeFaceDown = (gameManager.gameState.round > 3) && (movingCard.from != .localPlayer)
                    logger.log("🇫🇷 isFaceDown: \(movingCard.card.isFaceDown), shouldBeFaceDown: \(shouldBeFaceDown), round = \(gameManager.gameState.round), from: \(movingCard.from)")
                    let suspenseDuration: TimeInterval = 1
                    withAnimation(.easeOut(duration: suspenseDuration)) {
                        self.scale = 1.3
                        self.rotation = toState.rotation
                        self.position = CGPoint(
                            x: toState.position.x,
                            y: toState.position.y - 60 // raise it higher
                        )
                        movingCard.card.elevation = 20 // bigger shadow while in the air
                        movingCard.card.isFaceDown = shouldBeFaceDown
                    }

                    // Phase 2: After the suspense, perform the special animation.
                    DispatchQueue.main.asyncAfter(deadline: .now() + suspenseDuration) {
                        movingCard.card.isFaceDown = false
                        switch movingCard.card.playAnimationType {
                        case .impact:
                            // We'll create a more dramatic, powerful impact animation
                            withAnimation(.none) {
                                // Quick drop with slight scale increase for emphasis
                                self.scale = 1.2
                                self.rotation = toState.rotation
                                self.position = toState.position
                                movingCard.card.elevation = 0
                            }
                            
                            // Add camera shake effect
                            gameManager.triggerCameraShake(intensity: 8)
                            
                            // Show impact effect
                            gameManager.effectPosition = self.position
                            gameManager.showImpactEffect = true
                            
                            // Play impact sound - a powerful thud/impact
                            gameManager.playSound(named: "powerful impact")
                            
                            // Add secondary animations after the initial impact
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    // Scale back down with slight overshoot
                                    self.scale = 0.95
                                }
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                        // Return to final size
                                        self.scale = toState.scale
                                    }
                                    
                                    // Hide impact effect after it completes
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                                        gameManager.showImpactEffect = false
                                        gameManager.finalizeMove(movingCard)
                                    }
                                }
                            }
                        case .failure:
                            // 1) Gentle drop with slight tilt
                            withAnimation(.easeOut(duration: 0.25)) {
                                self.scale = 1.0
                                self.rotation = toState.rotation - 3 // Just a slight tilt
                                self.position = CGPoint(
                                    x: toState.position.x + 5, // Subtle shift
                                    y: toState.position.y + 5
                                )
                                movingCard.card.elevation = 0
                            }

                            // 2) Show the subtle failure effect and add a mild "settling" animation
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                // Show the subtle failure effect
                                gameManager.effectPosition = self.position
                                gameManager.showSubtleFailureEffect = true
                                
                                // Play a subtle sound - something like a soft "whoosh" or light tap
                                gameManager.playSound(named: "soft fail")
                                
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                    // Subtle settling motion
                                    self.position = CGPoint(
                                        x: toState.position.x,
                                        y: toState.position.y + 2 // Just a tiny bit of extra drop
                                    )
                                    self.rotation = toState.rotation
                                }

                                // 3) Final settling into position
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    gameManager.showSubtleFailureEffect = false
                                    
                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                        self.scale = toState.scale
                                        self.rotation = toState.rotation
                                        self.position = toState.position
                                        movingCard.card.elevation = 0
                                    }
                                    
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        gameManager.finalizeMove(movingCard)
                                    }
                                }
                            }
                        default:
                            break
                        }
                    }
                }
            }
    }
}

// MARK: Special play card animations
enum cardAnimationType: Codable {
    case impact   // For a powerful, game-changing move
    case failure  // For when a player is expected to win the trick but doesn’t
    case normal // For all the other cases
}

/// A simple explosion effect for the "impact" animation.
struct ExplosionView: View {
    @State private var scale: CGFloat = 0.1
    @State private var opacity: Double = 1.0

    var body: some View {
        Circle()
            .fill(
                RadialGradient(gradient: Gradient(colors: [.yellow, .orange, .red]),
                               center: .center,
                               startRadius: 0,
                               endRadius: 50)
            )
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.3)) {
                    scale = 3.0
                    opacity = 0
                }
            }
    }
}

// Model for an individual explosion particle.
struct ExplosionParticleModel: Identifiable {
    let id = UUID()
    let angle: Double        // Direction (in degrees)
    let distance: CGFloat    // How far it will travel
    let duration: Double     // Animation duration
    let color: Color         // Particle color
}

// A single explosion particle view.
struct ExplosionParticleView: View {
    let model: ExplosionParticleModel
    @State private var offset: CGSize = .zero
    @State private var opacity: Double = 1.0
    @State private var scale: CGFloat = 1.0

    var body: some View {
        Circle()
            .fill(model.color)
            .frame(width: 6, height: 6)
            .offset(offset)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                // Convert angle to radians and compute the offset.
                let radians = model.angle * .pi / 180
                let dx = cos(radians) * model.distance
                let dy = sin(radians) * model.distance
                withAnimation(.easeOut(duration: model.duration)) {
                    offset = CGSize(width: dx, height: dy)
                    opacity = 0
                    scale = 2.0
                }
            }
    }
}
