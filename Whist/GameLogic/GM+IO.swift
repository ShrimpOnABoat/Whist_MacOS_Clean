//
//  GM+IO.swift
//  Whist
//
//  Created by Tony Buffard on 2024-12-01.
//

import Foundation
import SwiftUI
import AppKit

extension Image {
    func asNSImage(size: CGSize = CGSize(width: 100, height: 100)) -> NSImage? {
        let hostingView = NSHostingView(rootView: self.resizable())
        hostingView.frame = CGRect(origin: .zero, size: size)

        let rep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        hostingView.cacheDisplay(in: hostingView.bounds, to: rep!)
        let image = NSImage(size: size)
        image.addRepresentation(rep!)
        return image
    }
}

extension GameManager {
    
    struct PlayerIdentification: Codable {
        let id: PlayerId
        let username: String
    }

    // MARK: - Sequencing helpers
    private func nextSequence(_ completion: @escaping (Int) -> Void) {
        Task {
            do {
                let seq = try await FirebaseService.shared.nextActionSequence()
                completion(seq)
            } catch {
                logger.fatalErrorAndLog("Sequence error: \(error.localizedDescription).")
            }
        }
    }

    private func buildActionWithSequence(type: GameAction.ActionType, payload: Data, playerId: PlayerId, completion: @escaping (GameAction) -> Void) {
        guard !isRestoring else { return }
        nextSequence { seq in
            let action = GameAction(
                playerId: playerId,
                type: type,
                payload: payload,
                timestamp: Date().timeIntervalSince1970,
                sequence: seq
            )
            completion(action)
        }
    }

    // MARK: - handleReceivedAction
    
    func handleReceivedAction(_ action: GameAction) {
        logger.log("Handling action \(action.type) from \(action.playerId)")
        DispatchQueue.main.async {
            // Check if the action is valid for the current phase
            if self.isActionValidInCurrentPhase(action.type) {
                self.processAction(action)
                if action.type != .sendState {
                    self.checkAndAdvanceStateIfNeeded()
                }
            } else {
                // Store the action for later
                self.pendingActions.append(action)
                logger.log("Stored action \(action.type) from \(action.playerId) for later because currentPhase = \(self.gameState.currentPhase)")
            }
        }
    }
    
    func processAction(_ action: GameAction) {
        logger.log("Processing action \(action.type) from player \(action.playerId)...")
        
        lastAppliedSequence = max(action.sequence, lastAppliedSequence)
        logger.log("lastAppliedSequence is now: \(lastAppliedSequence)")
        
        switch action.type {
        case .playOrder:
            guard let playOrder = try? JSONDecoder().decode([PlayerId].self, from: action.payload) else {
                logger.log("Failed to decode playOrder.")
                return
            }
            gameState.playOrder = playOrder

        case .playCard:
            guard let card = try? JSONDecoder().decode(Card.self, from: action.payload) else {
                logger.log("Failed to decode played card.")
                return
            }
            self.updateGameStateWithPlayedCard(from: action.playerId, with: card) {
                return
            }
            
        case .sendDeck:
            logger.log("Received deck from \(action.playerId).")
            self.updateDeck(with: action.payload)

        case .choseBet:
            if let bet = try? JSONDecoder().decode(Int.self, from: action.payload) {
                self.updateGameStateWithBet(from: action.playerId, with: bet)
            } else {
                logger.log("Failed to decode bet value.")
            }
            
        case .choseTrump:
            logger.log("Received trump")
            if let trumpCard = try? JSONDecoder().decode(Card.self, from: action.payload) {
                self.updateGameStateWithTrump(from: action.playerId, with: trumpCard)
            } else {
                logger.log("Failed to decode trump suit.")
            }
            
        case .cancelTrump:
            logger.log("Received cancellation of trump suit")
            // Do something only if last
            if gameState.localPlayer?.place == 3 {
                self.updateGameStateWithTrumpCancellation()
            }
            
        case .discard:
            logger.log("Received discard")
            if let discardedCards = try? JSONDecoder().decode([Card].self, from: action.payload) {
                self.updateGameStateWithDiscardedCards(from: action.playerId, with: discardedCards) {}
            } else {
                logger.log("Failed to decode discarded cards.")
            }
            
        case .sendState:
            if let state = try? JSONDecoder().decode(PlayerState.self, from: action.payload) {
                self.updatePlayerWithState(from: action.playerId, with: state)
            } else {
                logger.log("Failed to decode state.")
            }
            
        case .startNewGame:
            self.startNewGame()
            
        case .amSlowPoke:
            logger.log("Received slowPoke signal")
            self.showSlowPokeButton(for: action.playerId)
            /// faire un bool pour savoir si je suis visé
            /// jouer le volume moins fort si c'Est pas pour moi
            /// placer le bouton avec l'Autre Autopilot
            /// flasher le state et jouer le son

        case .honk:
            logger.log("I've been honked!!")
            self.honk()
            
        case .dealer:
            logger.log("Received dealer")
            if let dealer = try? JSONDecoder().decode(PlayerId.self, from: action.payload) {
                self.updateGameStateWithDealer(from: action.playerId, with: dealer)
            } else {
                logger.log("Failed to decode dealer.")
            }
        }
    }
    
