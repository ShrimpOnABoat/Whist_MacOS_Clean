import Foundation

struct AnnualChampion: Equatable {
    let playerId: PlayerId
    let year: Int

    init?(year: Int, scores: [GameScore]) {
        let summary = computeAnnualScoreSummary(for: year, scores: scores)
        guard let winner = summary.champion else { return nil }
        self.playerId = winner
        self.year = year
    }
}
