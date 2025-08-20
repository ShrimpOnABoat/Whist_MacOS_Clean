//
//  GM+StateMachine.swift
//  Whist
//
//  Created by Tony Buffard on 2024-12-09.
//

import SwiftUI

enum GamePhase: Encodable, Decodable {
    case waitingForPlayers      // Before the game starts, waiting for all players to connect
    case resumeSavedGame        // In case a game was saved, resume
    case setPlayOrder         // Ensuring seed is distributed before setup
    case setupGame              // Setup the game for the evening!
    case waitingToStart         // Display a "New game" button and the last game's winner
    case newGame                // Setup a new game
    case setupNewRound          // setup the new round
    case waitingForDeck         // Waiting for the dealer to shuffle the deck
    case renderingDeck          // Make sure the cards' cardState are initialized before dealing
    case dealingCards           // Dealing cards to players
    case choosingTrump          // Local player choose a trump suit
    case waitingForTrump        // Waiting for a player to pick trump
    case bidding                // Players bid how many tricks they will take. Stays on screen while the others still decide so that the player can change his mind.
    case discard                // Discard one or two cards
    case showCard               // Show card face up in first 3 rounds
    case playingTricks          // Active trick-playing phase
    case grabTrick              // One player takes the trick
    case scoring                // Calculating scores for the round
    case gameOver               // Game has ended
    
    var isPlayingPhase: Bool {
        switch self {
        case .showCard, .playingTricks, .grabTrick:
            return true
        default:
            return false
        }
    }

    var isBeforePlayingPhase: Bool {
        switch self {
        case .dealingCards, .choosingTrump, .waitingForTrump, .bidding, .discard:
            return true
        default:
            return false
        }
    }
}

extension GameManager {
    
    //     MARK: Transition
    
    func transition(to newPhase: GamePhase) {
        logger.log("🔁 Forcing transition to \(newPhase) from \(gameState.currentPhase)")
        let multiplePhases: Set<GamePhase> = [.bidding, .playingTricks]
        if gameState.currentPhase == newPhase && !multiplePhases.contains(newPhase) {
            logger.debug("No transition needed")
            return
        }
        if gameState.currentPhase == .setupGame && newPhase == .waitingToStart && !isRestoring {
            DispatchQueue.main.async {
                self.objectWillChange.send()
                logger.log("Transitionning to waitingToStart with UI refresh")
            }
        }
        logger.log("Transitioning from \(gameState.currentPhase) to \(newPhase)")
        gameState.currentPhase = newPhase
        handleStateTransition()
    }
    
    // MARK: setPlayerState
    
    func setPlayerState(to newState: PlayerState) {
        // Cancel any existing slowpoke timer whenever the player state changes
        cancelSlowpokeTimer()
        if gameState.localPlayer?.state != newState {
            gameState.localPlayer?.state = newState
            // If entering a state where the player must act, start the slowpoke timer
            switch newState {
            case .choosingTrump, .bidding, .discarding, .playing:
                startSlowpokeTimer()
            default:
                break
            }
            logger.log("My state is now \(newState)")
            sendStateToPlayers()
//            saveGameState(gameState)
        }
    }
    
    // MARK: handleStateTransition
    
