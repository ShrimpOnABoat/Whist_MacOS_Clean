//
//  GameView.swift
//  Whist
//
//  Created by Tony Buffard on 2024-11-18.
//  The primary game interface.

import SwiftUI

// MARK: - PreferenceKey

struct CardTransformPreferenceKey: PreferenceKey {
    typealias Value = [String: CardState]
    
    static var defaultValue: [String: CardState] = [:]
    
    static func reduce(value: inout [String: CardState], nextValue: () -> [String: CardState]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - GameView

struct GameView: View {
    @EnvironmentObject var gameManager: GameManager
    @EnvironmentObject var preferences: Preferences
    @State private var cardTransforms: [String: CardState] = [:]
    @State private var showMatchmaking: Bool = true
    @State private var showAlert: Bool = false
    @State private var showConfirmation: Bool = false
    @State private var savedGameExists: Bool = false
    @State private var playerID: String = ""
    @State private var showRoundHistory: Bool = false
    @State private var didMeasureDeck: Bool = false
    @State private var background: AnyView = AnyView(EmptyView())
    @State private var backgroundBaseColorIndex: Int = 0
    @State private var isHonkOnCooldown: Bool = false
    
    private var shouldShowPostGameOverlay: Bool {
        gameManager.gameState.currentPhase == .waitingToStart &&
        gameManager.showPostGameResultScreen
    }
    
    func refreshBackground() {
        logger.log("Refreshing backgroung")
        // Compute enabled indices off the main thread
        let enabledIndices = self.preferences.enabledRandomColors.enumerated().compactMap { (index, isEnabled) in
            isEnabled ? index : nil
        }
        // Pick a random index from enabled indices
        let randomIndex = enabledIndices.randomElement() ?? 0
        // Determine wear intensity
        let wear: CGFloat = self.preferences.wearIntensity ? CGFloat.random(in: 0...1) : 0
        // Determine motif presence
        let motif: Bool = self.preferences.motif
        // Create the background view
        let newBackground = AnyView(FeltBackgroundView(
            baseColorIndex: randomIndex,
            radialShadingStrength: 0.58,
            wearIntensity: wear,
            motifVisibility: motif ? 0.13 : 0,
            motifScale: 0.42,
            showScratches: Bool.random()
        ))
        // Update UI on the main thread
        self.backgroundBaseColorIndex = randomIndex
        self.background = newBackground
        logger.log("Finished executing background refresh")
    }

    // Matches the action button feel used in PlayerView (hover lift + slight press scale)
    struct HoverMoveUpButtonStyle: ButtonStyle {
        let isActive: Bool
        @State private var yOffset: CGFloat = 0

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
                .offset(y: configuration.isPressed ? -2 : (isActive ? yOffset : 0))
                .animation(.easeInOut(duration: 0.05), value: configuration.isPressed)
                .animation(.easeInOut(duration: 0.05), value: yOffset)
                .onHover { isHovering in
                    if isActive {
                        withAnimation {
                            yOffset = isHovering ? -3 : 0
                        }
                    }
                }
        }
    }

    // Icon-only action button, styled like PlayerView's action buttons
    struct InsetTableButton: View {
        let systemName: String?
        let imageName: String?
        let size: CGFloat
        var isOn: Bool = false
        var accent: () -> Color = { .green }
        var isEnabled: Bool = true
        var action: () -> Void

        var body: some View {
            Button(action: action) {
                Group {
                    if let imageName {
                        Image(imageName)
                            .resizable()
                            .scaledToFit()
                            .padding(size * 0.22)
                            .foregroundColor(isOn ? .white : .black)
                    } else if let systemName {
                        Image(systemName: systemName)
                            .font(.system(size: size * 0.48, weight: .heavy))
                            .foregroundColor(isOn ? .white : .black)
                    }
                }
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(isOn ? accent() : Color.white.opacity(0.52))
                        .background(
                            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
                .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 5)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .strokeBorder(isOn ? Color.white.opacity(0.7) : GameVisualStyle.glassStroke, lineWidth: 1.2)
                )
            }
            .buttonStyle(HoverMoveUpButtonStyle(isActive: isEnabled))
            .buttonStyle(PlainButtonStyle())
            .disabled(!isEnabled)
            .accessibilityLabel(Text(systemName ?? imageName ?? "button"))
        }
    }
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let dynamicSize = DynamicSize(from: geometry)
                if shouldShowPostGameOverlay {
                    ZStack {
                        background

                        GameResultView(
                            gameState: gameManager.gameState,
                            showRoundHistory: $showRoundHistory,
                            feltColorIndex: backgroundBaseColorIndex,
                            dynamicSize: dynamicSize
                        )

                        ConfettiCannon(trigger: $gameManager.showConfetti, num: 100)
                            .ignoresSafeArea()
                            .transition(.opacity)
                    }
                } else if let localPlayer = gameManager.gameState.localPlayer,
                          let leftPlayer = gameManager.gameState.leftPlayer,
                          let rightPlayer = gameManager.gameState.rightPlayer,
                          let dealer = gameManager.gameState.dealer {
                    // Proceed with your ZStack and layout
                    ZStack {
                        // Background
                        background
                        //                    GridOverlay(spacing: 50)
                        
                        // Effects layer (always under the cards but above the background)
                        ZStack {
                            if gameManager.showImpactEffect {
                                ProceduralImpactView()
                                    .frame(width: 300, height: 300)
                                    .position(gameManager.effectPosition)
                                    .onAppear {
                                        gameManager.playSound(named: "impact")
                                    }
                                ProceduralCracksView()
                                    .blur(radius: 1)
                                    .blendMode(.multiply)
                                    .frame(width: 250, height: 250)
                                    .position(gameManager.effectPosition)
                            }
                            if gameManager.showSubtleFailureEffect {
                                SubtleFailureView()
                                    .frame(width: 200, height: 200)
                                    .position(gameManager.effectPosition)
                                    .onAppear {
                                        gameManager.playSound(named: "fail")
                                    }
                            }
                        }
                    }
                    .zIndex(0)
                    
                    ZStack {
                        VStack(spacing: 0) {
                            HStack(alignment: .center, spacing: 0) {
                                PlayerView(player: leftPlayer, dynamicSize: dynamicSize, isDealer: dealer == leftPlayer.id)
                                    .frame(width: dynamicSize.sidePlayerWidth, height: dynamicSize.sidePlayerHeight)
                                VStack(spacing: 0) {
                                    Group {
                                        HStack {
                                            TrumpView(dynamicSize: dynamicSize)
                                            
                                            Button(action: {
                                                if gameManager.gameState.round > 1 {
                                                    showRoundHistory.toggle()
                                                }
                                            }) {
                                                ScoreBoardView(dynamicSize: dynamicSize)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            .keyboardShortcut(KeyEquivalent("s"), modifiers: [])
                                            
                                            DeckView(gameState: gameManager.gameState, dynamicSize: dynamicSize)
                                        }
                                    }
                                    .frame(width: dynamicSize.scoreboardWidth, height: dynamicSize.scoreboardHeight)
                                    
                                    ZStack {
                                        ZStack {
                                            if !(gameManager.showLastTrick && gameManager.gameState.currentPhase == .playingTricks) {
                                                if gameManager.gameState.currentPhase != .choosingTrump {
                                                    TableView(
                                                        gameState: gameManager.gameState,
                                                        dynamicSize: dynamicSize,
                                                        showRoundHistory: $showRoundHistory,
                                                        showWaitingPanelInPlace: !shouldShowPostGameOverlay
                                                    )
                                                } else {
                                                    TableView(
                                                        gameState: gameManager.gameState,
                                                        dynamicSize: dynamicSize,
                                                        showRoundHistory: $showRoundHistory,
                                                        showWaitingPanelInPlace: !shouldShowPostGameOverlay,
                                                        mode: .trumps
                                                    )
                                                }
                                            } else {
                                                // Display a background for the last trick
                                                ZStack {
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .fill(GameVisualStyle.glassFill) // Background with opacity
                                                        .overlay(
                                                            VStack {
                                                                Text(gameManager.gameState.lastTrick.isEmpty ? "Pas de dernier pli" : "Dernier pli")
                                                                    .font(.headline)
                                                                    .foregroundColor(.black)
                                                                    .padding(.bottom, 8) // Ensure padding at the bottom
                                                                Spacer()
                                                            }
                                                        )
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: 12)
                                                                .stroke(GameVisualStyle.glassStroke, lineWidth: 1.2) // Add a white border
                                                        )
                                                }
                                                
                                            }
                                        }
                                        // MARK: Options View
                                        if gameManager.showOptions {
                                            OptionsView(dynamicSize: dynamicSize)
                                                .transition(.scale)
                                                .animation(.easeInOut, value: gameManager.showOptions)
                                        }
                                    }
                                    .frame(width: dynamicSize.tableWidth, height: dynamicSize.tableHeight)
                                }
                                PlayerView(player: rightPlayer, dynamicSize: dynamicSize, isDealer: dealer == rightPlayer.id)
                                    .frame(width: dynamicSize.sidePlayerWidth, height: dynamicSize.sidePlayerHeight)
                            }
                            PlayerView(player: localPlayer, dynamicSize: dynamicSize, isDealer: dealer == localPlayer.id)
                                .frame(width: dynamicSize.localPlayerWidth, height: dynamicSize.localPlayerHeight)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity) //, alignment: .bottom)
                        
                        ConfettiCannon(trigger: $gameManager.showConfetti, num: 100)
                            .ignoresSafeArea()
                            .transition(.opacity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .coordinateSpace(name: "contentArea")
                    .cameraShake(offset: $gameManager.cameraShakeOffset)
                    .onAppear() {
                        logger.log("🎾🎾🎾 GameView is on!")
                    }
                } else {
                    ZStack {
                        Color.clear
                        ProgressView("Mise en place du jeu...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                            .scaleEffect(1.5)
                            .padding()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            var message = "🎾🎾🎾 GameView refresh"
                            if gameManager.gameState.localPlayer == nil {
                                message += " - localPlayer is nil"
                            }
                            if gameManager.gameState.leftPlayer == nil {
                                message += " - leftPlayer is nil"
                            }
                            if gameManager.gameState.rightPlayer == nil {
                                message += " - rightPlayer is nil"
                            }
                            if gameManager.gameState.dealer == nil {
                                message += " - dealer is nil"
                            }
                            logger.log(message)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                gameManager.objectWillChange.send()
                            }
                        }
                    }
                }
                
