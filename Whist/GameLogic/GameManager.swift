//
//  GameManager.swift
//  Whist
//
//  Created by Tony Buffard on 2024-11-18.
//  Core controller managing the game flow and state.

import Foundation
import Combine
import CryptoKit
import SwiftUI
import CloudKit
import WebRTC
import FirebaseFirestore


enum PlayerId: String, Codable, CaseIterable {
    case dd = "dd"
    case gg = "gg"
    case toto = "toto"
    
    var displayName: String {
        switch self {
        case .dd: return "DD"
        case .gg: return "GG"
        case .toto: return "Toto"
        }
    }
}

@MainActor
class GameManager: ObservableObject {
    @Published var gameState: GameState = GameState()
    @Published var showOptions: Bool = false
    @Published var showTrumps: Bool = false
    @Published var showLastTrick: Bool = false
    @Published var movingCards: [MovingCard] = []
    @Published var hoveredSuit: Suit? = nil
    private var timerCancellable: AnyCancellable?
    var isDeckReady: Bool = false
    var isDeckReceived: Bool = false
    var pendingActions: [GameAction] = []
    var activeAnimations = 0
    var onBatchAnimationsCompleted: [(() -> Void)?] = []
    var animationQueue: [(Int, () -> Void)] = []
    // Dictionary to store each card's state
    @Published var cardStates: [String: CardState] = [:]
    @Published var isShuffling: Bool = false
    var shuffleCallback: ((_ deck: [Card], _ completion: @escaping () -> Void) -> Void)?
    // MARK: - WebRTC Signaling Dependencies
    let connectionManager: P2PConnectionManager
    let signalingManager: FirebaseSignalingManager
    var networkingStarted: Bool = false
    var connectionAttemptTimers: [PlayerId: Timer] = [:]
    var iceDisconnectionTimers: [PlayerId: Timer] = [:]
    let iceDisconnectionRecoveryTimeout: TimeInterval = 10.0
    #if DEBUG
    let offerWaitTimeout: TimeInterval = 5.0 // Time to wait for an offer if I'm an answerer
    let answerWaitTimeout: TimeInterval = 5.0 // Time to wait for an answer if I'm an offerer
    let iceExchangeTimeout: TimeInterval = 5.0 // Time to complete ICE and connect after SDPs
    #else
    let offerWaitTimeout: TimeInterval = 20.0 // Time to wait for an offer if I'm an answerer
    let answerWaitTimeout: TimeInterval = 20.0 // Time to wait for an answer if I'm an offerer
    let iceExchangeTimeout: TimeInterval = 25.0 // Time to complete ICE and connect after SDPs
    #endif
    var lastAppliedSequence: Int = 0
    var buffered: [Int: GameAction] = [:]
    var catchUpWorkItem: DispatchWorkItem?
    var canCatchUp: Bool = false
    @Published var isRestoring = false
    @Published var restorationProgress: Double = 0.0
    
    let preferences: Preferences
    let soundManager = SoundManager()
    static let SM = ScoresManager.shared
    var persistence: GamePersistence = GamePersistence()
    
    var cancellables = Set<AnyCancellable>()
    var isGameSetup: Bool = false
    var isAwaitingActionCompletionDuringRestore: Bool = false
    @Published var autoPilot: Bool = false
    
    var lastGameWinner: PlayerId?
    var showConfetti: Bool = false
    @Published var showWindSwirl: Bool = false
    @Published var showFailureEffect: Bool = false
    @Published var cameraShakeOffset: CGSize = .zero
    @Published var showImpactEffect: Bool = false
    @Published var showSubtleFailureEffect: Bool = false
    @Published var effectPosition: CGPoint = .zero
    
    @Published var dealerPosition: CGPoint = .zero
    @Published var playersScoresUpdated: Bool = false
    var isFirstGame: Bool = true
    