    private func handleStateTransition() {
        if processPendingActionsForCurrentPhase() { return }
        
        guard let localPlayer: Player = gameState.localPlayer else { return }
        
        switch gameState.currentPhase {
        case .waitingForPlayers:
            setPlayerState(to: .idle)
            
        case .resumeSavedGame:
            Task {
//                let isSavedGame = await checkAndRestoreSavedGame()
                let isSavedGame = await restoreGameFromActions()
                if !isSavedGame {
                    transition(to: .setPlayOrder)
                }
            }
            
        case .setPlayOrder:
            if localPlayer.id == .toto {
                setAndSendPlayOrder()
            } else {
                logger.log("Waiting for seed from Toto...")
            }
            
        case .setupGame:
            setPlayerState(to: .idle)
            isAwaitingActionCompletionDuringRestore = true
            let setupGameId = Int.random(in: 0...1000)
            logger.debug("setupGameId set to \(setupGameId)")
            setupGame {
                self.transition(to: .waitingToStart)
                logger.debug("setupGame finished with Id \(setupGameId)")
                self.isAwaitingActionCompletionDuringRestore = false
            }
            
        case .waitingToStart:
            setPlayerState(to: .startNewGame)
            
        case .newGame:
            setPlayerState(to: .idle)
            newGame()
            transition(to: .setupNewRound)
            
        case .setupNewRound:
            setPlayerState(to: .idle)
            newGameRound()
            if localPlayer.id == gameState.dealer && !isRestoring {
                if !isDeckReady {
                    logger.log("isDeckReady: \(isDeckReady)")
                    transition(to: .renderingDeck)
                } else {
                    transition(to: .dealingCards)
                }
            } else {
                transition(to: .waitingForDeck)
            }
            
        case .renderingDeck:
            setPlayerState(to: .idle)
            // Mark that the deck is NOT measured yet
            //            isDeckReady = false
            
        case .waitingForDeck:
            setPlayerState(to: .idle)
            // remove cards from tricks, hands and table and bring them back to the deck
            waitForAnimationsToFinish {
                self.gatherCards() {
                    // in case the deck was sent earlier
                    //                    self.processPendingActionsForCurrentPhase()
                    
                    // otherwise nothing to do but wait
                    if !self.isDeckReady { logger.log("Waiting for deck") }
                }
            }
            
        case .dealingCards:
            isAwaitingActionCompletionDuringRestore = true
            setPlayerState(to: .idle)
            hoveredSuit = nil
            let isDealer = isRestoring ? false : (localPlayer.id == gameState.dealer)
            
            // 1) Define a function/closure that contains everything you do *after* dealCards finishes.
            func afterDealing() {
                // After dealing, decide what’s next:
                if gameState.round < 4 {
                    isAwaitingActionCompletionDuringRestore = false
                    transition(to: .bidding)
                } else {
                    if let localPlayer = gameState.localPlayer {
                        logger.log("My place is \(localPlayer.place)")
                        switch localPlayer.place {
                        case 1:
                            isAwaitingActionCompletionDuringRestore = false
                            transition(to: .bidding)
                        case 2:
                            isAwaitingActionCompletionDuringRestore = false
                            transition(to: .waitingForTrump)
                        case 3:
                            isAwaitingActionCompletionDuringRestore = false
                            transition(to: .choosingTrump)
                        default:
                            isAwaitingActionCompletionDuringRestore = false
                            logger.fatalErrorAndLog("Unknown place \(localPlayer.place)")
                        }
                    }
                }
            }
            
            // 2) Now branch out whether we do gatherCards + shuffle or not:
            waitForAnimationsToFinish {
                if isDealer && !self.isRestoring {
                    self.gatherCards {
                        self.shuffleCards() {
//                            self.saveGameState(self.gameState)
                            self.sendDeckToPlayers()
                            
                            // 3) Call dealCards, then call our afterDealing function
                            self.waitForAnimationsToFinish {
                                self.dealCards {
                                    afterDealing()
                                }
                            }
                        }
                    }
                } else {
                    // 4) Same dealCards call, same completion logic
                    self.shuffleCards(animationOnly: true) {
                        self.waitForAnimationsToFinish {
                            self.dealCards {
                                afterDealing()
                            }
                        }
                    }
                }
            }
            
        case .choosingTrump:
            setPlayerState(to: .choosingTrump)
            
            waitForAnimationsToFinish {
                self.chooseTrump() {
                    self.hoveredSuit = nil
                }
            }
            
        case .waitingForTrump:
            setPlayerState(to: .waiting)
            
            // Once a trump suit is chosen and confirmed:
            if (gameState.trumpSuit != nil) && (localPlayer.place == 2) {
                transition(to: .discard) // In case local player is second
            }
            
        case .discard:
            setPlayerState(to: .discarding)
            
        case .bidding:
            if gameState.round < 4 {
                if isLocalPlayerTurnToBet() {
                    logger.log("local player must bet < 4")
                    setPlayerState(to: .bidding)
                    showOptions = true
                } else if allPlayersBet() {
                    showOptions = false
                    transition(to: .showCard)
                } else {
                    showOptions = false
                    setPlayerState(to: .waiting)
                }
            } else { // round > 3
                if allPlayersBet() {
                    logger.log("All players have bet")
                    if lastPlayerDiscarded() {
                        transition(to: .playingTricks)
                    } else {
                        if localPlayer.place == 3 {
                            transition(to: .discard)
                        } else {
                            setPlayerState(to: .waiting)
                        }
                    }
                } else {
                    logger.log("Some players have not bet")
                    // At the last round, if local player is last and has 2 bonus cards, he must wait for the second player to discard his card first.
                    if gameState.round == 12
                        && (gameState.bonusCardsNeeded(for: localPlayer.id) == 2)
                        && localPlayer.hand.count != 12 {
                        setPlayerState(to: .waiting)
                        logger.log("Waiting for second player to give me his card")
                    } else {
                        showOptions = true
                        setPlayerState(to: .bidding)
                        logger.log("local player must bet > 3")
                    }
                }
            }
            
        case .showCard:
            setPlayerState(to: .idle)
            hoveredSuit = nil
            for i in localPlayer.hand.indices {
                localPlayer.hand[i].isFaceDown = false
            }
            
            transition(to: .playingTricks)
            
        case .playingTricks:
            showOptions = false // Hide the options view
            hoveredSuit = nil
            let allPlayersAreTied: Bool = gameState.players.map { $0.scores.last ?? 0 }.allSatisfy { $0 == gameState.players.first?.scores.last ?? 0 }
            if gameState.round > 3 && !allPlayersAreTied {
                gameState.trumpCards.last?.isFaceDown = false // show the trump card to the first player
            }
            
            if isLocalPlayerTurnToPlay() {
                setPlayerState(to: .playing)
                setPlayableCards()
                if autoPilot && !isRestoring {
                    waitForAnimationsToFinish {
                        self.AIPlayCard() {
                            if self.allPlayersPlayed() {
                                self.transition(to: .grabTrick)
                            } else {
                                self.setPlayerState(to: .waiting)
                            }
                        }
                    }
                }
            } else if allPlayersPlayed() {
                transition(to: .grabTrick)
            } else {
                setPlayerState(to: .waiting)
            }
            
        case .grabTrick:
            // Wait a few seconds and grab trick automatically
            // and set the last trick
            // and refresh playOrder
            isAwaitingActionCompletionDuringRestore = true
            logger.log("Assigning trick")
            setPlayerState(to: .idle)
            waitForAnimationsToFinish {
                self.assignTrick() {
                    self.gameState.currentTrick += 1
                    logger.log("Trick assigned, current trick is now \(self.gameState.currentTrick)")
                    self.isAwaitingActionCompletionDuringRestore = false
                    // check if last trick
                    if self.isLastTrick() {
                        self.transition(to: .scoring)
                    } else {
                        self.transition(to: .playingTricks)
                    }
                }
            }
            
            
        case .scoring:
            isAwaitingActionCompletionDuringRestore = true
            waitForAnimationsToFinish {
                logger.debug("Animations finished")
                self.gatherCards {
                    logger.debug("gatherCards finished")
                    // Compute scores
                    self.setPlayerState(to: .idle)
                    self.computeScores()
                    
                    // update positions
                    self.updatePlayersPositions()
                    
                    // if last round, transition to gameOver
                    self.isAwaitingActionCompletionDuringRestore = false
                    if self.gameState.round == 12 {
                        self.transition(to: .gameOver)
                    } else { // proceed to the next round
                        self.transition(to: .setupNewRound)
                    }
                }
            }

        case .gameOver:
            setPlayerState(to: .idle)
            showConfetti.toggle()
            playSound(named: "applaud")
            playSound(named: "Confetti")
            // Show final results, store the score, transition to .newGame ...
            clearSavedGameAtions()
            // save the game
            saveScore() //Sets the winner too
            isGameSetup = false // To allow recovery in case of crash
            isFirstGame = false
            transition(to: .setPlayOrder)
        }
    }
    
