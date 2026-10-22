import Foundation
import Testing
@testable import Whist

@MainActor
struct CodebaseRegressionTests {
    @Test func lateBidDoesNotBlockSubsequentMoves() throws {
        let manager = makeManager()
        defer { manager.cancelSlowpokeTimer() }
        manager.gameState.round = 4
        manager.gameState.currentPhase = .playingTricks
        manager.gameState.getPlayer(by: .dd).announcedTricks = [0, 0, 0, 1]
        let lateBid = try decision(.choseBet, round: 4, payload: JSONEncoder().encode(-1))
        manager.receiveOrderedAction(lateBid)
        manager.receiveOrderedAction(GameAction(playerId: .dd, type: .dealer,
            payload: try JSONEncoder().encode(PlayerId.gg), timestamp: 2, sequence: 2, context: nil))

        #expect(manager.lastAppliedSequence == 2)
        #expect(manager.pendingActions.isEmpty)
        #expect(manager.buffered.isEmpty)
        #expect(manager.gameState.getPlayer(by: .dd).announcedTricks == [0, 0, 0, 1])
    }

    @Test func lateTrumpCancellationCannotEraseTrumpDuringPlay() throws {
        let manager = makeManager()
        defer { manager.cancelSlowpokeTimer() }
        manager.gameState.round = 4
        manager.gameState.currentPhase = .playingTricks
        manager.gameState.trumpSuit = .hearts
        manager.receiveOrderedAction(try decision(.cancelTrump, round: 4))

        #expect(manager.gameState.trumpSuit == .hearts)
        #expect(manager.gameState.currentPhase == .playingTricks)
        #expect(manager.lastAppliedSequence == 1)
    }

    @Test func previousRoundsBidCannotChangeTheCurrentBid() throws {
        let manager = makeManager()
        defer { manager.cancelSlowpokeTimer() }
        manager.gameState.round = 5
        manager.gameState.currentPhase = .bidding
        manager.gameState.getPlayer(by: .dd).announcedTricks = [0, 0, 0, 1, 2]
        manager.receiveOrderedAction(try decision(.choseBet, round: 4, payload: JSONEncoder().encode(0)))

        #expect(manager.gameState.getPlayer(by: .dd).announcedTricks == [0, 0, 0, 1, 2])
        #expect(manager.lastAppliedSequence == 1)
    }

    @Test func restoredGatherCompletesAfterCardsAreBackInTheDeck() {
        let manager = makeManager()
        manager.isRestoring = true
        manager.initializeCards()
        manager.gameState.getPlayer(by: .dd).trickCards = Array(manager.gameState.deck.suffix(3))
        manager.gameState.deck.removeLast(3)
        var deckCountAtCompletion = 0
        var trickCountAtCompletion = -1

        manager.gatherCards {
            deckCountAtCompletion = manager.gameState.deck.count
            trickCountAtCompletion = manager.gameState.getPlayer(by: .dd).trickCards.count
        }

        #expect(deckCountAtCompletion == 32)
        #expect(trickCountAtCompletion == 0)
        #expect(manager.gameState.deck.count == 32)
    }

    @Test func nonDealerUsesReceivedDeckWithoutAShuffleView() {
        let manager = makeManager()
        manager.gameState.deck = [Card(suit: .clubs, rank: .seven)]
        manager.gameState.newDeck = [Card(suit: .hearts, rank: .ace), Card(suit: .spades, rank: .king)]
        var completions = 0

        manager.shuffleCards(animationOnly: true) { completions += 1 }

        #expect(manager.gameState.deck.map(\.id) == manager.gameState.newDeck.map(\.id))
        #expect(completions == 1)
    }

    @Test func restoringLastSavedDealWaitsForAllCards() async throws {
        let manager = makeManager()
        defer { manager.cancelSlowpokeTimer(); manager.canCatchUp = false }
        manager.initializeCards()
        let deck = manager.gameState.deck
        let payload = GameAction.StartNewGamePayload(playOrder: [.dd, .gg, .toto], dealer: .dd,
                                                      sessionId: UUID().uuidString)
        manager.persistence = SavedActions([
            GameAction(playerId: .dd, type: .startNewGame, payload: try JSONEncoder().encode(payload),
                       timestamp: 1, sequence: 1, context: nil),
            GameAction(playerId: .toto, type: .sendDeck, payload: try JSONEncoder().encode(deck),
                       timestamp: 2, sequence: 2, context: nil)
        ])

        let restored = await manager.restoreGameFromActions()

        #expect(restored)
        #expect(!manager.isAwaitingActionCompletionDuringRestore)
        #expect(manager.gameState.currentPhase == .bidding)
        #expect(manager.gameState.players.allSatisfy { $0.hand.count == 1 })
        #expect(manager.gameState.trumpSuit != nil)
        #expect(manager.movingCards.isEmpty)
        try await Task.sleep(for: .milliseconds(100))
        #expect(manager.movingCards.isEmpty)
    }