    // MARK: - Slowpoke Timer Properties
    var slowpokeTimer: DispatchSourceTimer?
    #if DEBUG
    let slowpokeDelay: TimeInterval = 5 // Delay in seconds before sending slowpoke
    #else
    let slowpokeDelay: TimeInterval = 20 // Delay in seconds before sending slowpoke
    #endif
    var amSlowPoke: Bool = false
    @Published var isSlowPoke: [PlayerId: Bool] = [:]
    @Published var amHonked: Bool = false
    
    /// Dependency‐injecting initializer
    init(connectionManager: P2PConnectionManager,
         signalingManager: FirebaseSignalingManager,
         preferences: Preferences) {
        self.connectionManager = connectionManager
        self.signalingManager = signalingManager
        self.preferences = preferences
    }
    
    // MARK: - Game State Initialization
    
    func setupGame(completion: @escaping () -> Void = {}) {
        logger.log("--> SetupGame()")
        let totalPlayers = gameState.players.count
        let connectedPlayers = gameState.players.filter { $0.firebasePresenceOnline }.count
        logger.log("Total players created: \(totalPlayers), Players connected: \(connectedPlayers)")

        guard !isGameSetup else {
            logger.log("Game is already set up.")
            completion()
            return
        }

        gameState.dealer = gameState.playOrder.first
        logger.log("Dealer is \(String(describing: gameState.dealer))")

        Task.detached { [self] in
            if let loser = await GameManager.SM.findLoser() {
                await MainActor.run {
                    let loserPlayer = self.gameState.getPlayer(by: loser.playerId)
                    loserPlayer.monthlyLosses = loser.losingMonths
                    logger.log("Updated \(loser.playerId)'s monthlyLosses to \(loser.losingMonths)")
                }
            } else {
                await MainActor.run {
                    logger.log("No loser identified or loser had 0 losing months.")
                }
            }

            await MainActor.run {
                self.gameState.updatePlayerReferences()

                if let localPlayer = self.gameState.localPlayer,
                   let leftPlayer = self.gameState.leftPlayer,
                   let rightPlayer = self.gameState.rightPlayer {
                    logger.log("Main Player: \(localPlayer.username), Left Player: \(leftPlayer.username), Right Player: \(rightPlayer.username)")
                } else {
                    logger.fatalErrorAndLog("Players could not be assigned correctly.")
                }

                self.isGameSetup = true
                self.initializeCards()
                self.objectWillChange.send()
                completion()
            }
        }
    }
    
    func setAndSendPlayOrder() { // Only if local player is toto
        if gameState.playOrder == [] { // first game of the session
            gameState.playOrder = [.gg, .dd, .toto].shuffled()
        }
        logger.log("Sending playOrder to other players!")
        sendPlayOrderToPlayers(gameState.playOrder)
        checkAndAdvanceStateIfNeeded()
    }
    
    // MARK: startNewGame
    func startNewGameAction() {
//        Task {
//            await persistence.clearGameActions()
//        }
        if !isFirstGame {
            persistOrderAndDealer()
        }
        sendStartNewGameAction()
        startNewGame()
    }
    
    // MARK: - Game Logic Functions
    
    func newGame() {
        gameState.round = 0
        gameState.players.forEach {
            $0.scores.removeAll()
            $0.announcedTricks.removeAll()
            $0.madeTricks.removeAll()
            $0.place = 0
            $0.hand.removeAll()
            $0.trickCards.removeAll()
            $0.state = .idle
            $0.onlyWins = true
            $0.onlyWinsBonus = false
        }
        
        // Move to the next dealer in playOrder so that another player starts the game
        guard let dealer = gameState.dealer,
              let currentIndex = gameState.playOrder.firstIndex(of: dealer) else {
            logger.fatalErrorAndLog("Error: Dealer is not set or not found in play order.")
        }
        let nextIndex = (currentIndex + 1) % gameState.playOrder.count
        gameState.dealer = gameState.playOrder[nextIndex]
        logger.log("Dealer is now \(gameState.dealer!.rawValue).")
    }
    