    // MARK: checkAndAdvanceStateIfNeeded
    
    // Call this after actions come in or after dealing
    // to see if conditions are met to move to next phase
    func checkAndAdvanceStateIfNeeded() {
        // TODO: Add a .pause phase for when a player disconnects?
        
        logger.log("🔁 checkAndAdvanceStateIfNeeded() called during phase \(gameState.currentPhase)")
        switch gameState.currentPhase {
        case .waitingForPlayers:
            if gameState.allPlayersConnected { // Use the existing computed property
                logger.log("All players connected! Transitioning from .waitingForPlayers...")
                transition(to: .resumeSavedGame)
            } else {
                // Still waiting, log status
                let connectedCount = gameState.players.filter { $0.firebasePresenceOnline }.count
                let totalCount = gameState.players.count
                logger.log("Waiting for players: \(connectedCount)/\(totalCount) connected.")
            }
            
        case .resumeSavedGame:
            logger.log("Not doing anything")
            
        case .setPlayOrder:
            if gameState.playOrder == [] {
                logger.log("PlayOrder not set yet. Waiting in .setPlayOrder...")
            } else {
                logger.log("PlayOrder initialized! Moving to .setupGame")
                transition(to: .setupGame)
            }
            
        case .renderingDeck:
            if isDeckReady {
                transition(to: .dealingCards)
            }
            
        case .waitingForDeck:
            if isDeckReceived {
                transition(to: .dealingCards)
            } else {
                logger.log("Still waiting for the deck...")
            }
            
        case .dealingCards:
            // This state is handled in handleStateTransition
            logger.log("Dealing cards")
            
        case .choosingTrump:
            // If trump chosen, I chose a bid
            if gameState.trumpSuit != nil {
                transition(to: .bidding)
            } else {
                transition(to: .choosingTrump)
            }
            
        case .waitingForTrump:
            // If trump chosen, I chose a bid
            if gameState.trumpSuit != nil {
                transition(to: .discard)
            }
            
        case .discard:
            let numberOfCardsToDiscard = (gameState.localPlayer?.hand.count ?? 0) - max(1, gameState.round - 2)
            if numberOfCardsToDiscard > 0 {
                if gameState.trumpCards.last?.isFaceDown == false {
                    return
                } else { // the player cancelled the trump choice
                    transition(to: .waitingForTrump)
                }
            } else if gameState.localPlayer?.place == 2 {
                transition(to: .bidding)
            } else {
                transition(to: .playingTricks)
            }
            
        case .bidding:
            if allPlayersBet() {
                showOptions = false
                if gameState.round < 4 {
                    transition(to: .showCard)
                } else if gameState.localPlayer?.place == 3 {
                    transition(to: .discard)
                } else if lastPlayerDiscarded() {
                    transition(to: .playingTricks)
                } else {
                    transition(to: .bidding)
                }
            } else {
                transition(to: .bidding)
            }
            
        case .showCard:
            gameState.trumpCards.last?.isFaceDown = false
            transition(to: .playingTricks)
            
        case .playingTricks:
            if allPlayersPlayed() {
                transition(to: .grabTrick)
            } else {
                transition(to: .playingTricks)
            }
            break
            
        case .grabTrick:
            if gameState.table.isEmpty && !allPlayersPlayed() {
                // check if last trick
                if isLastTrick() {
                    transition(to: .scoring)
                } else {
                    transition(to: .playingTricks)
                }
            } else {
                logger.debug("Transitioning to grabTrick")
                transition(to: .grabTrick)
            }
            
        case .scoring:
            // After scoring logic:
            // Either start new round: transition(to: .dealingCards)
            // Or end game: transition(to: .gameOver)
            break
            
        default:
            break
        }
    }
    
