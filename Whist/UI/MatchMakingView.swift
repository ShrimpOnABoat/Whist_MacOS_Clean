//
//  MatchmakingView.swift
//  Whist
//
//  Created by Tony Buffard on 2024-11-18.
//  Interface for matchmaking and connecting players with P2P visualizations.

import SwiftUI

struct MatchMakingView: View {
    @EnvironmentObject var gameManager: GameManager
    @EnvironmentObject var preferences: Preferences
    @State private var animationOffset: CGFloat = 0
    
    // Helper to get a user-friendly string and color for the phase
    private func displayInfo(for phase: P2PConnectionPhase) -> (text: String, color: Color) {
        switch phase {
        case .idle:
            return ("Inactif", .gray)
        case .initiating:
            return ("Initialisation...", .yellow)
        case .offering:
            return ("Envoi de l'offre...", .orange)
        case .waitingForOffer:
            return ("En attente d'une offre...", .yellow)
        case .answering:
            return ("Envoi de la réponse...", .orange)
        case .waitingForAnswer:
            return ("En attente d'une réponse...", .yellow)
        case .exchangingNetworkInfo:
            return ("Échange d'infos réseau...", .blue)
        case .connecting:
            return ("Connexion...", .purple)
        case .iceReconnecting:
            return ("Reconnexion en cours...", .yellow)
        case .connected:
            return ("Connecté", .green)
        case .failed:
            return ("Échec", .red)
        case .disconnected:
            return ("Déconnecté", .pink)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.blue.opacity(0.1),
                        Color.purple.opacity(0.1),
                        Color.indigo.opacity(0.05)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                VStack(spacing: 30) {
                    // Title
                    Text("Salle d'attente")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.top, 20)
                    
                    // Connection visualization area
                    ZStack {
                        // Connection lines and animations
                        ConnectionVisualizationView(
                            localPlayer: gameManager.gameState.localPlayer,
                            remotePlayers: gameManager.gameState.players.filter { $0.username != preferences.playerId },
                            geometry: geometry,
                            animationOffset: animationOffset
                        )
                        
                        // Player nodes
                        PlayerNodesView(
                            localPlayer: gameManager.gameState.localPlayer,
                            remotePlayers: gameManager.gameState.players.filter { $0.username != preferences.playerId },
                            preferences: preferences,
                            displayInfo: displayInfo,
                            geometry: geometry
                        )
                    }
                    .frame(height: min(geometry.size.height * 0.6, 400))
                    
                    Spacer()
                }
            }
        }
        .navigationTitle("Recherche de Partie")
        .onAppear {
//            startAnimations()
        }
    }
    
    private func startAnimations() {
        // Continuous flow animation for connection lines
        withAnimation(.linear(duration: 0.20).repeatForever(autoreverses: false)) {
            animationOffset = 1.0
        }
        
    }
}

// MARK: - Connection Visualization
struct ConnectionVisualizationView: View {
    let localPlayer: Player?
    let remotePlayers: [Player]
    let geometry: GeometryProxy
    let animationOffset: CGFloat
    
    var body: some View {
        Canvas { context, size in
            guard localPlayer != nil else { return }

            let topCenter = CGPoint(x: size.width / 2, y: size.height * 0.20)
            let radius: CGFloat = min(size.width, size.height) * 0.5
            let baseY = size.height * 1.05
            let baseX = size.width / 2

            for (index, player) in remotePlayers.enumerated() {
                let angle = Double(index) == 0 ? -0.5 : 0.5
                let x = baseX + CGFloat(sin(angle * .pi)) * radius
                let y = baseY + CGFloat(cos(angle * .pi)) * radius
                let remotePoint = CGPoint(x: x, y: y)

                drawConnection(
                    context: context,
                    from: topCenter,
                    to: remotePoint,
                    player: player,
                    animationOffset: animationOffset
                )
            }
        }
    }
    
    private func drawConnection(context: GraphicsContext, from start: CGPoint, to end: CGPoint, player: Player, animationOffset: CGFloat) {
        let phaseInfo = displayInfo(for: player.connectionPhase)

        // Adjust start and end points to be at the edge of the player circles
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = sqrt(dx * dx + dy * dy)
        let unitDx = dx / distance
        let unitDy = dy / distance
        let padding: CGFloat = 35  // half the 70pt avatar diameter

        let adjustedStart = CGPoint(x: start.x + unitDx * padding, y: start.y + unitDy * padding)
        let adjustedEnd = CGPoint(x: end.x - unitDx * padding, y: end.y - unitDy * padding)

        // Base connection line
        var path = Path()
        path.move(to: adjustedStart)
        path.addLine(to: adjustedEnd)

        let baseColor = player.isP2PConnected ? Color.green : phaseInfo.color

        context.stroke(
            path,
            with: .color(baseColor.opacity(0.3)),
            style: StrokeStyle(lineWidth: 2, lineCap: .round)
        )

        // Animated data flow
        if player.connectionPhase != .idle && player.connectionPhase != .failed {
            drawDataFlow(context: context, from: adjustedStart, to: adjustedEnd, color: baseColor, offset: animationOffset)
        }

        switch player.connectionPhase {
        case .connected:
            drawConnectedEffect(context: context, from: adjustedStart, to: adjustedEnd, offset: animationOffset)
        case .exchangingNetworkInfo, .connecting:
            drawBidirectionalFlow(context: context, from: adjustedStart, to: adjustedEnd, color: baseColor, offset: animationOffset)
        default:
            break
        }
    }
    