    // MARK: - Send data
    func sendPlayOrderToPlayers(_ playOrder: [PlayerId]) {
        guard let localPlayerID = gameState.localPlayer?.id, localPlayerID == .toto else { return }

        if let playOrderData = try? JSONEncoder().encode(playOrder) {
            buildActionWithSequence(type: .playOrder, payload: playOrderData, playerId: localPlayerID) { action in
                self.persistAndSend(action)
            }
        } else {
            logger.log("Error: Failed to encode the play order")
        }
    }

    
    func sendDeckToPlayers() {
        logger.log("Sending deck to players: \(gameState.deck)")
        // Ensure localPlayer is defined
        guard let localPlayer = gameState.localPlayer else {
            logger.log("Error: Local player is not defined")
            return
        }
        
        // Encode the filtered deck and create the action
        if let deckData = try? JSONEncoder().encode(gameState.deck) {
            buildActionWithSequence(type: .sendDeck, payload: deckData, playerId: localPlayer.id) { action in
                self.persistAndSend(action)
            }
        } else {
            logger.log("Error: Failed to encode the deck cards")
        }
    }

    
    func sendPlayCardtoPlayers(_ card: Card) {
        logger.log("Sending play card \(card) to players")
        guard let localPlayer = gameState.localPlayer else {
            logger.log("Error: Local player is not defined")
            return
        }
        
        if let cardData = try? JSONEncoder().encode(card) {
            buildActionWithSequence(type: .playCard, payload: cardData, playerId: localPlayer.id) { action in
                self.persistAndSend(action)
            }
        } else {
            logger.log("Error: Failed to encode the card")
        }
    }
    
    func sendBetToPlayers(_ bet: Int) {
        logger.log("Sending bet \(bet) to players")
        guard let localPlayer = gameState.localPlayer else {
            logger.log("Error: Local player is not defined")
            return
        }
        
        if let betData = try? JSONEncoder().encode(bet) {
            buildActionWithSequence(type: .choseBet, payload: betData, playerId: localPlayer.id) { action in
                self.persistAndSend(action)
            }
        } else {
            logger.log("Error: Failed to encode the bet")
        }
    }
    
    func sendTrumpToPlayers(_ trump: Card) {
        logger.log("Sending trump \(trump) to players")
        guard let localPlayer = gameState.localPlayer else {
            logger.log("Error: Local player is not defined")
            return
        }
        
        if let trumpData = try? JSONEncoder().encode(trump) {
            buildActionWithSequence(type: .choseTrump, payload: trumpData, playerId: localPlayer.id) { action in
                self.persistAndSend(action)
            }
        } else {
            logger.log("Error: Failed to encode the trump card")
        }
    }
    
    func sendDiscardedCards(_ discardedCards: [Card]) {
        logger.log("Sending discarded cards \(discardedCards) to players")
        guard let localPlayer = gameState.localPlayer else {
            logger.log("Error: Local player is not defined")
            return
        }
        
        if let discardedCardsData = try? JSONEncoder().encode(discardedCards) {
            buildActionWithSequence(type: .discard, payload: discardedCardsData, playerId: localPlayer.id) { action in
                self.persistAndSend(action)
            }
        } else {
            logger.log("Error: Failed to encode the trump card")
        }
    }
    
    func sendStateToPlayers() {
        guard !isRestoring else {
            logger.debug("Skipping sendStateToPlayers during restore")
            return
        }
        guard let localPlayer = gameState.localPlayer else {
            logger.log("Error: Local player is not defined")
            return
        }
        let state = localPlayer.state
        logger.log("Sending new state \(state.message) to players")
        
        if let state = try? JSONEncoder().encode(state) {
            buildActionWithSequence(type: .sendState, payload: state, playerId: localPlayer.id) { action in
                self.persistAndSend(action)
            }
        } else {
            logger.log("Error: Failed to encode player's state")
        }
    }
    
    func sendStartNewGameAction() {
        logger.log("Sending start new game action to players")
        guard let localPlayer = gameState.localPlayer else { return }

        Task {
            do {
                self.buildActionWithSequence(type: .startNewGame, payload: Data(), playerId: localPlayer.id) { action in
                    self.persistAndSend(action)
                }
            }
        }
    }
    