    // MARK: - Utilities
    
    func startNewGame() {
        logger.log("Starting new game")
        transition(to: .newGame)
    }
    
    func isLocalPlayerTurnToBet() -> Bool {
        guard let localPlayerID = gameState.localPlayer?.id else {
            logger.log("Error: Local player ID not found.")
            return false
        }
        
        if gameState.round < 4 {
            guard let playerIndex = gameState.playOrder.firstIndex(of: localPlayerID) else {
                logger.log("Error: Local player not found in play order.")
                return false
            }
            
            // Check if all previous players in play order have made their bets
            for index in 0..<playerIndex {
                let previousPlayerID = gameState.playOrder[index]
                guard let previousPlayer = gameState.players.first(where: { $0.id == previousPlayerID }) else {
                    logger.log("Error: Player \(previousPlayerID) not found.")
                    return false
                }
                
                if previousPlayer.announcedTricks.count < gameState.round {
                    // A previous player hasn't made their bet yet
                    return false
                }
            }
            
            // Check if the player already bet
            if gameState.localPlayer!.announcedTricks.count >= gameState.round {
                return false
            }
            
            // If all checks pass, it's local player's turn to bet
            return true
        }
        else {
            return true
        }
    }
    
    func allPlayersBet() -> Bool {
        return gameState.players.allSatisfy { $0.announcedTricks.count == gameState.round }
    }
    
