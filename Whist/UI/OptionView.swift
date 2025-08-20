//
//  OptionView.swift
//  Whist
//
//  Created by Tony Buffard on 2024-12-09.
//

import SwiftUI

struct NoShadowOnPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .shadow(radius: configuration.isPressed ? 0 : 5) // Remove shadow when pressed
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0) // Optional: Add a slight scale effect when pressed
            .animation(.easeInOut(duration: 0.05), value: configuration.isPressed) // Smooth transition
    }
}

// MARK: CircularButton

struct CircularButton: View {
    let text: String
    let action: () -> Void
    let size: CGFloat
    let backgroundColor: Color
    let isSelected: Bool // New parameter to indicate if the button is selected

    init(
        text: String,
        size: CGFloat = 60,
        backgroundColor: Color = .blue,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.size = size
        self.backgroundColor = backgroundColor
        self.isSelected = isSelected
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            ZStack {
                // Inner filled circle
                Circle()
                    .fill(isSelected ? backgroundColor.opacity(0.8) : backgroundColor.opacity(0.7))
                
                // Outer border to mimic poker chip
                Circle()
                    .strokeBorder(
                        isSelected ? backgroundColor.opacity(0.8) : backgroundColor.opacity(0.7), // Border color
                        lineWidth: isSelected ? 4 : 2 // Thicker border when selected
                    )
                    .foregroundColor(isSelected ? backgroundColor.opacity(0.8) : backgroundColor.opacity(0.7))

                // Add poker chip notches
                ForEach(0..<8) { i in
                    Rectangle()
                        .fill(.white) // Highlight notches when selected
                        .frame(width: size * 0.1, height: size * 0.1)
                        .offset(y: -size / 2 + size * 0.05) // Move to the edge of the circle
                        .rotationEffect(Angle(degrees: Double(i) * 45)) // Distribute evenly
                }

                Text(text)
                    .font(.system(size: size / 3).bold()) // Adjust font size
                    .foregroundColor(.white)
            }
            .frame(width: size, height: size)
            .shadow(color: isSelected ? .yellow : .black, radius: size / 15) // Add glowing shadow when selected
        }
        .buttonStyle(NoShadowOnPressButtonStyle())
    }
}

// MARK: OptionsView

struct OptionsView: View {
    var dynamicSize: DynamicSize
    @State private var selectedBet: Int? = nil // Tracks the currently selected bet
    @State private var backgroundColor: Color // Store the random color
    @EnvironmentObject var gameManager: GameManager
    @State private var randomNumber: Int? = nil // Current number during animation
    @State private var isAnimating = false // Tracks if the animation is running
    
    init(dynamicSize: DynamicSize) {
        _backgroundColor = State(initialValue: [
            .red, .orange, .yellow, .green, .mint, .teal,
            .cyan, .blue, .indigo, .purple, .pink, .brown, .gray
        ].randomElement() ?? .blue)
        self.dynamicSize = dynamicSize
    }
    
    var body: some View {
        VStack(spacing: dynamicSize.optionsVerticalSpacing) {
            // Calculate scores
            let scores = gameManager.gameState.players.map { $0.scores.last ?? 0 }.sorted(by: >)
            let playerScore = gameManager.gameState.localPlayer?.scores.last ?? 0
            let bestScore = scores.first ?? 0
            let secondBestScore = scores.dropFirst().first ?? 0
            
            // Check if the player is in random bet mode
            let maxBet = max(gameManager.gameState.round - 2, 1)
            
            if (playerScore >= 2 * secondBestScore &&
                playerScore != secondBestScore && // in case the 2 best players have 0
                gameManager.gameState.round > 3 &&
                playerScore == bestScore) { // In case of negative values
                // Display only the "?" chip
                CircularButton(
                    text: randomNumber != nil ? "\(randomNumber!)" : "?",
                    size: 60,
                    backgroundColor: backgroundColor,
                    isSelected: randomNumber != nil,
                    action: {
                        gameManager.playSound(named: "normal-click")
                        if randomNumber == nil {
                            handleRandomBetSelection()
                        }
                    }
                )
            } else {
                // Display the regular betting chips
                let numbers = Array(0...maxBet)
                let totalItems = numbers.count
                let minColumns = (totalItems < 7 && totalItems != 4) ? 3 : 4
                let columns = min(minColumns, totalItems)
                let rows = Int(ceil(Double(totalItems) / Double(columns))) // Calculate rows dynamically
                
                VStack(spacing: dynamicSize.optionsVerticalSpacing) {
                    ForEach(0..<rows, id: \.self) { rowIndex in
                        HStack(spacing: 20) {
                            ForEach(0..<columns, id: \.self) { columnIndex in
                                let numberIndex = rowIndex * columns + columnIndex
                                if numberIndex < totalItems {
                                    CircularButton(
                                        text: "\(numbers[numberIndex])",
                                        size: dynamicSize.optionsButtonSize,
                                        backgroundColor: backgroundColor,
                                        isSelected: selectedBet == numbers[numberIndex],
                                        action: {
                                            gameManager.playSound(named: "normal-click")
                                            handleBetSelection(numbers[numberIndex])
                                        }
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.white.opacity(0.2))
        .cornerRadius(15)
        .shadow(radius: 10)
        .onAppear {
            // Initialize selectedBet from GameManager when the view appears
            let roundIndex = max(gameManager.gameState.round - 1, 0)
            if let tricks = gameManager.gameState.localPlayer?.announcedTricks,
               tricks.indices.contains(roundIndex),
               gameManager.gameState.round > 3 {
                let currentBet = tricks[roundIndex]
                self.selectedBet = currentBet
                randomNumber = currentBet
            }
        }
        .onReceive(gameManager.objectWillChange) { _ in
            // Keep selectedBet in sync with GameManager’s stored bet
            let roundIndex = max(gameManager.gameState.round - 1, 0)
            if let tricks = gameManager.gameState.localPlayer?.announcedTricks,
               tricks.indices.contains(roundIndex),
               gameManager.gameState.round > 3 {
                let currentBet = tricks[roundIndex]
                self.selectedBet = currentBet
                randomNumber = currentBet 
            }
        }
    }
    
    private func handleBetSelection(_ bet: Int) {
        selectedBet = (selectedBet == bet) ? nil : bet
        gameManager.choseBet(bet: selectedBet)
        gameManager.checkAndAdvanceStateIfNeeded()
    }
    
    private func handleRandomBetSelection() {
        guard !isAnimating else { return } // Prevent double taps during animation
        guard randomNumber == nil else { return } // Prevent triggering again if already chosen

        // Start the random number animation
        isAnimating = true
        let maxBet = max(gameManager.gameState.round - 2, 1)
        let numbers = Array(0...maxBet)
        
        var elapsedTime: TimeInterval = 0
        Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { timer in
            randomNumber = numbers.randomElement()
            elapsedTime += 0.05
            
            if elapsedTime >= GameConstants.optionsRandomDuration {
                timer.invalidate()
                isAnimating = false
                
                // Select the final random bet
                if let finalBet = numbers.randomElement() {
                    randomNumber = finalBet
                    handleBetSelection(finalBet) // Lock the player's choice
                }
            }
        }
    }
}
