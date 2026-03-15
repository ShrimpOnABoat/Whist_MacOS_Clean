//
//  Action.swift
//  Whist
//
//  Created by Tony Buffard on 2024-11-18.
//  Defines actions that can be taken in the game.

import Foundation

struct GameAction: Codable {
    struct Context: Codable {
        let round: Int
        let trickIndex: Int?
        let turnIndex: Int?
        let phase: GamePhase?
    }

    enum ActionType: String, Codable {
        case playOrder
        case playCard
        case sendDeck
        case discard
        case choseBet
        case choseTrump
        case cancelTrump
        case sendState
        case startNewGame
        case refreshSession
        case amSlowPoke
        case honk
        case dealer
        
        var associatedPhases: [GamePhase] {
            switch self {
            case .playOrder:
                // Accept playOrder not only in .setPlayOrder, but also in all phases
                // before the deck is sent/received for the new game.
                return [
                    .setPlayOrder,
                    .setupGame,
                    .waitingToStart,
                    .newGame,
                    .setupNewRound,
                    .waitingForDeck
                ]
            case .playCard:
                return [.playingTricks]
            case .sendDeck:
                return [.waitingForDeck]
            case .discard:
                return [.choosingTrump, .waitingForTrump, .bidding, .discard]
            case .choseBet:
                return [.choosingTrump, .waitingForTrump, .bidding, .discard]
            case .choseTrump:
                return [.choosingTrump, .waitingForTrump, .bidding, .discard]
            case .startNewGame:
                return [.waitingToStart]
            case .refreshSession:
                // Administrative reset action; must be accepted regardless of phase.
                return []
            default:
                // [] means "valid in any phase" with your current isActionValidInCurrentPhase logic.
                return []
            }
        }

        var isDurableOrdered: Bool {
            switch self {
            case .sendState, .refreshSession, .amSlowPoke, .honk:
                return false
            default:
                return true
            }
        }
    }
    let playerId: PlayerId
    let type: ActionType
    let payload: Data
    let timestamp: TimeInterval
    let sequence: Int
    let context: Context?
}

// Example of creating a playCard action
extension GameAction {
    static func playCardAction(playerId: PlayerId, card: Card, context: Context? = nil) -> GameAction {
        let payloadData = try! JSONEncoder().encode(card)
        return GameAction(
            playerId: playerId,
            type: .playCard,
            payload: payloadData,
            timestamp: Date().timeIntervalSince1970,
            sequence: 0,
            context: context
        )
    }
}