                if !shouldShowPostGameOverlay {
                    // MARK: Dealer button
                    DealerButton(size: dynamicSize.dealerButtonSize)
                        .position(gameManager.dealerPosition)
                        .animation(.easeOut, value: gameManager.dealerPosition)
                    
                    // MARK: Show last trick
                    if gameManager.showLastTrick && gameManager.gameState.currentPhase == .playingTricks {
                        ZStack {
                            if !gameManager.gameState.lastTrick.isEmpty {
                                GeometryReader { geometry in
                                    ZStack {
                                        ForEach(gameManager.gameState.lastTrickCardStates.sorted(by: { $0.value.zIndex < $1.value.zIndex }), id: \.key) { playerId, cardState in
                                            if let card = gameManager.gameState.lastTrick[playerId] {
                                                TransformableCardView(
                                                    card: card,
                                                    rotation: cardState.rotation,
                                                    xOffset: cardState.position.x,
                                                    yOffset: cardState.position.y,
                                                    dynamicSize: dynamicSize
                                                )
                                                .zIndex(cardState.zIndex) // Apply the stored z-index
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(width: dynamicSize.tableWidth, height: dynamicSize.tableHeight)
                        .animation(.easeInOut, value: gameManager.showLastTrick)
                    }
                    
                    // Overlay Moving Cards
                    ForEach(gameManager.movingCards) { movingCard in
                        MovingCardView(movingCard: movingCard, dynamicSize: dynamicSize)
                            .environmentObject(gameManager)
                    }
                    
                    // MARK: - Slowpoke & AutoPilot
                    VStack {
                        Spacer()
                        HStack(alignment: .bottom, spacing: 16) {
                            #if DEBUG
                            InsetTableButton(
                                systemName: "hare.fill",
                                imageName: nil,
                                size: dynamicSize.dealerButtonSize,
                                isOn: gameManager.debugAutoPlayAllSteps,
                                accent: { .orange },
                                isEnabled: true
                            ) {
                                withAnimation(.easeInOut(duration: 0.1)) {
                                    gameManager.setDebugAutoPlayAllStepsEnabled(!gameManager.debugAutoPlayAllSteps)
                                }
                            }
                            #endif

                            if [.playingTricks, .grabTrick].contains(gameManager.gameState.currentPhase) {
                                InsetTableButton(
                                    systemName: "bolt.fill",
                                    imageName: nil,
                                    size: dynamicSize.dealerButtonSize,
                                    isOn: gameManager.autoPilot,
                                    accent: { .green },
                                    isEnabled: true
                                )
                                {
                                    withAnimation(.easeInOut(duration: 0.1)) {
                                        gameManager.autoPilot.toggle()
                                        if gameManager.autoPilot {
                                            if let localPlayer = gameManager.gameState.localPlayer {
                                                if localPlayer.announcedTricks.count > localPlayer.madeTricks.count {
                                                    gameManager.autoPilotShouldWinTricks = true
                                                }
                                            }
                                        }
                                    }
                                }
                            } else {
                                Circle()
                                    .frame(width: dynamicSize.dealerButtonSize, height: dynamicSize.dealerButtonSize)
                                    .opacity(0)
                            }
                            
                            if gameManager.isSlowPoke.values.contains(true) {
                                if !isHonkOnCooldown {
                                    InsetTableButton(
                                        systemName: nil,
                                        imageName: "horn",
                                        size: dynamicSize.dealerButtonSize,
                                        isOn: true,
                                        accent: { .yellow },
                                        isEnabled: true
                                    ) {
                                        gameManager.sendHonk()
                                        isHonkOnCooldown = true
                                        // Reset after a short delay to prevent spamming
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                            isHonkOnCooldown = false
                                        }
                                    }
                                } else {
                                    InsetTableButton(
                                        systemName: nil,
                                        imageName: "horn",
                                        size: dynamicSize.dealerButtonSize,
                                        isOn: false,
                                        accent: { .yellow },
                                        isEnabled: false
                                    ) {
                                    }
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.leading, 16)
                        .padding(.bottom, 16)
                    }
                    .zIndex(20_000)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onPreferenceChange(CardTransformPreferenceKey.self) { transforms in
                self.cardTransforms = transforms
                
                // For cards initialization
                for (cardID, cardState) in transforms {
                    // Update each card’s fromState
                    gameManager.cardStates[cardID] = cardState
                }
                
                let expectedDeckCardIds = Set((gameManager.gameState.deck + gameManager.gameState.trumpCards).map(\.id))
                let measuredCardIds = Set(gameManager.cardStates.keys)

                if gameManager.gameState.currentPhase == .renderingDeck {
                    let missingDeckCardIds = expectedDeckCardIds.subtracting(measuredCardIds)
                    logger.log(
                        "Deck measurement debug: phase=\(gameManager.gameState.currentPhase), didMeasureDeck=\(didMeasureDeck), expected=\(expectedDeckCardIds.count), measured=\(measuredCardIds.count), missing=\(missingDeckCardIds.count)"
                    )
                    if !missingDeckCardIds.isEmpty {
                        logger.log("Deck measurement missing ids: \(missingDeckCardIds.sorted().prefix(8).joined(separator: ", "))")
                    }
                }

                // If all deck cards are now measured, let the GameManager know we’re ready to deal.
                if !didMeasureDeck &&
                    gameManager.gameState.currentPhase == .renderingDeck &&
                    !expectedDeckCardIds.isEmpty &&
                    expectedDeckCardIds.isSubset(of: measuredCardIds) {
                    logger.log("Setting didMeasureDeck to true")
                    didMeasureDeck = true
                }
                gameManager.checkDeckMeasurementReadiness(reason: "card transform preference changed")
                
                // Iterate through moving cards to check if any placeholder positions are captured
                for movingCard in gameManager.movingCards {
                    if let toState = transforms[movingCard.placeholderCard.id] {
                        if movingCard.toState == nil {
                            // Update the movingCard's toState
                            movingCard.toState = toState
                        }
                    }
                }
            }
            .overlay(
                Group {
                    if showRoundHistory {
                        ZStack {
                            // Tappable background to dismiss the modal
                            Color.black.opacity(0.4)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    showRoundHistory = false
                                }
                            
                            // The modal view
                            RoundHistoryView(isPresented: $showRoundHistory)
                                .environmentObject(gameManager)
                        }
                        .transition(.opacity)
                    }
                }
            )
            // GeometryReader onAppear for background refresh
            .onAppear() {
                logger.log("onAppear: Refreshing background")
                refreshBackground()
            }
            .onChange(of: preferences.selectedFeltIndex) { _ in
                logger.log("Preferences changed: selectedFeltIndex updated, refreshing background")
                refreshBackground()
            }
            .onChange(of: gameManager.gameState.currentPhase) { phase in
                if phase == .renderingDeck {
                    logger.log("Deck measurement debug: entering renderingDeck; resetting didMeasureDeck")
                    didMeasureDeck = false
                    DispatchQueue.main.async {
                        gameManager.checkDeckMeasurementReadiness(reason: "entered renderingDeck from GameView")
                    }
                }
            }
            // End GeometryReader
            if gameManager.isRestoring {
                ZStack {
                    // Frosted backdrop
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .transition(.opacity)

                    // Centered progress card
                    VStack(spacing: 16) {
                        // Header
                        VStack(spacing: 6) {
                            Text("Restauration en cours…")
                                .font(.headline)
                            Text("Relecture des actions manquées")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        // Linear progress bar bound to restorationProgress
                        ProgressView(value: gameManager.restorationProgress, total: 1.0)
                            .progressViewStyle(.linear)
                            .frame(maxWidth: 420)
                            .padding(.horizontal, 4)
                            .accessibilityValue(Text("\(Int((gameManager.restorationProgress * 100).rounded())) pour cent"))

                        // Helper text
                        Text("Merci de patienter — ça peut prendre un ti boute.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.regularMaterial)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(radius: 20)
                    .padding()
                    .transition(.scale)
                    .animation(.easeInOut, value: gameManager.restorationProgress)
                }
            }
            // End ZStack
        } // end ZStack
        .animation(.easeInOut, value: gameManager.isRestoring)
    }
}


// MARK: Grid Overlay

struct GridOverlay: View {
    let spacing: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                
                for x in stride(from: 0, to: width, by: spacing) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }
                
                for y in stride(from: 0, to: height, by: spacing) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(Color.gray.opacity(0.3), lineWidth: 1) // Thin lines for every 50px
            
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                
                for x in stride(from: 0, to: width, by: spacing * 2) { // Every 100px
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }
                
                for y in stride(from: 0, to: height, by: spacing * 2) { // Every 100px
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(Color.gray.opacity(0.5), lineWidth: 2) // Thicker lines for every 100px
            
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                
                for x in stride(from: 0, to: width, by: spacing * 10) { // Every 500px
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))
                }
                
                for y in stride(from: 0, to: height, by: spacing * 10) { // Every 500px
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(Color.gray.opacity(0.8), lineWidth: 3) // Boldest lines for every 500px
        }
    }
}