    func sendCancelTrumpChoice() {
        logger.log("Sending cancel trump choice action to players")
        guard let localPlayer = gameState.localPlayer else {
            logger.log("Error: Local player is not defined")
            return
        }
        
        buildActionWithSequence(type: .cancelTrump, payload: Data(), playerId: localPlayer.id) { action in
            self.persistAndSend(action)
        }
    }
    
    func sendAmSlowPoke() {
        logger.log("Sending I'm a slowpoke signal to players")
        guard let localPlayer = gameState.localPlayer else {
            logger.log("Error: Local player is not defined")
            return
        }
        
        buildActionWithSequence(type: .amSlowPoke, payload: Data(), playerId: localPlayer.id) { action in
            self.persistAndSend(action)
        }
    }
    
    func sendHonk() {
        guard isSlowPoke.values.contains(true) else {
            return
        }
        
        logger.log("Honking other players")
        guard let localPlayer = gameState.localPlayer else {
            logger.log("Error: Local player is not defined")
            return
        }
        
        buildActionWithSequence(type: .honk, payload: Data(), playerId: localPlayer.id) { action in
            self.persistAndSend(action)
        }
        
        playSound(named: "pouet")
    }
    
    func persistOrderAndDealer() {
        guard gameState.playOrder != [] else {
            logger.log("No playOrder defined")
            return
        }
        guard gameState.dealer != nil else {
            logger.log( "No dealer defined")
            return
        }
        guard let localPlayer = gameState.localPlayer else {
            logger.log("Error: Local player is not defined")
            return
        }
        
        logger.log("Sending playOrder and Dealer to other players")
        
        if let playOrderData = try? JSONEncoder().encode(gameState.playOrder) {
            buildActionWithSequence(type: .playOrder, payload: playOrderData, playerId: localPlayer.id) { action in
                self.persist(action)
            }
        } else {
            logger.log("Error: Failed to encode the play order")
        }

        if let dealerData = try? JSONEncoder().encode(gameState.dealer) {
            buildActionWithSequence(type: .dealer, payload: dealerData, playerId: localPlayer.id) { action in
                self.persist(action)
            }
        } else {
            logger.log("Error: Failed to encode the dealer")
        }
    }
    
    func persistAndSend(_ action: GameAction) {
        guard !isRestoring else { return }
        
        lastAppliedSequence = max(action.sequence, lastAppliedSequence)
        logger.log("lastAppliedSequence set to \(lastAppliedSequence)")
        
        if let actionData = try? JSONEncoder().encode(action),
           let messageString = String(data: actionData, encoding: .utf8) {
            let sent = connectionManager.sendMessage(messageString)
            if sent {
                 logger.log("Sent P2P action \(action.type) to other players")
            } else {
                 logger.log("Failed to send P2P action \(action.type) (some channels might not be open)")
            }
            if ![.amSlowPoke, .honk].contains(action.type) {
                saveGameAction(action)
            }
        } else {
            logger.log("Failed to encode action or convert to string")
        }
    }
    
    func persist(_ action: GameAction) {
        guard !isRestoring else { return }
        if ![.amSlowPoke, .honk].contains(action.type) {
            saveGameAction(action)
        }
    }
    
    // MARK: CatchUp
    func requestCatchUp(from start: Int, to end: Int? = nil) {
        Task { await catchUp(from: start, to: end) }
    }

    @MainActor
    func catchUp(from start: Int, to end: Int?) async {
        guard !isRestoring else { return }         // reuse your restore lock
        isRestoring = true
        defer { isRestoring = false }

        do {
            // Provide a range loader in FirebaseService
            let missing = try await FirebaseService.shared
                .loadGameActions(sequenceGreaterThanOrEqual: start,
                                 sequenceLessThanOrEqual: end)

            // Defensive sort in case of any server-side quirks
            let ordered = missing.sorted { $0.sequence < $1.sequence }

            let total = ordered.count
            var processed = 0
            self.restorationProgress = 0.0

            for a in ordered {
                if a.sequence == lastAppliedSequence + 1 {
                    handleReceivedAction(a)
                } else if a.sequence > lastAppliedSequence + 1 {
                    // still a hole → keep waiting; this can happen if end == nil and writes lag
                    buffered[a.sequence] = a
                } // else duplicate → skip
                processed += 1
                self.restorationProgress = Double(processed) / Double(max(total,1))
            }

            // After catch-up, drain any buffered consecutive actions
            while let next = buffered[lastAppliedSequence + 1] {
                buffered.removeValue(forKey: lastAppliedSequence + 1)
                handleReceivedAction(next)
                processed += 1
                self.restorationProgress = Double(processed) / Double(max(total,1))
            }

            self.restorationProgress = 1.0
        } catch {
            logger.log("Catch-up failed: \(error.localizedDescription)")
            self.restorationProgress = 0.0
        }
    }
}
