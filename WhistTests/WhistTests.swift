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

}