    private func drawDataFlow(context: GraphicsContext, from start: CGPoint, to end: CGPoint, color: Color, offset: CGFloat) {
        let distance = sqrt(pow(end.x - start.x, 2) + pow(end.y - start.y, 2))
        let direction = CGPoint(
            x: (end.x - start.x) / distance,
            y: (end.y - start.y) / distance
        )
        
        // Create flowing dots
        for i in 0..<3 {
            let progress = (offset + CGFloat(i) * 0.3).truncatingRemainder(dividingBy: 1.0)
            let position = CGPoint(
                x: start.x + direction.x * distance * progress,
                y: start.y + direction.y * distance * progress
            )
            
            let dotSize: CGFloat = 4 + sin(progress * .pi) * 2
            let rect = CGRect(
                x: position.x - dotSize/2,
                y: position.y - dotSize/2,
                width: dotSize,
                height: dotSize
            )
            
            context.fill(
                Path(ellipseIn: rect),
                with: .color(color.opacity(0.8))
            )
        }
    }
    
    private func drawConnectedEffect(context: GraphicsContext, from start: CGPoint, to end: CGPoint, offset: CGFloat) {
        // Stable connection with gentle pulse
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        
        let pulseOpacity = 0.6 + sin(offset * .pi * 2) * 0.3
        context.stroke(
            path,
            with: .color(Color.green.opacity(pulseOpacity)),
            style: StrokeStyle(lineWidth: 3, lineCap: .round)
        )
    }
    
    private func drawBidirectionalFlow(context: GraphicsContext, from start: CGPoint, to end: CGPoint, color: Color, offset: CGFloat) {
        // Data flowing both ways
        drawDataFlow(context: context, from: start, to: end, color: color, offset: offset)
        drawDataFlow(context: context, from: end, to: start, color: color.opacity(0.6), offset: offset + 0.5)
    }
    
    private func displayInfo(for phase: P2PConnectionPhase) -> (text: String, color: Color) {
        switch phase {
        case .idle: return ("Inactif", .gray)
        case .initiating: return ("Initialisation ...", .yellow)
        case .offering: return ("Envoi de l'offre ...", .orange)
        case .waitingForOffer: return ("En attente d'une offre ...", .yellow)
        case .answering: return ("Envoi de la réponse ...", .orange)
        case .waitingForAnswer: return ("En attente d'une réponse ...", .yellow)
        case .exchangingNetworkInfo: return ("Échange d'infos réseau ...", .blue)
        case .connecting: return ("Connexion ...", .purple)
        case .iceReconnecting: return ("Reconnexion en cours ...", .yellow)
        case .connected: return ("Connecté", .green)
        case .failed: return ("Échec", .red)
        case .disconnected: return ("Déconnecté", .pink)
        }
    }
}

// MARK: - Player Nodes
struct PlayerNodesView: View {
    let localPlayer: Player?
    let remotePlayers: [Player]
    let preferences: Preferences
    let displayInfo: (P2PConnectionPhase) -> (text: String, color: Color)
    let geometry: GeometryProxy

    // Removed pulseScale state as each PlayerNodeView now manages its own animation.

    var body: some View {
        ZStack {
            // Local player at the top center
            if let localPlayer = localPlayer {
                PlayerNodeView(
                    player: localPlayer,
                    isLocal: true,
                    phaseInfo: ("Vous", .primary)
                )
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.15)
            }

            // Remote players at the bottom forming a triangle
            let radius: CGFloat = min(geometry.size.width, geometry.size.height) * 0.25
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height * 0.6

            ForEach(Array(remotePlayers.enumerated()), id: \.element.id) { index, player in
                let angle = Double(index) == 0 ? -0.5 : 0.5  // Two fixed positions for a triangle base
                let x = centerX + CGFloat(sin(angle * .pi)) * radius
                let y = centerY + CGFloat(cos(angle * .pi)) * radius

                let phaseInfo = displayInfo(player.connectionPhase)

                PlayerNodeView(
                    player: player,
                    isLocal: false,
                    phaseInfo: phaseInfo
                )
                .position(x: x, y: y)
            }
        }
    }
}

// MARK: - Individual Player Node
struct PlayerNodeView: View {
    let player: Player
    let isLocal: Bool
    let phaseInfo: (text: String, color: Color)
    @State private var glowScale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Outer glow for connecting players (animated individually)
                if !isLocal && !player.isP2PConnected && player.connectionPhase != .idle {
                    Circle()
                        .fill(phaseInfo.color.opacity(0.3))
                        .frame(width: 100, height: 100)
                        .scaleEffect(glowScale)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                                glowScale = 1.2
                            }
                        }
                }
                
                // Avatar
                Group {
                    if let image = player.image {
                        image
                            .resizable()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                    }
                }
                .scaledToFit()
                .frame(width: 70, height: 70)
                .background(player.imageBackgroundColor ?? Color.gray)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(isLocal ? Color.blue : phaseInfo.color, lineWidth: 3)
                )
                .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
            }
            
            // Player info
            VStack(spacing: 4) {
                Text(player.username)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if !isLocal {
                    HStack(spacing: 4) {
                        Text(phaseInfo.text)
                            .font(.caption)
                            .foregroundColor(phaseInfo.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(phaseInfo.color.opacity(0.15))
                            .cornerRadius(8)
                        
                        Image(systemName: player.isP2PConnected ? "wifi" : "wifi.slash")
                            .foregroundColor(player.isP2PConnected ? .green : .red)
                            .font(.caption)
                    }
                } else {
                    Text("Vous")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(8)
                }
            }
        }
    }
}

// Keep the existing InvitingButtonStyle
struct InvitingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? Color.blue.opacity(0.7) : Color.blue)
            .cornerRadius(12)
            .shadow(radius: 5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.2), value: configuration.isPressed)
    }
}