    func lastPlayerDiscarded() -> Bool {
        if gameState.round < 4 || allScoresEqual() { return true }
        if let lastPlayer = gameState.lastPlayer {
            logger.log("Last player \(lastPlayer.id) hasDiscarded: \(lastPlayer.hasDiscarded)")
            return lastPlayer.hasDiscarded
        } else {
            logger.log("lastPlayerDiscarded: No last player found.")
            return false
        }
    }
    
    func isLocalPlayerTurnToPlay() -> Bool {
        guard let localPlayerID = gameState.localPlayer?.id else {
            logger.fatalErrorAndLog("Error: Local player ID not found.")
        }
        
        guard let playerIndex = gameState.playOrder.firstIndex(of: localPlayerID) else {
            logger.fatalErrorAndLog("Error: Local player not found in play order.")
        }
        
        // Check if it's the local player's turn to play
        if gameState.table.count == playerIndex {
            logger.log("It's my turn to play")
            return true
        } else {
            logger.log("Not my turn to play yet")
            return false
        }
    }
    func allPlayersPlayed() -> Bool {
        return gameState.table.count == gameState.players.count
    }
    
    func allPlayersIded() -> Bool {
        logger.log("Players usernames: \(gameState.players.map(\.username))")
        return gameState.players.allSatisfy { !$0.username.isEmpty }
    }
    
    func isLastTrick() -> Bool {
        // Check if all players' hands are empty
        let allHandsEmpty = gameState.players.allSatisfy { $0.hand.isEmpty }
        logger.log("allHandsEmpty: \(allHandsEmpty)")
        if allHandsEmpty {
            return true
        }
        
        return false
    }
    
