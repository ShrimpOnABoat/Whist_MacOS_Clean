//
//  GM+Cards.swift
//  Whist
//
//  Created by Tony Buffard on 2024-12-01.
//

import Foundation
import SwiftUI

extension GameManager {
    // functions dealing with the cards
    
    // MARK: initializeCards
    
    func initializeCards() {
        // remove the old deck of cards if it's not the first game of the session
        gameState.deck.removeAll()
        
        // Create the deck cards, the trump ones are already defined
        for suit in Suit.allCases {
            for rank in Rank.allCases {
                let card = Card(suit: suit, rank: rank)
                if rank != .two {
                    gameState.deck.append(card)
                }
            }
        }
        if gameState.deck.count != 32 || gameState.trumpCards.count != 4 {
            logger.log("Number of cards: \(gameState.deck.count), number of trump cards: \(gameState.trumpCards.count)")
            logger.fatalErrorAndLog("Something went wrong creating the deck")
        }
    }
    
    // MARK: gatherCards
    
    func gatherCards(completion: @escaping () -> Void) {
        let totalCardsToMove = gameState.players.reduce(0) { $0 + $1.trickCards.count }
        logger.debug("beginBatchMove(\(totalCardsToMove)), activeAnimations: \(activeAnimations)")
        if totalCardsToMove > 0 {
            beginBatchMove(totalCards: totalCardsToMove) {
                completion()
            }
            
            // make sure they're all face down and not playable
            for index in gameState.deck.indices {
                gameState.deck[index].isFaceDown = true
                gameState.deck[index].isPlayable = false
            }
            for index in gameState.trumpCards.indices {
                gameState.trumpCards[index].isFaceDown = true
                gameState.trumpCards[index].isPlayable = false
            }
            
            for player in gameState.players {
                let source: CardPlace = player.tablePosition == .local ? .localPlayerTricks : (player.tablePosition == .left) ? .leftPlayerTricks : .rightPlayerTricks
                for card in player.trickCards {
                    moveCard(card, from: source, to: .deck)
                }
            }
            
            // Make sure everything is alright
            let deckCardCount: Int = gameState.deck.count
            let trumpCardCount: Int = gameState.trumpCards.count
            
            if (deckCardCount != 32) || (trumpCardCount != 4) {
                logger.fatalErrorAndLog("Some cards are missing or wrong count")
            }
        } else {
            completion()
        }
    }
    
    // MARK: shuffleCards
    
    func shuffleCards(animationOnly: Bool = false, completion: @escaping () -> Void) {
        guard !isRestoring else {
            gameState.deck = gameState.newDeck
            completion()
            return
        }
        var newDeck: [Card] = []
        if animationOnly {
            // We use the deck received from the dealer
            newDeck = gameState.newDeck
        } else {
            // Generate a new shuffled deck
            newDeck = gameState.deck.shuffled()
        }
        
        // Call simulateShuffle with the new deck order
        if let shuffle = shuffleCallback {
            shuffle(newDeck) {
                logger.log("Shuffle complete!")
                completion()
            }
        } else {
            logger.log("Shuffle callback is not set.")
            // we still shuffle the cards
            self.gameState.deck.shuffle()
            completion()
        }
    }
    
    // MARK: updateDeck
    
    func updateDeck(with data: Data) {
        // Make deck same as dealer's
        if let newDeck = try? JSONDecoder().decode([Card].self, from: data) {
            gameState.newDeck = newDeck
            self.isDeckReady = true
            self.isDeckReceived = true
            logger.log("Updated deck from dealer, isDeckReady now true")
            logger.debug("Deck: \(newDeck)")
        } else {
            logger.log("Failed to decode deck data.")
        }
    }
    
    // MARK: dealCards
    