    func newGameRound() {
        var roundString: String
        if let message = gameState.localPlayer?.id.rawValue.uppercased() {
            if gameState.round < 3 {
                roundString = "\(gameState.round + 1)/3"
            } else {
                roundString = "\(gameState.round-1)"
            }
            let message2 = message + " / round \(roundString)"
            let padding = 3 // Padding around the message inside the box
            let lineLength = message2.count + padding * 2
            let borderLine = String(repeating: "*", count: lineLength)
            let formattedMessage = "** \(message2) **"
            
            logger.log(borderLine)
            logger.log(formattedMessage)
            logger.log(borderLine)
        }
        
        gameState.round += 1
        gameState.trumpSuit = nil
        gameState.tricksGrabbed = Array(repeating: false, count: max(gameState.round - 2, 1))
        gameState.currentTrick = 0
        gameState.lastTrick.removeAll()
        gameState.lastTrickCardStates.removeAll()
        gameState.players.forEach {
            $0.hasDiscarded = false
        }
        amSlowPoke = false
        isSlowPoke = [:]
        autoPilot = false // Resets the autoPilot
        
#if DEBUG
        if gameState.localPlayer?.id != .toto {
            autoPilot = true
        }
#endif
        
        // Move to the next dealer in playOrder
        guard let dealer = gameState.dealer,
              let currentIndex = gameState.playOrder.firstIndex(of: dealer) else {
            logger.fatalErrorAndLog("Error: Dealer is not set or not found in play order.")
        }
        let nextIndex = (currentIndex + 1) % gameState.playOrder.count
        gameState.dealer = gameState.playOrder[nextIndex]
        logger.log("Dealer is now \(gameState.dealer!.rawValue).")
        
        // Set the first player to play
        updatePlayerPlayOrder(startingWith: .dealer(gameState.dealer!))
        
        // Update the players' positions
        if gameState.round > 1 {
            updatePlayersPositions()
        }
    }
    
    func updateDealerFrame(playerId: PlayerId, frame: CGRect) {
        dealerPosition = CGPoint(x: frame.midX, y: frame.midY)
    }
    
    func updatePlayerPlayOrder(startingWith condition: StartingCondition) {
        /// Usage:
        /// updatePlayerPlayOrder(startingWith: .winner(.gg))
        /// updatePlayerPlayOrder(startingWith: .dealer(.dd))
        
        let startingPlayerId: PlayerId?
        
        switch condition {
        case .winner(let winnerId):
            startingPlayerId = winnerId
        case .dealer(let dealerId):
            if let dealerIndex = gameState.playOrder.firstIndex(of: dealerId) {
                let nextIndex = (dealerIndex + 1) % gameState.playOrder.count
                startingPlayerId = gameState.playOrder[nextIndex]
            } else {
                startingPlayerId = nil
            }
        }
        
        guard let startingPlayerId = startingPlayerId,
              let startingIndex = gameState.playOrder.firstIndex(of: startingPlayerId) else {
            logger.fatalErrorAndLog("Error: Starting player not found.")
        }
        
        let reorderedPlayOrder = gameState.playOrder[startingIndex...] + gameState.playOrder[..<startingIndex]
        gameState.playOrder = Array(reorderedPlayOrder)
        logger.log("New players order: \(gameState.playOrder)")
    }
    
    // Enum for distinguishing conditions
    enum StartingCondition {
        case winner(PlayerId)
        case dealer(PlayerId)
    }
    
    // MARK: - Game Utility Functions
    
    func updatePlayersPositions() {
        gameState.players.forEach { player in
            player.place = determinePosition(for: player.id)
        }
    }
    
