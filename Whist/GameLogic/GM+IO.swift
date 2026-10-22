//
//  GM+IO.swift
//  Whist
//
//  Created by Tony Buffard on 2024-12-01.
//

import Foundation
import SwiftUI
import AppKit
import FirebaseFirestore

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
    private enum OrderedActionDisposition {
        case apply
        case deferUntilReady(String)
        case ignoreAsStale(String)
    }

    private func registerLocalActionCompletion(_ completion: @escaping () -> Void, for sequence: Int) {
        localActionCompletions[sequence] = completion
    }

    private func consumeLocalActionCompletion(for sequence: Int) -> (() -> Void) {
        localActionCompletions.removeValue(forKey: sequence) ?? {}
    }

    private func processImmediately(_ action: GameAction) {
        processAction(action)
        if action.type != .sendState {
            checkAndAdvanceStateIfNeeded()
        }
    }

    private func appendPendingAction(_ action: GameAction) {
        if action.type.isDurableOrdered,
           pendingActions.contains(where: { $0.type.isDurableOrdered && $0.sequence == action.sequence }) {
            logger.log("Ignoring duplicate pending action \(action.type) seq \(action.sequence)")
            return
        }
        pendingActions.append(action)
    }

    private func makeActionContext(for type: GameAction.ActionType, playerId: PlayerId) -> GameAction.Context? {
        switch type {
        case .playCard:
            return GameAction.Context(
                round: gameState.round,
                trickIndex: gameState.currentTrick,
                turnIndex: gameState.table.count,
                phase: gameState.currentPhase
            )
        case .sendDeck, .discard, .choseBet, .choseTrump, .cancelTrump, .startNewGame, .playOrder, .dealer:
            return GameAction.Context(
                round: gameState.round,
                trickIndex: nil,
                turnIndex: nil,
                phase: gameState.currentPhase
            )
        default:
            return nil
        }
    }

    private func playCardDisposition(_ action: GameAction) -> OrderedActionDisposition {
        if let context = action.context {
            if context.round < gameState.round {
                return .ignoreAsStale("playCard targets round \(context.round), but local round is \(gameState.round)")
            }
            if context.round > gameState.round {
                return .deferUntilReady("playCard targets future round \(context.round), local round is \(gameState.round)")
            }

            if let trickIndex = context.trickIndex {
                if trickIndex < gameState.currentTrick {
                    return .ignoreAsStale("playCard targets trick \(trickIndex), but local trick is \(gameState.currentTrick)")
                }
                if trickIndex > gameState.currentTrick {
                    return .deferUntilReady("playCard targets future trick \(trickIndex), local trick is \(gameState.currentTrick)")
                }
            }

            if let turnIndex = context.turnIndex {
                let expectedTurnIndex = gameState.table.count
                if turnIndex < expectedTurnIndex {
                    return .ignoreAsStale("playCard targets turn \(turnIndex), but local table already contains \(expectedTurnIndex) cards")
                }
                if turnIndex > expectedTurnIndex {
                    return .deferUntilReady("playCard targets future turn \(turnIndex), local table is at turn \(expectedTurnIndex)")
                }
            }
        }

        guard let playerIndex = gameState.playOrder.firstIndex(of: action.playerId) else {
            return .apply
        }

        if gameState.currentPhase == .grabTrick || isAwaitingActionCompletionDuringRestore {
            return .deferUntilReady("currentPhase = \(gameState.currentPhase)")
        }

        if gameState.table.indices.contains(playerIndex) {
            return .ignoreAsStale("player \(action.playerId.rawValue) already occupies table slot \(playerIndex)")
        }

        return .apply
    }

    func isActionReadyForCurrentPhase(_ action: GameAction) -> Bool {
        let isDealersOwnDeck = action.type == .sendDeck &&
            action.playerId == gameState.localPlayer?.id && gameState.currentPhase == .dealingCards
        return isActionValidInCurrentPhase(action.type) || isDealersOwnDeck
    }

    private func orderedActionDisposition(for action: GameAction) -> OrderedActionDisposition {
        switch action.type {
        case .choseBet, .choseTrump, .cancelTrump, .discard:
            if let context = action.context {
                if context.round < gameState.round {
                    return .ignoreAsStale("decision targets a completed round \(context.round)")
                }
                if context.round > gameState.round {
                    return .deferUntilReady("decision targets future round \(context.round)")
                }
            }
            switch gameState.currentPhase {
            case .showCard, .playingTricks, .grabTrick, .scoring, .gameOver, .waitingToStart:
                // A second click can commit after the final bid has started play.
                // Consume its sequence without changing an already locked decision.
                return .ignoreAsStale("bidding and discarding have already ended")
            default:
                break
            }
        default:
            break
        }
        if action.type == .playCard {
            let disposition = playCardDisposition(action)
            if case .apply = disposition {} else { return disposition }
        }
        if !isActionReadyForCurrentPhase(action) {
            return .deferUntilReady("waiting for a phase that accepts \(action.type)")
        }
        return .apply
    }

    func shouldDeferOrderedAction(_ action: GameAction) -> Bool {
        if case .deferUntilReady = orderedActionDisposition(for: action) {
            return true
        }
        return false
    }

    func shouldIgnoreOrderedAction(_ action: GameAction) -> Bool {
        if case .ignoreAsStale = orderedActionDisposition(for: action) {
            return true
        }
        return false
    }

    private func applyReceivedOrderedAction(_ action: GameAction) {
        if shouldHoldActionBehindDeferredNewGame(action) {
            buffered[action.sequence] = action
            logger.log("Holding ordered action \(action.type) seq \(action.sequence) until local player joins deferred new game.")
            return
        }

        switch orderedActionDisposition(for: action) {
        case .deferUntilReady(let reason):
            appendPendingAction(action)
            logger.log("Deferring ordered action \(action.type) seq \(action.sequence) until runtime state is ready: \(reason)")
            return
        case .ignoreAsStale(let reason):
            lastAppliedSequence = max(lastAppliedSequence, action.sequence)
            localActionCompletions.removeValue(forKey: action.sequence)
            logger.log("Ignoring stale ordered action \(action.type) seq \(action.sequence): \(reason)")
            return
        case .apply:
            break
        }

        processImmediately(action)
    }

    private func shouldHoldActionBehindDeferredNewGame(_ action: GameAction) -> Bool {
        guard hasDeferredStartNewGame,
              gameState.currentPhase == .waitingToStart,
              let deferredStartNewGameSequence,
              action.sequence > deferredStartNewGameSequence else {
            return false
        }

        return action.type.isDurableOrdered
    }

    func releaseActionsHeldBehindDeferredNewGame() {
        deferredStartNewGameSequence = nil
        promoteReadyBufferedOrderedActionsToPending()
    }

    func promoteReadyBufferedOrderedActionsToPending() {
        var nextSequence = lastAppliedSequence + 1
        while let nextAction = buffered[nextSequence] {
            buffered.removeValue(forKey: nextAction.sequence)
            appendPendingAction(nextAction)
            logger.log("Promoted buffered action \(nextAction.type) seq \(nextAction.sequence) to pending queue.")
            nextSequence += 1
        }
    }

    private func drainBufferedOrderedActions() {
        while let nextAction = buffered[lastAppliedSequence + 1] {
            if shouldHoldActionBehindDeferredNewGame(nextAction) {
                logger.log("Stopping buffered drain at \(nextAction.type) seq \(nextAction.sequence) until local player joins deferred new game.")
                return
            }

            buffered.removeValue(forKey: nextAction.sequence)
            logger.log("Draining buffered action \(nextAction.type) seq \(nextAction.sequence)")
            applyReceivedOrderedAction(nextAction)
        }
    }

    func receiveOrderedAction(_ action: GameAction) {
        if action.sequence <= lastAppliedSequence {
            logger.log("Ignoring stale/duplicate action \(action.type) seq \(action.sequence); lastAppliedSequence=\(lastAppliedSequence)")
            return
        }

        let expectedSequence = lastAppliedSequence + 1
        if action.sequence > expectedSequence {
            if buffered[action.sequence] == nil {
                buffered[action.sequence] = action
                logger.log("Buffered out-of-order action \(action.type) seq \(action.sequence); expected seq \(expectedSequence)")
            }
            scheduleCatchUp(reason: "Gap detected before seq \(action.sequence)")
            return
        }

        applyReceivedOrderedAction(action)
        drainBufferedOrderedActions()
    }
    
    struct PlayerIdentification: Codable {
        let id: PlayerId
        let username: String
    }

    // MARK: - Sequencing helpers
    private func buildTransientAction(type: GameAction.ActionType, payload: Data, playerId: PlayerId) -> GameAction? {
        guard !isRestoring else { return nil }
        return GameAction(
            playerId: playerId,
            type: type,
            payload: payload,
            timestamp: Date().timeIntervalSince1970,
            sequence: 0,
            context: makeActionContext(for: type, playerId: playerId)
        )
    }

    func commitActionWithSequence(type: GameAction.ActionType, payload: Data, playerId: PlayerId) async -> GameAction? {
        guard !isRestoring else { return nil }
        let generation = actionSyncGeneration
        let documentID = UUID().uuidString
        // Freeze the intended round/turn before waiting for the connection.
        let draft = GameAction(playerId: playerId, type: type, payload: payload,
                               timestamp: Date().timeIntervalSince1970, sequence: 0,
                               context: makeActionContext(for: type, playerId: playerId))
        localActionCommitsInFlight += 1
        defer { localActionCommitsInFlight -= 1 }

        for attempt in 0..<6 {
            guard !Task.isCancelled, generation == actionSyncGeneration else { return nil }
            do {
                let action = try await actionStore.commitGameAction(draft, documentID: documentID)
                guard generation == actionSyncGeneration else { return nil }
                return action
            } catch {
                logger.log("Action commit failed (attempt \(attempt + 1)/6): \(error.localizedDescription)")
                let error = error as NSError
                let retryableCodes = [FirestoreErrorCode.unavailable.rawValue,
                                      FirestoreErrorCode.deadlineExceeded.rawValue,
                                      FirestoreErrorCode.aborted.rawValue]
                guard error.domain == FirestoreErrorDomain,
                      retryableCodes.contains(error.code), attempt < 5 else { return nil }
                do {
                    try await Task.sleep(nanoseconds: UInt64(min(0.1 * pow(2, Double(attempt)), 2) * 1_000_000_000))
                } catch { return nil }
            }
        }
        return nil
    }

    private func commitActionWithSequence(type: GameAction.ActionType, payload: Data, playerId: PlayerId, onFailed: (() -> Void)? = nil, completion: @escaping (GameAction) -> Void) {
        guard !isRestoring else { return }
        Task {
            guard let action = await commitActionWithSequence(type: type, payload: payload, playerId: playerId) else {
                onFailed?()
                return
            }
            // Register local animation callbacks before catch-up can deliver this action.
            completion(action)
        }
    }

    // MARK: - handleReceivedAction
    
    func handleReceivedAction(_ action: GameAction) {
        logger.log("Handling action \(action.type) from \(action.playerId)")
        DispatchQueue.main.async {
            if action.type.isDurableOrdered {
                self.receiveOrderedAction(action)
            } else if self.isActionValidInCurrentPhase(action.type) {
                self.processImmediately(action)
            } else {
                self.appendPendingAction(action)
                logger.log("Stored transient action \(action.type) from \(action.playerId) for later because currentPhase = \(self.gameState.currentPhase)")
            }
        }
    }
    
    func processAction(_ action: GameAction) {
        logger.log("Processing action \(action.type) from player \(action.playerId)...")
        
        if action.type.isDurableOrdered {
            lastAppliedSequence = max(action.sequence, lastAppliedSequence)
            logger.log("lastAppliedSequence is now: \(lastAppliedSequence)")
        }
        
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
            self.updateGameStateWithPlayedCard(from: action.playerId, with: card, completion: consumeLocalActionCompletion(for: action.sequence))
            
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
                self.trackTrumpSelection(playerId: action.playerId, suit: trumpCard.suit)
                self.updateGameStateWithTrump(from: action.playerId, with: trumpCard)
                consumeLocalActionCompletion(for: action.sequence)()
            } else {
                logger.log("Failed to decode trump suit.")
            }
            
        case .cancelTrump:
            logger.log("Received cancellation of trump suit")
            self.trackTrumpCancellation()
            self.updateGameStateWithTrumpCancellation()
            
        case .discard:
            logger.log("Received discard")
            if let discardedCards = try? JSONDecoder().decode([Card].self, from: action.payload) {
                self.updateGameStateWithDiscardedCards(from: action.playerId, with: discardedCards, completion: consumeLocalActionCompletion(for: action.sequence))
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
            let payload = try? JSONDecoder().decode(GameAction.StartNewGamePayload.self, from: action.payload)
            self.handleStartNewGameAction(from: action.playerId, sequence: action.sequence, payload: payload)

        case .refreshSession:
            logger.log("Received admin refresh session action")
            self.resetStateAndRestoreGame(preferFreshLobbyOnEmptyRestore: true)
            
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
    func sendPlayOrderToPlayers(_ playOrder: [PlayerId], onCommitted: (() -> Void)? = nil) {
        guard let localPlayerID = gameState.localPlayer?.id, localPlayerID == .toto else { return }

        if let playOrderData = try? JSONEncoder().encode(playOrder) {
            commitActionWithSequence(type: .playOrder, payload: playOrderData, playerId: localPlayerID, onFailed: {
                logger.log("Unable to build playOrder action. New game setup will not proceed.")
            }) { action in
                self.sendCommittedOrTransientAction(action, onCommitted: onCommitted)
            }
        } else {
            logger.log("Error: Failed to encode the play order")
        }
    }

    
    func sendDeckToPlayers(onCommitted: (() -> Void)? = nil, onFailed: (() -> Void)? = nil) {
        logger.log("Sending deck to players: \(gameState.deck)")
        // Ensure localPlayer is defined
        guard let localPlayer = gameState.localPlayer else {
            logger.log("Error: Local player is not defined")
            return
        }
        
        // Encode the filtered deck and create the action
        if let deckData = try? JSONEncoder().encode(gameState.deck) {
            commitActionWithSequence(type: .sendDeck, payload: deckData, playerId: localPlayer.id, onFailed: onFailed) { action in
                self.sendCommittedOrTransientAction(action, onCommitted: onCommitted)
            }
        } else {
            logger.log("Error: Failed to encode the deck cards")
            onFailed?()
        }
    }

    
    func sendPlayCardtoPlayers(_ card: Card, completion: @escaping () -> Void, onFailed: (() -> Void)? = nil) {
        logger.log("Sending play card \(card) to players")
        guard let localPlayer = gameState.localPlayer else {
            logger.log("Error: Local player is not defined")
            return
        }
        
        if let cardData = try? JSONEncoder().encode(card) {
            commitActionWithSequence(type: .playCard, payload: cardData, playerId: localPlayer.id, onFailed: onFailed) { action in
                self.registerLocalActionCompletion(completion, for: action.sequence)
                self.sendCommittedOrTransientAction(action)
            }
        } else {
            logger.log("Error: Failed to encode the card")
            onFailed?()
        }
    }
    
    func sendBetToPlayers(_ bet: Int, onFailed: (() -> Void)? = nil) {
        logger.log("Sending bet \(bet) to players")
        guard let localPlayer = gameState.localPlayer else {
            logger.log("Error: Local player is not defined")
            return
        }
        
        if let betData = try? JSONEncoder().encode(bet) {
            commitActionWithSequence(type: .choseBet, payload: betData, playerId: localPlayer.id, onFailed: onFailed) { action in
                self.sendCommittedOrTransientAction(action)
            }
        } else {
            logger.log("Error: Failed to encode the bet")
            onFailed?()
        }
    }
    
    func sendTrumpToPlayers(_ trump: Card, completion: @escaping () -> Void, onFailed: (() -> Void)? = nil) {
        logger.log("Sending trump \(trump) to players")
        guard let localPlayer = gameState.localPlayer else {
            logger.log("Error: Local player is not defined")
            return
        }
        
        if let trumpData = try? JSONEncoder().encode(trump) {
            commitActionWithSequence(type: .choseTrump, payload: trumpData, playerId: localPlayer.id, onFailed: onFailed) { action in
                self.registerLocalActionCompletion(completion, for: action.sequence)
                self.sendCommittedOrTransientAction(action)
            }
        } else {
            logger.log("Error: Failed to encode the trump card")
            onFailed?()
        }
    }
    
    func sendDiscardedCards(_ discardedCards: [Card], completion: @escaping () -> Void, onFailed: (() -> Void)? = nil) {
        logger.log("Sending discarded cards \(discardedCards) to players")
        guard let localPlayer = gameState.localPlayer else {
            logger.log("Error: Local player is not defined")
            return
        }
        
        if let discardedCardsData = try? JSONEncoder().encode(discardedCards) {
            commitActionWithSequence(type: .discard, payload: discardedCardsData, playerId: localPlayer.id, onFailed: onFailed) { action in
                self.registerLocalActionCompletion(completion, for: action.sequence)
                self.sendCommittedOrTransientAction(action)
            }
        } else {
            logger.log("Error: Failed to encode the trump card")
            onFailed?()
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
        // Keep the latest status available even when a peer's data channel is
        // unavailable or opens after this transition.
        PresenceManager.shared.publishPlayerState(state)
        logger.log("Sending new state \(state.message) to players")
        
        if let stateData = try? JSONEncoder().encode(state),
           let action = buildTransientAction(type: .sendState, payload: stateData, playerId: localPlayer.id) {
            if !isRestoring {
                self.sendCommittedOrTransientAction(action)
            }
        } else {
            logger.log("Error: Failed to encode player's state")
        }
    }
    
    func sendStartNewGameAction(onCommitted: (() -> Void)? = nil) {
        logger.log("Sending start new game action to players")
        guard let localPlayer = gameState.localPlayer else { return }
        guard !gameState.playOrder.isEmpty else {
            logger.log("Unable to send startNewGame: playOrder is empty.")
            return
        }
        guard let dealer = gameState.dealer else {
            logger.log("Unable to send startNewGame: dealer is not defined.")
            return
        }

        let payload = GameAction.StartNewGamePayload(
            playOrder: gameState.playOrder,
            dealer: dealer,
            sessionId: UUID().uuidString
        )

        guard let payloadData = try? JSONEncoder().encode(payload) else {
            logger.log("Unable to encode startNewGame payload.")
            return
        }

        self.commitActionWithSequence(type: .startNewGame, payload: payloadData, playerId: localPlayer.id, onFailed: {
            logger.log("Unable to build startNewGame action.")
        }) { action in
            self.sendCommittedOrTransientAction(action, onCommitted: onCommitted)
        }
    }
    
    func sendRefreshSessionAction() {
        guard let localPlayer = gameState.localPlayer else { return }
        let action = GameAction(
            playerId: localPlayer.id,
            type: .refreshSession,
            payload: Data(),
            timestamp: Date().timeIntervalSince1970,
            sequence: 0,
            context: nil
        )

        if let actionData = try? JSONEncoder().encode(action),
           let messageString = String(data: actionData, encoding: .utf8) {
            let sent = connectionManager.sendMessage(messageString)
            if sent {
                logger.log("Sent refresh session action to other players")
            } else {
                logger.log("Failed to send refresh session action (some channels might not be open)")
            }
        } else {
            logger.log("Failed to encode refresh session action")
        }
    }
    
    func sendCancelTrumpChoice(onFailed: (() -> Void)? = nil) {
        logger.log("Sending cancel trump choice action to players")
        guard let localPlayer = gameState.localPlayer else {
            logger.log("Error: Local player is not defined")
            return
        }
        
        commitActionWithSequence(type: .cancelTrump, payload: Data(), playerId: localPlayer.id, onFailed: onFailed) { action in
            self.sendCommittedOrTransientAction(action)
        }
    }
    
    func sendAmSlowPoke() {
        logger.log("Sending I'm a slowpoke signal to players")
        guard let localPlayer = gameState.localPlayer else {
            logger.log("Error: Local player is not defined")
            return
        }
        
        guard let action = buildTransientAction(type: .amSlowPoke, payload: Data(), playerId: localPlayer.id) else {
            return
        }
        self.sendCommittedOrTransientAction(action)
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
        
        guard let action = buildTransientAction(type: .honk, payload: Data(), playerId: localPlayer.id) else {
            return
        }
        self.sendCommittedOrTransientAction(action)
        
        playSound(named: "pouet")
    }
    
    func persistOrderAndDealer() async -> Bool {
        guard gameState.playOrder != [] else {
            logger.log("No playOrder defined")
            return false
        }
        guard gameState.dealer != nil else {
            logger.log( "No dealer defined")
            return false
        }
        guard let localPlayer = gameState.localPlayer else {
            logger.log("Error: Local player is not defined")
            return false
        }
        
        logger.log("Persisting playOrder and dealer before startNewGame")

        guard let playOrderData = try? JSONEncoder().encode(gameState.playOrder) else {
            logger.log("Error: Failed to encode the play order")
            return false
        }

        guard let dealerData = try? JSONEncoder().encode(gameState.dealer) else {
            logger.log("Error: Failed to encode the dealer")
            return false
        }

        guard let playOrderAction = await commitActionWithSequence(type: .playOrder, payload: playOrderData, playerId: localPlayer.id) else {
            logger.log("Failed to commit playOrder.")
            return false
        }

        guard let dealerAction = await commitActionWithSequence(type: .dealer, payload: dealerData, playerId: localPlayer.id) else {
            logger.log("Failed to commit dealer.")
            return false
        }

        logger.log("Persisted playOrder seq \(playOrderAction.sequence) and dealer seq \(dealerAction.sequence)")
        return true
    }
    
    func sendCommittedOrTransientAction(_ action: GameAction, onCommitted: (() -> Void)? = nil) {
        guard !isRestoring else { return }
        do {
            let data = try JSONEncoder().encode(action)
            if let message = String(data: data, encoding: .utf8) {
                let sent = connectionManager.sendMessage(message)
                logger.log("P2P delivery of \(action.type) seq \(action.sequence): \(sent ? "sent" : "server recovery available")")
            }
        } catch {
            logger.log("Could not encode P2P action: \(error.localizedDescription)")
        }
        // A P2P failure cannot undo an acknowledged server commit.
        if action.type.isDurableOrdered {
            receiveOrderedAction(action)
            onCommitted?()
        }
    }

}
