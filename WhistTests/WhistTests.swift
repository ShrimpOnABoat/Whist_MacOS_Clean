//
//  WhistTests.swift
//  WhistTests
//
//  Created by Tony Buffard on 2024-12-14.
//

import Foundation
import Testing
@testable import Whist

struct WhistTests {

    @Test func defaultGameStateCreatesThreeKnownPlayers() {
        let state = GameState()

        #expect(state.players.map(\.id) == [.dd, .gg, .toto])
        #expect(state.players.allSatisfy { !$0.firebasePresenceOnline })
        #expect(state.round == 0)
        #expect(state.currentPhase == .waitingForPlayers)
    }

    @Test @MainActor func initializedDeckContainsThirtyTwoNonTrumpCardsAndFourTrumpTwos() {
        let manager = makeGameManager()

        manager.initializeCards()

        #expect(manager.gameState.deck.count == 32)
        #expect(manager.gameState.trumpCards.count == 4)
        #expect(manager.gameState.deck.allSatisfy { $0.rank != .two })
        #expect(Set(manager.gameState.deck.map(\.id)).count == 32)
        #expect(Set(manager.gameState.trumpCards.map(\.id)) == [
            "clubs_2",
            "spades_2",
            "diamonds_2",
            "hearts_2"
        ])
    }

    @Test @MainActor func gameStateIntegrityAcceptsCompleteInitializedGame() {
        let manager = makeGameManager()
        manager.gameState.playOrder = [.dd, .gg, .toto]
        manager.gameState.dealer = .dd

        manager.initializeCards()

        #expect(manager.gameState.checkIntegrity().isEmpty)
    }

    @Test @MainActor func gameStateIntegrityReportsMissingDealerAndPlayOrder() {
        let manager = makeGameManager()

        manager.initializeCards()

        let errors = manager.gameState.checkIntegrity()
        #expect(errors.contains("Dealer is not defined."))
        #expect(errors.contains { $0.contains("playOrder") })
    }

    @Test func cardCodingPreservesIdentityAndAnimationType() throws {
        let card = Card(suit: .hearts, rank: .ace)
        card.playAnimationType = .impact

        let data = try JSONEncoder().encode(card)
        let decoded = try JSONDecoder().decode(Card.self, from: data)

        #expect(decoded.id == "hearts_ace")
        #expect(decoded.suit == .hearts)
        #expect(decoded.rank == .ace)
        #expect(decoded.playAnimationType == .impact)
        #expect(decoded.isFaceDown)
        #expect(!decoded.isPlayable)
    }

    @Test func actionPhaseRulesKeepPlayCardsInTrickPhaseOnly() {
        #expect(GameAction.ActionType.playCard.associatedPhases == [.playingTricks])
        #expect(GameAction.ActionType.playCard.associatedPhases.contains(.playingTricks))
        #expect(!GameAction.ActionType.playCard.associatedPhases.contains(.bidding))
        #expect(!GameAction.ActionType.playCard.associatedPhases.contains(.grabTrick))
    }

    @Test func administrativeActionsAreAcceptedInAnyPhase() {
        #expect(GameAction.ActionType.refreshSession.associatedPhases.isEmpty)
        #expect(GameAction.ActionType.sendState.associatedPhases.isEmpty)
        #expect(GameAction.ActionType.honk.associatedPhases.isEmpty)
        #expect(!GameAction.ActionType.refreshSession.isDurableOrdered)
        #expect(!GameAction.ActionType.sendState.isDurableOrdered)
        #expect(!GameAction.ActionType.honk.isDurableOrdered)
    }

    @Test func perfectGameBonusCountsOnePointPerPerfectGame() {
        let scores = [
            makeScore(ggConsecutiveWins: 12, ddConsecutiveWins: 11, totoConsecutiveWins: nil),
            makeScore(ggConsecutiveWins: 12, ddConsecutiveWins: 12, totoConsecutiveWins: 0)
        ]

        let bonuses = computePerfectGameCounts(for: 2026, scores: scores)

        #expect(bonuses.gg == 2)
        #expect(bonuses.dd == 1)
        #expect(bonuses.toto == 0)
    }

    @Test func perfectGameBonusIgnoresOtherYears() {
        let scores = [
            makeScore(year: 2026, ggConsecutiveWins: 12),
            makeScore(year: 2025, ggConsecutiveWins: 12)
        ]

        let bonuses = computePerfectGameCounts(for: 2026, scores: scores)

        #expect(bonuses.gg == 1)
        #expect(bonuses.dd == 0)
        #expect(bonuses.toto == 0)
    }

    @Test func annualSummaryAddsPerfectGameBonusToTotalsOnly() {
        let scores = [
            makeScore(
                ggScore: 100,
                ddScore: 80,
                totoScore: 40,
                ggPosition: 1,
                ddPosition: 2,
                totoPosition: 3,
                ggConsecutiveWins: 12
            )
        ]

        let summary = computeAnnualScoreSummary(for: 2026, scores: scores)

        #expect(summary.monthlySummaries.count == 1)
        #expect(summary.perfectGameBonuses.gg == 1)
        #expect(summary.total.gg == 3)
        #expect(summary.total.dd == 1)
        #expect(summary.total.toto == 0)
        #expect(summary.total.ggTally == 2)
        #expect(summary.total.ddTally == 1)
        #expect(summary.total.totoTally == 0)
    }

    @Test func isPerfectGameRequiresCompletedRoundCount() {
        #expect(isPerfectGame(consecutiveWins: 12))
        #expect(!isPerfectGame(consecutiveWins: 11))
        #expect(!isPerfectGame(consecutiveWins: nil))
    }

    private func makeScore(
        year: Int = 2026,
        month: Int = 1,
        day: Int = 1,
        ggScore: Int = 0,
        ddScore: Int = 0,
        totoScore: Int = 0,
        ggPosition: Int? = nil,
        ddPosition: Int? = nil,
        totoPosition: Int? = nil,
        ggConsecutiveWins: Int? = nil,
        ddConsecutiveWins: Int? = nil,
        totoConsecutiveWins: Int? = nil
    ) -> GameScore {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
        return GameScore(
            date: date,
            ggScore: ggScore,
            ddScore: ddScore,
            totoScore: totoScore,
            ggPosition: ggPosition,
            ddPosition: ddPosition,
            totoPosition: totoPosition,
            ggConsecutiveWins: ggConsecutiveWins,
            ddConsecutiveWins: ddConsecutiveWins,
            totoConsecutiveWins: totoConsecutiveWins
        )
    }

    @MainActor
    private func makeGameManager() -> GameManager {
        GameManager(
            connectionManager: .shared,
            signalingManager: .shared,
            preferences: Preferences()
        )
    }

}