    private func determinePosition(for playerId: PlayerId) -> Int {
        /// returns 1 if the player has the highest score, even if there's a tie
        /// returns 2 for the second player
        /// returns 3 for the last player
        
        // TODO: check that this function works as intended
        let player = gameState.getPlayer(by: playerId)
        let currentRound = gameState.round
        let currentScores = gameState.players.map { $0.scores.last ?? 0 }
        let highestScore = currentScores.max() ?? 0
        let lowestScore = currentScores.min() ?? 0
        if currentRound < 12 {
        
            // Step 1: Player has the highest score
            if player.scores.last == highestScore {
                return 1
            }
            
            // Step 2: Player has the lowest score
            if player.scores.last == lowestScore {
                let sortedByScore = gameState.players.sorted {
                    ($0.scores.last ?? 0) < ($1.scores.last ?? 0)
                }
                
                let playersWithLowestScore = sortedByScore.filter {
                    $0.scores.last == lowestScore
                }
                
                if playersWithLowestScore.count > 1 {
                    // Break tie based on historical scores
                    let otherPlayer = playersWithLowestScore.first { $0.username != player.username }
                    
                    for round in stride(from: currentRound - 1, through: 0, by: -1) {
                        let playerScore = player.scores[safe: round] ?? Int.min
                        let otherPlayerScore = otherPlayer?.scores[safe: round] ?? Int.min
                        
                        if playerScore != otherPlayerScore {
                            if playerScore < otherPlayerScore {
                                return 3
                            } else {
                                return 2
                            }
                        }
                    }
                    
                    // Fallback to dealer-based play order
                    if let dealer = gameState.dealer,
                       let dealerIndex = gameState.playOrder.firstIndex(of: dealer),
                       let usernameIndex = gameState.playOrder.firstIndex(of: playerId) {
                        // Calculate the index of the player to the left of the dealer
                        let leftOfDealerIndex = (dealerIndex + 1) % gameState.playOrder.count
                        
                        // If the current player is the dealer
                        if usernameIndex == dealerIndex {
                            return 3 // Dealer gets rank 3
                        }
                        
                        // If the other player is the dealer
                        if otherPlayer?.id == gameState.dealer {
                            return 2
                        }
                        
                        // If the current player is the first player to the left of the dealer
                        if usernameIndex == leftOfDealerIndex {
                            return 3 // Real last place
                        } else {
                            return 2
                        }
                    }
                } else {
                    return 3
                }
            }
            
            // Step 3: Player is neither the highest nor the lowest
            return 2
        } else {
            // Final round: enforce unique ranks using score and tie-breakers
            let sortedPlayers = gameState.players.sorted { lhs, rhs in
                let lhsScore = lhs.scores.last ?? 0
                let rhsScore = rhs.scores.last ?? 0
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }

                // Tie-break with historical rounds
                for round in stride(from: currentRound - 2, through: 0, by: -1) {
                    let lhsPast = lhs.scores[safe: round] ?? Int.min
                    let rhsPast = rhs.scores[safe: round] ?? Int.min
                    if lhsPast != rhsPast {
                        return lhsPast > rhsPast
                    }
                }

                // Tie-break with play order
                guard let lhsIndex = gameState.playOrder.firstIndex(of: lhs.id),
                      let rhsIndex = gameState.playOrder.firstIndex(of: rhs.id) else {
                    return false
                }
                return lhsIndex < rhsIndex
            }

            if let index = sortedPlayers.firstIndex(where: { $0.id == playerId }) {
                return index + 1
            } else {
                return 3 // fallback
            }
        }
    }
    
    func allScoresEqual() -> Bool {
        guard let firstScore = gameState.players.first?.scores.last else {
            return true
        }
        return gameState.players.allSatisfy { $0.scores.last == firstScore }
    }
    
    func updateGameStateWithBet(from playerId: PlayerId, with bet: Int) {
        let player = gameState.getPlayer(by: playerId)

        if bet == -1 {
            // Player cancelled his bet
            if player.announcedTricks.count == gameState.round {
                player.announcedTricks.removeLast()
                player.madeTricks.removeLast()
                logger.log("Player \(playerId) cancelled their bet.")
            } else {
                logger.log("Player \(playerId) tried to cancel a bet, but none was found for this round.")
            }
            self.objectWillChange.send()
            return
        }
        
        // Check if bet legal
        if !(bet > -1 && bet <= max(gameState.round - 2, 1)) {
            logger.fatalErrorAndLog("Received a illegal bet from \(playerId) with \(bet) at round \(gameState.round).")
        }

        // Set the player's bet
        if player.announcedTricks.count < gameState.round {
            player.announcedTricks.append(bet)
            player.madeTricks.append(0)
        } else {
            player.announcedTricks[gameState.round - 1] = bet
        }
        logger.log("Player \(playerId) announced tricks: \(player.announcedTricks)")

        // if all players have bet and I'm placed 1, show the trump card if there's no 3-tie OR if local player score >= 2 * second player score
        let shouldRevealTrump = (
            allPlayersBet() &&
            gameState.round > 3 &&
            gameState.playerPlaced(1)?.scores.last != gameState.playerPlaced(3)?.scores.last
        ) || ({ // Use a closure to safely unwrap and compare scores
            guard let localScore = gameState.localPlayer?.scores.last, // Safely get local player's last score
                  let secondPlacePlayer = gameState.playerPlaced(2),   // Safely get player in 2nd place
                  let secondScore = secondPlacePlayer.scores.last else { // Safely get 2nd place player's last score
                return false // If any value is nil, this condition is false
            }
            // Now perform the comparison with unwrapped values
            return localScore >= 2 * secondScore
        })() // Immediately execute the closure

        if shouldRevealTrump {
            gameState.trumpCards.last?.isFaceDown = false
        }

        self.objectWillChange.send() // To force a refresh for the last player
        checkAndAdvanceStateIfNeeded() // To fix the trump card visibility for the 2nd player in the first 3 rounds
    }
    
    func updateGameStateWithTrump(from playerId: PlayerId, with card: Card) {
        logger.debug("Trump card chosen: \(card)")
        // if restoring and local player chose trump
        if gameState.localPlayer?.id == playerId && isRestoring {
            selectTrumpSuit(card) {
                // hack
                card.isFaceDown = false
                self.checkAndAdvanceStateIfNeeded()
            }
        }
        
        // move the card on top of the trump deck
        guard let index = gameState.trumpCards.firstIndex(of: card) else {
            logger.log("Card \(card) not found in trumpCards.")
            return
        }
        
        let removedCard = gameState.trumpCards.remove(at: index)
        
        // Put the card face up if second player
        if gameState.localPlayer?.place == 2 {
            removedCard.isFaceDown = false
        }
        
        gameState.trumpCards.append(removedCard)
        
        // Set the trump suit
        gameState.trumpSuit = card.suit
        
        self.objectWillChange.send() // To force a refresh for the 2nd player
    }
    
    func updateGameStateWithTrumpCancellation() {
        // Reset trump-related state to cancel the trump choice
        gameState.trumpSuit = nil
        gameState.trumpCards.last?.isFaceDown = true
        showOptions = false
        
        logger.log("Trump choice cancelled by second player.")
        
        transition(to: .choosingTrump)
    }
    
    func updateGameStateWithDiscardedCards(from playerId: PlayerId, with cards: [Card], completion: @escaping () -> Void) {
        // Validate the player
        let player = gameState.getPlayer(by: playerId)
        
        // Ensure the cards are part of the player's hand
        for card in cards {
            guard player.hand.firstIndex(of: card) != nil else {
                logger.log("Error: Card \(card) is not in \(playerId)'s hand.")
                return
            }
            
            player.hasDiscarded = true
            
            var origin: CardPlace = player.tablePosition == .left ? .leftPlayer: .rightPlayer
            switch player.tablePosition {
            case .left:
                origin = .leftPlayer
                
            case .right:
                origin = .rightPlayer
                
            case .local:
                origin = .localPlayer
            
            default:
                logger.fatalErrorAndLog("Player \(player) has not table position!")
            }
            var destination: CardPlace = .deck
            var message: String = "Player \(player) discarded \(card)"
            
            if player.place == 2 && gameState.round == 12 {
                if Double(gameState.lastPlayer?.scores[safe: gameState.round - 2] ?? 0) <= 0.5 * Double(player.scores[safe: gameState.round - 2] ?? 0) || gameState.lastPlayer?.monthlyLosses ?? 0 > 0 {
                    switch gameState.lastPlayer?.tablePosition {
                    case .left:
                        destination = .leftPlayer
                        
                    case .right:
                        destination = .rightPlayer
                        
                    case .local:
                        cards.forEach { $0.isFaceDown = false } // show the card if I'm the last player
                        destination = .localPlayer
                        
                    default:
                        destination = .table // Should crash but shouldn't happen
                    }
                    message = "Player \(playerId) gave \(card) to the last, \(destination) player"
                }
            }
            logger.log(message)
            beginBatchMove(totalCards: 1) {
                if destination == .localPlayer {
                    self.sortLocalPlayerHand()
                }
                completion() }
            moveCard(card, from: origin, to: destination)
        }
    }
    
    func updatePlayerWithState(from playerId: PlayerId, with state: PlayerState) {
        let player = gameState.getPlayer(by: playerId)
        player.state = state
        isSlowPoke[playerId] = false
        logger.log("\(playerId) updated their state to \(state).")
    }
    
    func updateGameStateWithDealer(from playerId: PlayerId, with dealer: PlayerId) {
        logger.log("Updating dealer with \(dealer.rawValue)")
        gameState.dealer = dealer
    }
    
    func showSlowPokeButton(for playerId: PlayerId) {
        isSlowPoke[playerId] = true
    }
    
    func honk() {
        if amSlowPoke {
            amHonked = true
        }
        playSound(named: "pouet")
    }
    
    // MARK: Choose bet
    func choseBet(bet: Int?) {
        // Ensure the local player is defined
        guard let localPlayer = gameState.localPlayer else {
            logger.fatalErrorAndLog("Error: Local player is not defined.")
        }
        
        if gameState.round < 4 {
            showOptions = false
            logger.log("the optionsView should disappear now.")
        }
        
        if localPlayer.announcedTricks.count == gameState.round {
            if bet != nil {
                // player updates his current bet
                localPlayer.announcedTricks[localPlayer.announcedTricks.count-1] = bet!
            } else {
                // Player deselected his bet
                if localPlayer.announcedTricks.count == gameState.round {
                    localPlayer.announcedTricks.removeLast()
                    localPlayer.madeTricks.removeLast()
                }
            }
        } else {
            guard bet != nil else { return } // in case it was cancelled and the game was restored
            // first bet for this round
            localPlayer.announcedTricks.append(bet!)
            localPlayer.madeTricks.append(0)
        }
        
        // Notify other players about the action
        sendBetToPlayers(bet ?? -1)
    }
    
    // MARK: Cancel Trump Choice
    
    func cancelTrumpChoice() {
        // Reset trump-related state to cancel the trump choice
        gameState.trumpSuit = nil
        gameState.trumpCards.last?.isFaceDown = true
        
        logger.log("Trump choice cancelled by local player.")
        
        // Notify other players about the cancellation
        sendCancelTrumpChoice()
        
        // Advance the game state as needed
        checkAndAdvanceStateIfNeeded()
    }
    
    // MARK: Save scores
    func saveScore() {
        // Update the game's winner
        lastGameWinner = gameState.players.first { $0.place == 1 }?.id
        
        // Save the score only once
        if gameState.localPlayer?.id == .toto {
            // Retrieve players by their ID using the gameState helper.
            let ggPlayer = gameState.getPlayer(by: .gg)
            let ddPlayer = gameState.getPlayer(by: .dd)
            let totoPlayer = gameState.getPlayer(by: .toto)
            
            // Get the latest score for each player (defaulting to 0 if not available).
            let ggScore = ggPlayer.scores.last ?? 0
            let ddScore = ddPlayer.scores.last ?? 0
            let totoScore = totoPlayer.scores.last ?? 0
            
            // Create a new GameScore instance with current date, scores, and positions.
            let newScore = GameScore(
                date: Date(),
                ggScore: ggScore,
                ddScore: ddScore,
                totoScore: totoScore,
                ggPosition: ggPlayer.place,
                ddPosition: ddPlayer.place,
                totoPosition: totoPlayer.place,
                ggConsecutiveWins: consecutiveWins(by: .gg),
                ddConsecutiveWins: consecutiveWins(by: .dd),
                totoConsecutiveWins: consecutiveWins(by: .toto)
            )
            
            // Save the updated scores array.
            Task {
                do {
                    try await ScoresManager.shared.saveScore(newScore)
                    // Log success on the main thread if necessary, though logger should handle it
                    await MainActor.run { // Ensure logging happens on main thread if it interacts with UI state implicitly
                         logger.log("Score saved successfully for game ending \(newScore.date)")
                    }
                } catch {
                     // Handle the error (e.g., display an alert to the user).
                    await MainActor.run {
                         logger.log("Failed to save score: \(error.localizedDescription)")
                         logger.log("Score data that failed to save: \(newScore)")
                    }
                }
            }
        }
    }
    
    func consecutiveWins(by playerId: PlayerId) -> Int {
        let player = gameState.getPlayer(by: playerId)
        var count = 0
        
        for round in 0..<player.announcedTricks.count {
            if player.announcedTricks[round] == player.madeTricks[round] {
                count += 1
            } else {
                break // Stop counting if a round was lost
            }
        }
        
        return count
    }
    
    func displayPlayers() {
        logger.log("🔍 Displaying peer players:")
        
        for player in gameState.players {
            if player.id == gameState.localPlayer?.id {
                continue
            }
            let username = player.username
            let playerId = player.id.rawValue
            let tablePosition = player.tablePosition?.rawValue ?? "unknown"
            let isPresent = player.firebasePresenceOnline
            let isConnected = player.isP2PConnected
            
            logger.log("\(isPresent ? "✅": "❌") Player: \(username), PlayerId: \(playerId), TablePosition: \(tablePosition), Present: \(isPresent), isP2PConnected: \(isConnected ? "✅": "❌")")
        }
    }
    
    // MARK: Save/Load Game Actions
    
    func saveGameAction(_ action: GameAction) {
        Task {
            await persistence.saveGameAction(action)
        }
    }
    
    func clearSavedGameAtions() {
        Task {
            await persistence.clearGameActions()
        }
    }
    
    // MARK: Restore saved actions
    
    /// Logs additional payload details for selected action types
    private func actionPayloadString(_ action: GameAction) -> String {
        switch action.type {
        case .playCard:
            guard let card = try? JSONDecoder().decode(Card.self, from: action.payload) else {
                return "nil"
            }
            return "\(card)"
        case .choseBet:
            if let bet = try? JSONDecoder().decode(Int.self, from: action.payload) {
                return "\(bet)"
            } else {
                return "nil"
            }
        case .choseTrump:
            if let trumpCard = try? JSONDecoder().decode(Card.self, from: action.payload) {
                return "\(trumpCard)"
            } else {
                return "nil"
            }
        case .discard:
            if let discardedCards = try? JSONDecoder().decode([Card].self, from: action.payload) {
                let list = discardedCards.map { "\($0)" }.joined(separator: ", ")
                return "[\(list)]"
            } else {
                return "[]"
            }
        default:
            return ""
        }
    }

    /// Restores the game state by loading and replaying all saved GameAction events.
    func restoreGameFromActions() async -> Bool {
        var round = 0
        logger.log("Restoring game from saved actions...")
        // Load saved actions
        guard let actions = await persistence.loadGameActions(),
              actions.contains(where: { $0.type == .startNewGame }) else {
            logger.log("No fresh game actions (startNewGame) found. Starting new game...")
            return false
        }
        // Sort all actions by sequence (ascending)
        let sortedActions = actions.sorted { $0.sequence < $1.sequence }

        // Pick the latest playOrder and dealer actions to establish authoritative state first
        let latestPlayOrder = sortedActions.last { $0.type == .playOrder }
        let latestDealer = sortedActions.last { $0.type == .dealer }

        // Priority actions to run first (order between them doesn't matter)
        var priorityActions: [GameAction] = []
        if let po = latestPlayOrder { priorityActions.append(po) }
        if let dl = latestDealer { priorityActions.append(dl) }

        // Remaining actions exclude all dealer/playOrder (we've established the final ones above)
        let remaining = sortedActions.filter { $0.type != .dealer && $0.type != .playOrder }

        // From the remaining actions, remove all sendState except the latest per player
        var latestSendStateByPlayer: [PlayerId: GameAction] = [:]
        for action in remaining where action.type == .sendState {
            latestSendStateByPlayer[action.playerId] = action
        }
        let tailActions: [GameAction] = remaining.filter { action in
            action.type != .sendState || latestSendStateByPlayer[action.playerId]?.sequence == action.sequence
        }

        // Final ordered list: priority actions first, then the rest in sequence order
        let filteredActions: [GameAction] = priorityActions + tailActions

        // For logging (round counting is only for sendDeck in the tail and remains accurate)
        var actionsProcessed: Int = 0
        let totalActions = filteredActions.count
        for action in filteredActions {
            if action.type == .sendDeck {
                round += 1
                if round < 4 {
                    logger.log("[\(String(format: "%04d", action.sequence))] \(action.playerId.rawValue) - \(action.type) - ROUND \(round)/3")
                } else {
                    logger.log("[\(String(format: "%04d", action.sequence))] \(action.playerId.rawValue) - \(action.type) - ROUND \(round-2)")
                }
            } else {
                logger.log("[\(String(format: "%04d", action.sequence))] \(action.playerId.rawValue) - \(action.type)(\(actionPayloadString(action)))")
            }
        }
        logger.log("Filtered to \(filteredActions.count) actions after prioritizing playOrder/dealer and pruning redundant sendState actions.")

        // Replay each action through your existing handler
        isRestoring = true
        logger.debug("😀😀😀 isRestoring is true!!!")
        gameState.currentPhase = .setPlayOrder
        for action in filteredActions {
            while isAwaitingActionCompletionDuringRestore { // ensure sequential apply during restore
                try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms
            }
            handleActionImmediately(action)
            actionsProcessed += 1
            restorationProgress = Double(actionsProcessed) / Double(totalActions)
        }
        restorationProgress = 1.0
        // hack
        if gameState.currentPhase == .playingTricks {
            for card in gameState.table {
                card.isFaceDown = false
            }
        }
        isRestoring = false
        logger.debug("😀😀😀 isRestoring is false.")

        self.objectWillChange.send()
        checkAndAdvanceStateIfNeeded()

        logger.log("Game successfully restored via saved actions.")
        return true
    }
    
    private func handleActionImmediately(_ action: GameAction) {
        logger.log("🏓 Handling (immediate) action \(action.type) from \(action.playerId)")
        if self.isRestoring || self.isActionValidInCurrentPhase(action.type) {
            self.processAction(action)
            if action.type != .sendState {
                self.checkAndAdvanceStateIfNeeded()
            }
        } else {
            self.pendingActions.append(action)
            logger.log("Stored action \(action.type) from \(action.playerId) for later because currentPhase = \(self.gameState.currentPhase)")
        }
    }
}