    func dealCards(completion: @escaping () -> Void) {
        logger.debug("♠️♥️♣️♦️ Start dealing cards with deck \(gameState.deck)")
        var cardsToDeal: Int
        
        isDeckReceived = false
        
        // Sort players by the last score
        gameState.players.sort { (a, b) -> Bool in
            let lastScoreA = a.scores.last ?? 0
            let lastScoreB = b.scores.last ?? 0
            return lastScoreA < lastScoreB
        }
        
        // Establish the base number of cards to deal for each round
        if gameState.round <= 3 {
            cardsToDeal = 1
        } else if gameState.round <= 12 {
            cardsToDeal = gameState.round - 2
        } else {
            return // No cards to deal beyond round 12
        }
        
        // Calculate the number of cards to deal to each player
        var cardsPerPlayer = [PlayerId: Int]() // PlayerId -> Cards to deal
        for player in gameState.players {
            var extraCards = 0
            
            if gameState.round > 3 {
                if player.place == 2 {
                    if player.monthlyLosses > 1 && gameState.round < 12 {
                        extraCards = 2
                    } else {
                        extraCards = 1
                    }
                } else if player.place == 3 {
                    extraCards = 1
                    let playerScore = player.scores[safe: gameState.round - 2] ?? 0
                    let secondPlayerScore = gameState.players[1].scores[safe: gameState.round - 2] ?? 0
                    
                    if player.monthlyLosses > 0 || Double(playerScore) <= 0.5 * Double(secondPlayerScore) {
                        extraCards = 2
                    }
                }
            }
            
            // Cap extra cards to the number of cards left in the deck for the last round
            if gameState.round == 12 && extraCards == 2,
               let secondPlayer = gameState.players[safe: 1],
               let thirdPlayer = gameState.players[safe: 2],
               secondPlayer.scores[safe: gameState.round - 2] != thirdPlayer.scores[safe: gameState.round - 2] {
                extraCards = 1
            }
            
            cardsPerPlayer[player.id] = cardsToDeal + extraCards
        }
        
        // Set the batch animation
        let totalCardsToMove = cardsPerPlayer.reduce(0) { $0 + $1.value }
        //        logger.log("dealCards: beginBatchMove(\(totalCardsToMove)), activeAnimations: \(activeAnimations)")
        beginBatchMove(totalCards: totalCardsToMove) {
            if !self.isRestoring {
                completion()
            }
        }
        
        // Distribute cards one by one in a clockwise manner with delay
        var currentIndex = 0
        
        func dealNextCard() {
            guard !gameState.deck.isEmpty else {
                completion()
                return
            }
            
            // Get the current player
            let playerID = gameState.playOrder[currentIndex]
            guard let remainingCards = cardsPerPlayer[playerID], remainingCards > 0 else {
                currentIndex = (currentIndex + 1) % gameState.playOrder.count
                dealNextCard() // Skip to the next player
                return
            }
            
            // Move card to player's hand with animation
            if let card = gameState.deck.last
            {
                card.isFaceDown = true
                card.isPlayable = false
                var destination: CardPlace = .localPlayer
                switch (gameState.getPlayer(by: playerID).tablePosition ) {
                case .local:
                    destination = .localPlayer
                    card.isFaceDown = gameState.round < 4 ? true : false
                case .left:
                    destination = .leftPlayer
                    card.isFaceDown = gameState.round < 4 ? false : true
                case .right:
                    destination = .rightPlayer
                    card.isFaceDown = gameState.round < 4 ? false : true
                default:
                    logger.fatalErrorAndLog("Invalid table position")
                }
                
                // Wait for card movement to complete before dealing next card
                moveCard(card, from: .deck, to: destination)
                cardsPerPlayer[playerID]! -= 1
                
                // Wait for the animation to complete before moving to next card
                let animationDuration: TimeInterval =  isRestoring ? 0 : 0.5 / Double(max(gameState.round - 2, 1))
                DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration) {
                    // Move to the next player
                    currentIndex = (currentIndex + 1) % self.gameState.playOrder.count
                    
                    // Stop if all cards are dealt
                    if cardsPerPlayer.values.allSatisfy({ $0 == 0 }) {
                        // Determine the trump card if applicable
                        if self.gameState.round <= 3 || self.allScoresEqual() {
                            if let trumpCard = self.gameState.deck.last {
                                self.gameState.trumpSuit = trumpCard.suit
                                withAnimation(.smooth(duration: 0.5)) {
                                    trumpCard.isFaceDown = false
                                    logger.log("Showing the trump card \(trumpCard)")
                                }
                            } else {
                                logger.log("Not showing the trump card")
                            }
                        }
                        self.sortLocalPlayerHand()
                        if self.isRestoring {
                            completion()
                        }
                    } else {
                        dealNextCard()
                    }
                }
            }
        }
        
