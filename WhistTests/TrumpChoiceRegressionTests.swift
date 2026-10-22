import Foundation
import Testing
@testable import Whist

@Suite(.serialized)
@MainActor
struct TrumpChoiceRegressionTests {
    @Test func lastPlayerCanReviseTrumpWhenThereIsNoSecondPlayer() throws {
        let manager = makeManager()
        let trump = try #require(manager.gameState.trumpCards.last)
        for phase in [GamePhase.bidding, .discard] {
            manager.gameState.currentPhase = phase
            manager.gameState.getPlayer(by: .gg).place = 1
            #expect(manager.canCancelTrumpChoice(byTapping: trump))
            manager.gameState.getPlayer(by: .gg).place = 2
            #expect(!manager.canCancelTrumpChoice(byTapping: trump))
        }
    }

    @Test func firstPlayersCannotCancelAndSecondPlayerKeepsExistingBehavior() throws {
        let manager = makeManager()
        let local = try #require(manager.gameState.localPlayer)
        let trump = try #require(manager.gameState.trumpCards.last)
        manager.gameState.currentPhase = .discard
        local.place = 1
        #expect(!manager.canCancelTrumpChoice(byTapping: trump))
        local.place = 2
        #expect(manager.canCancelTrumpChoice(byTapping: trump))
        manager.gameState.currentPhase = .bidding
        #expect(!manager.canCancelTrumpChoice(byTapping: trump))
    }

    @Test func onlyTheSelectedTrumpCanBeCancelledBeforeDiscarding() throws {
        let manager = makeManager()
        let trump = try #require(manager.gameState.trumpCards.last)
        #expect(!manager.canCancelTrumpChoice(byTapping: Card(suit: .spades, rank: .two)))
        #expect(!manager.canCancelTrumpChoice(byTapping: Card(suit: .hearts, rank: .ace)))
        manager.gameState.localPlayer?.hasDiscarded = true
        #expect(!manager.canCancelTrumpChoice(byTapping: trump))
        manager.gameState.localPlayer?.hasDiscarded = false
        manager.gameState.trumpSuit = nil
        #expect(!manager.canCancelTrumpChoice(byTapping: trump))
    }

    @Test func trumpCannotBeCancelledOutsideTheDecisionWindow() throws {
        let manager = makeManager()
        let trump = try #require(manager.gameState.trumpCards.last)
        for phase in [GamePhase.choosingTrump, .waitingForTrump, .playingTricks, .grabTrick, .scoring] {
            manager.gameState.currentPhase = phase
            #expect(!manager.canCancelTrumpChoice(byTapping: trump))
        }
    }

    @Test(arguments: PlayerId.allCases)
    func cancelledChoiceReturnsAllFourTrumpsAndAcceptsAReplacement(localID: PlayerId) throws {
        let manager = makeManager(localID: localID)
        defer { manager.cancelSlowpokeTimer() }
        manager.isRestoring = true // Apply card moves synchronously, as during replay.
        manager.receiveOrderedAction(action(.cancelTrump, from: localID, sequence: 1))

        #expect(manager.gameState.trumpSuit == nil)
        #expect(manager.gameState.currentPhase == .choosingTrump)
        #expect(manager.gameState.table.count == 4)
        #expect(Set(manager.gameState.table.map(\.id)).count == 4)
        #expect(manager.gameState.trumpCards.isEmpty)
        let replacement = try #require(manager.gameState.table.first { $0.suit == .spades })
        manager.receiveOrderedAction(action(.choseTrump, from: localID, sequence: 2,
                                            payload: try JSONEncoder().encode(replacement)))

        #expect(manager.gameState.trumpSuit == .spades)
        #expect(manager.gameState.currentPhase == .bidding)
        #expect(manager.gameState.table.isEmpty)
        #expect(manager.gameState.trumpCards.count == 4)
        #expect(Set(manager.gameState.trumpCards.map(\.id)).count == 4)
        #expect(manager.lastAppliedSequence == 2)
        #expect(manager.gameState.players.allSatisfy { $0.announcedTricks.count == 3 })
    }

    @Test func replacementDuringDiscardPreservesBidsAndReturnsToDiscard() throws {
        let manager = makeManager()
        defer { manager.cancelSlowpokeTimer() }
        manager.gameState.currentPhase = .discard
        manager.gameState.players.forEach {
            $0.announcedTricks.append(1)
            $0.madeTricks.append(0)
        }
        manager.isRestoring = true
        manager.receiveOrderedAction(action(.cancelTrump, from: .dd, sequence: 1))
        let replacement = try #require(manager.gameState.table.first { $0.suit == .clubs })
        manager.receiveOrderedAction(action(.choseTrump, from: .dd, sequence: 2,
                                            payload: try JSONEncoder().encode(replacement)))

        #expect(manager.gameState.trumpSuit == .clubs)
        #expect(manager.gameState.currentPhase == .discard)
        #expect(manager.gameState.players.allSatisfy { $0.announcedTricks == [0, 0, 0, 1] })
        #expect(manager.gameState.localPlayer?.hasDiscarded == false)
    }

    @Test func firstPlayerReceivesCancellationAndReplacementWithoutChoosingTrump() throws {
        let manager = makeManager(localID: .gg)
        defer { manager.cancelSlowpokeTimer() }
        manager.gameState.getPlayer(by: .gg).place = 1
        manager.gameState.getPlayer(by: .dd).place = 3
        manager.gameState.getPlayer(by: .gg).scores = [10, 10, 10]
        manager.gameState.getPlayer(by: .dd).scores = [0, 0, 0]
        manager.isRestoring = true
        manager.receiveOrderedAction(action(.cancelTrump, from: .dd, sequence: 1))
        #expect(manager.gameState.trumpSuit == nil)
        #expect(manager.gameState.currentPhase == .bidding)
        #expect(manager.gameState.table.isEmpty)
        manager.receiveOrderedAction(action(.choseTrump, from: .dd, sequence: 2,
                                            payload: try JSONEncoder().encode(Card(suit: .spades, rank: .two))))
        #expect(manager.gameState.trumpSuit == .spades)
        #expect(manager.gameState.currentPhase == .bidding)
    }

    private func action(_ type: GameAction.ActionType, from playerID: PlayerId,
                        sequence: Int, payload: Data = Data()) -> GameAction {
        GameAction(playerId: playerID, type: type, payload: payload, timestamp: Double(sequence),
                   sequence: sequence,
                   context: GameAction.Context(round: 4, trickIndex: nil, turnIndex: nil, phase: .bidding))
    }

    private func makeManager(localID: PlayerId = .dd) -> GameManager {
        let manager = GameManager(connectionManager: .shared, signalingManager: .shared, preferences: Preferences())
        manager.gameState.round = 4
        manager.gameState.currentPhase = .bidding
        manager.gameState.trumpSuit = .hearts
        manager.gameState.trumpCards.last?.isFaceDown = false
        manager.gameState.playOrder = [localID] + PlayerId.allCases.filter { $0 != localID }
        for (index, id) in manager.gameState.playOrder.enumerated() {
            let player = manager.gameState.getPlayer(by: id)
            player.tablePosition = [TablePosition.local, .left, .right][index]
            player.place = id == localID ? 3 : 1
            player.scores = id == localID ? [0, 0, 0] : [10, 10, 10]
            player.announcedTricks = [0, 0, 0]
            player.madeTricks = [0, 0, 0]
            player.hand = [Card(suit: .hearts, rank: .seven), Card(suit: .clubs, rank: .ace)]
            if id == localID { player.hand.append(Card(suit: .spades, rank: .king)) }
        }
        return manager
    }
}