    func computeScores() {
        // Determine the maximum possible tricks for this round
        let maxTricks = max(gameState.round - 2, 1)
        
        for player in gameState.players {
            guard gameState.round > 0 else { return }
            let roundIndex = gameState.round - 1
            
            // Ensure the player has announced and made tricks for this round
            guard player.announcedTricks.indices.contains(roundIndex),
                  player.madeTricks.indices.contains(roundIndex) else {
                logger.log("Error: Missing announced or made tricks for player \(player.username)")
                continue
            }
            
            let announced = player.announcedTricks[roundIndex]
            let made = player.madeTricks[roundIndex]
            var roundScore = 0
            
            if announced == made {
                // Player matched their announced tricks
                if announced == maxTricks {
                    // Announced maximum tricks
                    roundScore = 10 + 10 * made
                } else {
                    // Standard scoring
                    roundScore = 10 + 5 * made
                }
            } else {
                // Player missed their announced tricks
                roundScore = -5 * abs(made - announced)
                player.onlyWins = false
            }
            
            // Add the round score to the player's total score
            let totalScore = (player.scores.last ?? 0) + roundScore
            player.scores.append(totalScore)
            
            logger.log("Player \(player.username): Announced \(announced), Made \(made), Round Score \(roundScore), Total Score \(totalScore)")
        }

        // Update onlyWinsBonus flags
        // Rule: Set to true if the player has won all rounds so far and round > 3.
        // It should remain true unless the player loses AND at least one other player still has onlyWins == true.
        if gameState.round > 3 {
            // Check if at least one player still has a perfect streak
            let someoneStillPerfect = gameState.players.contains { $0.onlyWins }
            for p in gameState.players {
                if p.onlyWins {
                    // Perfect so far and beyond round 3 -> ensure bonus is on
                    p.onlyWinsBonus = true
                } else if someoneStillPerfect {
                    // This player lost, and at least one other is still perfect -> remove bonus
                    p.onlyWinsBonus = false
                } // else: keep current state (bonus stays as-is if nobody is still perfect)
            }
        } else {
            // Before or at round 3, ensure no one gets the bonus yet
            for p in gameState.players {
                p.onlyWinsBonus = false
            }
        }
        
        // Add bonus for the highest bidder in the last round (round 12)
        if gameState.round == 12 {
            // Calculate each player's total announced tricks (across all rounds)
            let playersAnnouncedTotals = gameState.players.map { player in
                (player: player, total: player.announcedTricks.reduce(0, +))
            }
            let maxAnnounced = playersAnnouncedTotals.map { $0.total }.max() ?? 0
            
            // Identify all players who reached the maximum
            let topPlayers = playersAnnouncedTotals.filter { $0.total == maxAnnounced }
            if topPlayers.count == 1 {
                let bonusWinner = topPlayers.first!.player
                // Add 15 bonus points to the bonus winner's last score
                bonusWinner.scores[bonusWinner.scores.count - 1] += 15
                logger.log("Bonus added for highest bidder \(bonusWinner.username): +15 points")
            } else {
                logger.log("No bonus added due to tie among highest bidders.")
            }
            
            // Add the bonus for the longest streak
            // Add +5 to all players who kept the only-wins bonus
            for p in gameState.players where p.onlyWinsBonus {
                let lastIndex = p.scores.count - 1
                if lastIndex >= 0 {
                    p.scores[lastIndex] += 5
                    logger.log("Only-wins streak bonus added to \(p.username): +5 points")
                }
            }
            
        }
        if !isRestoring {
            self.playersScoresUpdated.toggle()
        }
    }
    
    func isActionValidInCurrentPhase(_ actionType: GameAction.ActionType) -> Bool {
        return (actionType.associatedPhases.contains(gameState.currentPhase) || actionType.associatedPhases == [])
    }
    
    func processPendingActionsForCurrentPhase(checkState: Bool = true) -> Bool {
        guard pendingActions.isEmpty == false else { return false }
        
        logger.log("Pending actions count: \(pendingActions.count)")
        logger.log("checkState: \(checkState)")
        var atLeastOneActionProcessed = false
        
        let remainingActions = pendingActions
        pendingActions.removeAll()
        
        for action in remainingActions {
            if isActionValidInCurrentPhase(action.type) {
                logger.log("Action \(action.type) is valid in current phase, processing it")
                processAction(action)
                atLeastOneActionProcessed = true
            } else {
                logger.log("Action \(action.type) is NOT valid in current phase (\(gameState.currentPhase)), skipping it")
                pendingActions.append(action)  // Re-add invalid actions
            }
        }
        
        if atLeastOneActionProcessed && checkState {
            logger.log("processPendingActionsForCurrentPhase: Checking state after processing actions...")
            checkAndAdvanceStateIfNeeded()
        }
        
        // Remove processed actions from pendingActions
        logger.log("Pending actions left: \(pendingActions.count)")
        
        return atLeastOneActionProcessed
    }
    
    // MARK: - Slowpoke Timer Helpers
    
    /// Cancels any existing slowpoke timer.
    func cancelSlowpokeTimer() {
        amSlowPoke = false
        slowpokeTimer?.cancel()
        slowpokeTimer = nil
    }
    
    /// Starts a slowpoke timer for the local player.
    func startSlowpokeTimer() {
        cancelSlowpokeTimer()
        guard let localPlayer = gameState.localPlayer else { return }
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now() + slowpokeDelay)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            logger.log("Slowpoke timer fired for \(localPlayer.id)")
            self.sendAmSlowPoke()
            amSlowPoke = true
        }
        timer.resume()
        slowpokeTimer = timer
    }
}