        dealNextCard()
        logger.debug("♠️♥️♣️♦️ Finished dealing cards")
    }
    
    // MARK: sortLocalPlayerHand
    
    func sortLocalPlayerHand() {
        guard let localPlayerId = gameState.localPlayer?.id else {
            logger.fatalErrorAndLog("Error: Local player is not defined.")
        }
        
        let player = gameState.getPlayer(by: localPlayerId)
        
        // Define the suit order
        let suitsInHand = Set(player.hand.map { $0.suit })
        let suitOrder: [Suit]
        if !suitsInHand.contains(.clubs) {
            suitOrder = [.hearts, .spades, .diamonds]
        } else if !suitsInHand.contains(.diamonds) {
            suitOrder = [.clubs, .hearts, .spades]
        } else {
            suitOrder = [.hearts, .clubs, .diamonds, .spades]
        }
        
        // Sort the hand based on suit order and rank
        withAnimation(.easeInOut(duration: 0.4)) {
            player.hand.sort { card1, card2 in
                if card1.suit == card2.suit {
                    // If suits are the same, compare ranks
                    return card1.rank.precedence < card2.rank.precedence
                } else {
                    // Otherwise, sort by suit order
                    return suitOrder.firstIndex(of: card1.suit)! < suitOrder.firstIndex(of: card2.suit)!
                }
            }
        }

        //        logger.log("Local player's hand has been sorted.")
    }
    
    // MARK: playCard
    
    func playCard(_ card: Card, completion: @escaping () -> Void) {
        // Ensure the local player is defined
        guard let localPlayer = gameState.localPlayer else {
            logger.fatalErrorAndLog("Error: Local player is not defined.")
        }
        
        // Ensure the local player has the card in their hand
        guard localPlayer.hand.firstIndex(where: { $0 == card }) != nil else {
            logger.fatalErrorAndLog("Error: The card is not in the local player's hand.")
        }
        
        // Play the card
//        logger.log("playCard: beginBatchMove(1), activeAnimations: \(activeAnimations)")
        beginBatchMove(totalCards: 1) {
            completion()
        }
        moveCard(card, from: .localPlayer, to: .table)
        
        // Notify other players about the action
        sendPlayCardtoPlayers(card)
        
        // Set the remaining cards to not playable
        for card in localPlayer.hand {
            card.isPlayable = false
        }
        
        sortLocalPlayerHand()
        
        logger.log("Card \(card) played by \(localPlayer.username). Updated gameState.table: \(gameState.table)")
        
    }
    
    // MARK: Received played card
    
    func updateGameStateWithPlayedCard(from playerId: PlayerId, with card: Card, completion: @escaping () -> Void) {
        // Move the card from the player's hand to the table
        let player = gameState.getPlayer(by: playerId)
        
        logger.log("Received played card from \(playerId.rawValue) with card \(card).")
        //        logger.log("\(player)'s current hand: \(player.hand)")
        
        // Check if the player already played
        guard let playerIndex = gameState.playOrder.firstIndex(of: playerId) else {
            logger.fatalErrorAndLog("Player ID not found in play order.")
        }
        
        if gameState.table.indices.contains(playerIndex) {
            logger.log("Error: Player \(playerId.rawValue) has already played a card this round.")
            return
        }
        
        if player.hand.firstIndex(where: { $0 == card }) != nil {
            var source: CardPlace
            switch player.tablePosition {
            case .left:
                source = .leftPlayer
                
            case .right:
                source = .rightPlayer
                
            case .local:
                source = .localPlayer
                
            default:
                logger.fatalErrorAndLog("Player \(playerId.rawValue) hasn't a table position.")
            }
            beginBatchMove(totalCards: 1) { completion() }
            moveCard(card, from: source, to: .table)
        } else {
            logger.log("Error: Card not found in player's hand.")
            return
        }
//        saveGameState(gameState)
        logger.log("Card \(card) played by \(playerId.rawValue). Updated gameState.table: \(gameState.table)")
    }
    
    // MARK: setPlayableCards
    
    func setPlayableCards() {
        // Ensure the local player is defined
        guard let localPlayer = gameState.localPlayer else {
            logger.fatalErrorAndLog("Error: Local player is not defined.")
        }
        
        // Determine the leading suit if available
        let leadingSuit = gameState.table.first?.suit
        
        //        logger.log("setPlayableCards with leadingSuit \(leadingSuit?.rawValue ?? "Undefined")")
        
        // Check if the player has cards matching the leading suit
        let hasLeadingSuit = localPlayer.hand.contains { $0.suit == leadingSuit }
        
        // Determine playable cards
        localPlayer.hand.forEach { card in
            if let leadingSuit = leadingSuit, hasLeadingSuit {
                // If there's a leading suit and the player has cards of that suit,
                // only those cards are playable
                card.isPlayable = card.suit == leadingSuit
            } else {
                // Otherwise, all cards are playable
                card.isPlayable = true
            }
        }
    }
    
    // MARK: assignTricks
    
    func assignTrick(completion: @escaping () -> Void) {
        guard gameState.tricksGrabbed[gameState.currentTrick] == false else {
            logger.log("Already assigned trick \(gameState.currentTrick).")
            return
        }
        gameState.tricksGrabbed[gameState.currentTrick] = true
        
        // Ensure there are exactly 3 cards on the table
        guard gameState.table.count == 3 else {
            logger.fatalErrorAndLog("Table must contain exactly 3 cards. Cards on the table: \(gameState.table).")
        }
        
        // Ensure there's a trump suit defined
        guard let trumpSuit = gameState.trumpSuit else {
            logger.fatalErrorAndLog("Trump suit is not defined.")
        }
        
        // Determine the leading suit (suit of the first card played)
        guard let leadingSuit = gameState.table.first?.suit else {
            logger.fatalErrorAndLog("No leading suit found.")
        }
        
        // Find the winning card
        guard let winningCard = gameState.table.max(by: { card1, card2 in
            // Check if either card is a trump card
            if card1.suit == trumpSuit && card2.suit != trumpSuit {
                return false // card1 wins
            } else if card2.suit == trumpSuit && card1.suit != trumpSuit {
                return true // card2 wins
            }
            
            // If neither card is a trump card, compare by leading suit
            if card1.suit == leadingSuit && card2.suit != leadingSuit {
                return false // card1 wins
            } else if card2.suit == leadingSuit && card1.suit != leadingSuit {
                return true // card2 wins
            }
            
            // If both cards are of the same suit, compare ranks
            return card1.rank.precedence < card2.rank.precedence
        }) else {
            logger.fatalErrorAndLog("Failed to determine the winning card.")
        }
        
        // Find the winner (player who played the winning card)
        guard let winningCardIndex = gameState.table.firstIndex(of: winningCard),
              let winningPlayerID = gameState.playOrder[safe: winningCardIndex] else {
            logger.fatalErrorAndLog("Could not determine the winner.")
        }
        
        let winner = gameState.getPlayer(by: winningPlayerID)
        logger.log("Player \(winner.id.rawValue) won the trick with \(winningCard).")
        
        // Update the last trick with all played cards and their players
        gameState.lastTrick.removeAll()
        gameState.lastTrickCardStates.removeAll()
        showLastTrick = false // just in case
        for (index, playerId) in gameState.playOrder.enumerated() {
            if let card = gameState.table[safe: index], let state = cardStates[card.id] {
                let LTCard = Card(suit: card.suit, rank: card.rank, isLastTrick: true)
                gameState.lastTrick[playerId] = LTCard
                gameState.lastTrickCardStates[playerId] = CardState(
                    position: CGPoint(x: state.position.x - 30, y: state.position.y - 45),
                    rotation: state.rotation,
                    scale: state.scale,
                    zIndex: Double(index)
                )
            }
        }
        
        // make sure all cards moved before doing anything else
        //        logger.log("assignTricks: beginBatchMove(3), activeAnimations: \(activeAnimations)")
        beginBatchMove(totalCards: 3) {
            logger.log("Assign trick should be completed now!")
        }
        // Introduce a delay before clearing the table and assigning the trick unless restoring persistence
        let delay = isRestoring ? 0 : 1
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(delay)) {
            // Set isFaceDown to true for the cards on the table
            self.gameState.table.forEach { card in
                //                logger.log("Grabing card \(card) with active animations = \(self.activeAnimations)")
                card.isFaceDown = true
                switch winner.tablePosition {
                case .local:
                    self.moveCard(card, from: .table, to: .localPlayerTricks)
                case .left:
                    self.moveCard(card, from: .table, to: .leftPlayerTricks)
                case .right:
                    self.moveCard(card, from: .table, to: .rightPlayerTricks)
                default:
                    logger.fatalErrorAndLog("Unknown winner table position)")
                }
            }
            
            winner.madeTricks[self.gameState.round - 1] += 1
            logger.log("Winner \(winner.id.rawValue) has \(winner.trickCards.count) trick cards and announced \(winner.announcedTricks[self.gameState.round - 1]) trick.")
            
            // Add a delay after the animation completes if last trick of the round
            DispatchQueue.main.asyncAfter(deadline: .now() + (winner.hand.isEmpty && !self.isRestoring ? 1.5 : 0)) {
                if self.gameState.round > 3 {
                    self.updatePlayerPlayOrder(startingWith: .winner(winningPlayerID))
                }
                completion()
            }
        }
    }
    
    // MARK: ChooseTrump
    
    func chooseTrump(completion: @escaping () -> Void) {
        logger.log("chooseTrump: beginBatchMove(4), activeAnimations: \(activeAnimations)")
        beginBatchMove(totalCards: 4) { completion() }
        // Move the trump cards to the table face up
        logger.debug("Setting trump cards' isFaceDown and isPlayable")
        for card in gameState.trumpCards {
            card.isFaceDown = false
            card.isPlayable = true
            moveCard(card, from: .trumpDeck, to: .table)
        }
    }
    
    func selectTrumpSuit(_ trumpCard: Card, completion: @escaping () -> Void) {
        // Set the trump suit
        gameState.trumpSuit = trumpCard.suit
        
        // Move the cards back in the deck, the selected one last
        //        logger.log("selectTrump: beginBatchMove(4), activeAnimations: \(activeAnimations)")
        beginBatchMove(totalCards: 4) { completion() }
        for card in gameState.table {
            if card != trumpCard {
                card.isFaceDown = true
                moveCard(card, from: .table, to: .trumpDeck)
            }
        }
        moveCard(trumpCard, from: .table, to: .trumpDeck)
        
        // Send other players the chosen trump suit
        sendTrumpToPlayers(trumpCard)
//        saveGameState(gameState)
    }
    
    // MARK: discard
    
    func discard(cardsToDiscard: [Card], completion: @escaping () -> Void) {
        guard gameState.currentPhase == .discard else { return }
        
        beginBatchMove(totalCards: cardsToDiscard.count) { completion() }
        for card in cardsToDiscard {
            card.isFaceDown = true
            // if player is second, round is 12 and last player needs 2 cards, destination == last player instead of deck
            var destination: CardPlace = .deck
            
            if gameState.localPlayer?.place == 2 && gameState.round == 12 {
                if Double(gameState.lastPlayer?.scores[safe: gameState.round - 2] ?? 0) <= 0.5 * Double(gameState.localPlayer?.scores[safe: gameState.round - 2] ?? 0) || gameState.lastPlayer?.monthlyLosses ?? 0 > 0 {
                    switch gameState.lastPlayer?.tablePosition {
                    case .left:
                        destination = .leftPlayer
                    default:
                        destination = .rightPlayer
                    }
                }
            }
            moveCard(card, from: .localPlayer, to: destination)
        }
        
        // Send the information to other players
        sendDiscardedCards(cardsToDiscard)
        sortLocalPlayerHand()
        
        logger.log("Discarded cards: \(cardsToDiscard)")
        
        completion()
    }
    
    // MARK: AI functions
    
    func AIPlayCard(completion: @escaping () -> Void) {
        // Ensure the local player is defined
        guard let localPlayer = gameState.localPlayer else {
            logger.fatalErrorAndLog("Error: Local player is not defined.")
        }
        
        guard let localIndex = gameState.playOrder.firstIndex(of: localPlayer.id) else {
            logger.fatalErrorAndLog("Error: Local player index is not defined.")
        }
        
        if !gameState.table.indices.contains(localIndex) {
            // Filter playable cards
            let playableCards = localPlayer.hand.filter { $0.isPlayable }
            
            // Ensure there are playable cards
            guard !playableCards.isEmpty else {
                logger.fatalErrorAndLog("Error: No playable cards available.")
            }
            
            // Select a random playable card
            if let selectedCard = playableCards.randomElement() {
                logger.log("AI is playing card: \(selectedCard)")
                
                // Play the selected card
                playCard(selectedCard) {
                    logger.log("AI played card \(selectedCard)")
                    //                    self.checkAndAdvanceStateIfNeeded()
                    completion()
                }
            }
        }
    }
    
    func AIChooseTrumpSuit(completion: @escaping () -> Void) {
        if gameState.trumpSuit == nil && !gameState.table.isEmpty {
            selectTrumpSuit(gameState.table.randomElement()!) {
                //                self.checkAndAdvanceStateIfNeeded()
                completion()
            }
        } else {
            logger.log("the trump suit was already chosen by AI or the table is empty")
        }
    }
    
    func AIdiscard(completion: @escaping () -> Void) {
        var numberOfCardsToDiscard = 0
        
        if gameState.round > 3 {
            if gameState.localPlayer?.place == 2 {
                if gameState.localPlayer?.monthlyLosses ?? 0 > 1 && gameState.round < 12 {
                    numberOfCardsToDiscard = 2
                } else {
                    numberOfCardsToDiscard = 1
                }
            } else if gameState.localPlayer?.place == 3 {
                numberOfCardsToDiscard = 1
                let playerScore = gameState.localPlayer?.scores[safe: gameState.round - 2] ?? 0
                let secondPlayerScore = gameState.players[1].scores[safe: gameState.round - 2] ?? 0
                
                if gameState.localPlayer?.monthlyLosses ?? 0 > 0 || Double(playerScore) <= 0.5 * Double(secondPlayerScore) {
                    numberOfCardsToDiscard = 2
                }
            }
        }
        
        if let hand = gameState.localPlayer?.hand {
            let cardsToDiscard = Array(hand.shuffled().prefix(numberOfCardsToDiscard))
            
            discard(cardsToDiscard: cardsToDiscard) {
                //                self.checkAndAdvanceStateIfNeeded()
                completion()
            }
        }
    }
    
    // MARK: - Debugging Helpers

    /// Prints debug info for a specific card, including its context in the game state.
    func printDebugInfo(for card: Card) {
        // Check deck
        if gameState.deck.firstIndex(of: card) != nil {
            card.printDebugInfo(in: gameState.deck, arrayName: "deck")
            return
        }
        // Check trump deck
        if gameState.trumpCards.firstIndex(of: card) != nil {
            card.printDebugInfo(in: gameState.trumpCards, arrayName: "trumpCards")
            return
        }
        // Check table
        if gameState.table.firstIndex(of: card) != nil {
            card.printDebugInfo(in: gameState.table, arrayName: "table")
            return
        }
        // Check each player's hand and trickCards
        for player in gameState.players {
            if let _ = player.hand.firstIndex(of: card) {
                card.printDebugInfo(in: player.hand, arrayName: "\(player.id.rawValue) hand")
                return
            }
            if let _ = player.trickCards.firstIndex(of: card) {
                card.printDebugInfo(in: player.trickCards, arrayName: "\(player.id.rawValue) trickCards")
                return
            }
        }
        // Fallback: just print basic info
        card.printDebugInfo()
    }

    /// Iterates through all card collections and prints debug info for each.
    func printAllCardsDebugInfo() {
        print("=== All Cards Debug Info ===")
        // Decks and table
        let sections: [(cards: [Card], name: String)] = [
            (gameState.deck, "deck"),
            (gameState.trumpCards, "trumpCards"),
            (gameState.table, "table")
        ]
        for (cards, name) in sections {
            cards.forEach { $0.printDebugInfo(in: cards, arrayName: name) }
        }
        // Players' hands and trickCards
        for player in gameState.players {
            player.hand.forEach { $0.printDebugInfo(in: player.hand, arrayName: "\(player.id.rawValue) hand") }
            player.trickCards.forEach { $0.printDebugInfo(in: player.trickCards, arrayName: "\(player.id.rawValue) trickCards") }
        }
    }
}