    @Test func restoringLastSavedTrickFinishesScoringBeforeReturning() async throws {
        let manager = makeManager()
        defer { manager.cancelSlowpokeTimer(); manager.canCatchUp = false }
        manager.gameState.getPlayer(by: .dd).tablePosition = .right
        manager.gameState.getPlayer(by: .gg).tablePosition = .local
        manager.gameState.getPlayer(by: .toto).tablePosition = .left
        manager.initializeCards()
        let deck = manager.gameState.deck
        let payload = GameAction.StartNewGamePayload(playOrder: [.dd, .gg, .toto], dealer: .dd,
                                                      sessionId: UUID().uuidString)
        var actions = [
            GameAction(playerId: .dd, type: .startNewGame, payload: try JSONEncoder().encode(payload),
                       timestamp: 1, sequence: 1, context: nil),
            GameAction(playerId: .toto, type: .sendDeck, payload: try JSONEncoder().encode(deck),
                       timestamp: 2, sequence: 2, context: nil)
        ]
        for (index, id) in [PlayerId.dd, .gg, .toto].enumerated() {
            actions.append(GameAction(playerId: id, type: .choseBet, payload: try JSONEncoder().encode(0),
                                      timestamp: 3, sequence: 3 + index, context: nil))
        }
        for (index, id) in [PlayerId.dd, .gg, .toto].enumerated() {
            actions.append(GameAction(playerId: id, type: .playCard,
                                      payload: try JSONEncoder().encode(deck[deck.count - 1 - index]),
                                      timestamp: 6, sequence: 6 + index, context: nil))
        }
        manager.persistence = SavedActions(actions)

        #expect(await manager.restoreGameFromActions())

        #expect(manager.gameState.round == 2)
        #expect(manager.gameState.currentPhase == .waitingForDeck)
        #expect(manager.gameState.deck.count == 32)
        #expect(manager.gameState.players.allSatisfy { $0.scores.count == 1 && $0.trickCards.isEmpty })
        #expect(manager.gameState.players.reduce(0) { $0 + ($1.madeTricks.first ?? 0) } == 1)
        #expect(!manager.isAwaitingActionCompletionDuringRestore)
    }

    @Test func discardingAStalePendingDecisionReleasesBufferedMoves() throws {
        let manager = makeManager()
        defer { manager.cancelSlowpokeTimer() }
        manager.gameState.round = 4
        manager.gameState.currentPhase = .dealingCards
        manager.receiveOrderedAction(try decision(.choseBet, round: 4, payload: JSONEncoder().encode(0)))
        manager.receiveOrderedAction(GameAction(playerId: .dd, type: .dealer,
            payload: try JSONEncoder().encode(PlayerId.gg), timestamp: 2, sequence: 2, context: nil))
        #expect(manager.pendingActions.count == 1)
        manager.gameState.round = 5
        manager.gameState.currentPhase = .bidding

        _ = manager.processPendingActionsForCurrentPhase()

        #expect(manager.lastAppliedSequence == 2)
        #expect(manager.pendingActions.isEmpty)
        #expect(manager.buffered.isEmpty)
    }

    @Test func futureRoundsDecisionWaitsWithoutChangingTheCurrentRound() throws {
        let manager = makeManager()
        manager.gameState.round = 4
        manager.gameState.currentPhase = .playingTricks
        manager.receiveOrderedAction(try decision(.choseBet, round: 5, payload: JSONEncoder().encode(0)))
        #expect(manager.lastAppliedSequence == 0)
        #expect(manager.pendingActions.count == 1)
        #expect(manager.gameState.getPlayer(by: .dd).announcedTricks.isEmpty)
    }

    @Test func tournamentResultsDoNotChangeMonthlyBonusCards() throws {
        let calendar = Calendar(identifier: .gregorian)
        let august = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        let september = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        let regularGame = GameScore(date: august, ggScore: 30, ddScore: 20, totoScore: 10)
        let tournamentGame = GameScore(date: august, ggScore: 10, ddScore: 20, totoScore: 30,
                                      tournamentID: UUID(), tournamentName: "Vacances")

        let loser = ScoresManager.findLoser(in: [regularGame, tournamentGame, tournamentGame], asOf: september)

        #expect(loser?.playerId == .toto)
        #expect(loser?.losingMonths == 1)
        #expect(ScoresManager.findLoser(in: [tournamentGame], asOf: september) == nil)
    }

    @Test(arguments: [[1, 1, 3], [1, 2, 2], [1, 1, 1], [3, 1, 2]])
    func storedTiedRanksEarnTheSamePoints(ranks: [Int]) {
        let game = GameScore(date: Date(), ggScore: 100, ddScore: 100, totoScore: 100,
                             ggPosition: ranks[0], ddPosition: ranks[1], totoPosition: ranks[2])
        let points = calculateGamePoints(for: game)
        #expect([points.gg, points.dd, points.toto] == ranks.map { 3 - $0 })
    }

    @Test func unnamedTournamentStaysOutOfCalendarMonthStandings() throws {
        let date = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 10)))
        let game = GameScore(date: date, ggScore: 30, ddScore: 20, totoScore: 10, tournamentID: UUID())

        let summaries = computeMonthlySummaries(for: 2026, scores: [game])

        #expect(summaries.map(\.month) == ["Tournoi"])
        #expect(summaries.first?.ggPoints == 2)
    }

    private func decision(_ type: GameAction.ActionType, round: Int, payload: Data = Data()) throws -> GameAction {
        GameAction(playerId: .dd, type: type, payload: payload, timestamp: 1, sequence: 1,
                   context: GameAction.Context(round: round, trickIndex: nil, turnIndex: nil, phase: .bidding))
    }

    private func makeManager() -> GameManager {
        let manager = GameManager(connectionManager: .shared, signalingManager: .shared, preferences: Preferences())
        manager.gameState.playOrder = [.dd, .gg, .toto]
        manager.gameState.getPlayer(by: .dd).tablePosition = .local
        manager.gameState.getPlayer(by: .gg).tablePosition = .left
        manager.gameState.getPlayer(by: .toto).tablePosition = .right
        return manager
    }
}

private final class SavedActions: GamePersistence {
    let actions: [GameAction]
    init(_ actions: [GameAction]) { self.actions = actions; super.init() }
    override func loadGameActions() async -> [GameAction]? { actions }
}
