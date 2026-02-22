//
//  GM+Insights.swift
//  Whist
//
//  Created by Codex on 2026-02-21.
//

import Foundation

struct GameInsightFact: Codable, Identifiable {
    let id: String
    let metricKey: String
    let category: String
    let value: Double
    let rarityScore: Double
    let text: String
}

struct GameInsightsSummary: Codable {
    let id: String
    let createdAt: Date
    let winner: PlayerId?
    let topFacts: [GameInsightFact]
    let allFacts: [GameInsightFact]?
    let metrics: [String: Double]
}

struct TrumpChoiceConcentrationRecord {
    let round: Int
    let playerId: PlayerId
    let suit: Suit
    let concentration: Double
}

struct GameInsightMetricStats: Codable {
    let key: String
    let count: Int
    let min: Double
    let max: Double
    let mean: Double
    let m2: Double
    let updatedAt: Date

    init(key: String,
         count: Int = 0,
         min: Double = .infinity,
         max: Double = -.infinity,
         mean: Double = 0,
         m2: Double = 0,
         updatedAt: Date = Date()) {
        self.key = key
        self.count = count
        self.min = min
        self.max = max
        self.mean = mean
        self.m2 = m2
        self.updatedAt = updatedAt
    }

    var variance: Double {
        guard count > 1 else { return 0 }
        return m2 / Double(count - 1)
    }

    func updating(with value: Double) -> GameInsightMetricStats {
        let newCount = count + 1
        let delta = value - mean
        let newMean = mean + delta / Double(newCount)
        let delta2 = value - newMean
        let newM2 = m2 + delta * delta2
        let newMin = Swift.min(min, value)
        let newMax = Swift.max(max, value)
        return GameInsightMetricStats(
            key: key,
            count: newCount,
            min: newMin,
            max: newMax,
            mean: newMean,
            m2: newM2,
            updatedAt: Date()
        )
    }
}

private enum InsightDirection {
    case high
    case low
}

private struct InsightSample {
    let key: String
    let category: String
    let value: Double
    let direction: InsightDirection
    let text: String
}

extension GameManager {
    func resetInsightsTrackingForNewGame() {
        trumpSelectionsBySuit = [:]
        trumpSelectionsByPlayer = [:]
        trumpCancelCount = 0
        roundFirstBettor = [:]
        roundDifficultyByPlayer = [:]
        roundMidCardDensityByPlayer = [:]
        randomBetByPlayer = [:]
        randomBetRecordedByRound = []
        trumpChoiceConcentrationRecords = []
        trackedDifficultyRounds = []
        latestGameInsightFacts = []
        latestGameAllInsightFacts = []
    }

    func trackTrumpSelection(playerId: PlayerId, suit: Suit) {
        trumpSelectionsBySuit[suit, default: 0] += 1
        var byPlayer = trumpSelectionsByPlayer[playerId, default: [:]]
        byPlayer[suit, default: 0] += 1
        trumpSelectionsByPlayer[playerId] = byPlayer

        let hand = gameState.getPlayer(by: playerId).hand
        let concentration = suitConcentration(in: hand, targetSuit: suit)
        trumpChoiceConcentrationRecords.append(
            TrumpChoiceConcentrationRecord(
                round: gameState.round,
                playerId: playerId,
                suit: suit,
                concentration: concentration
            )
        )
    }

    func trackTrumpCancellation() {
        trumpCancelCount += 1
    }

    func trackRoundDifficultySnapshotIfNeeded() {
        let round = gameState.round
        guard round > 0 else { return }
        guard !trackedDifficultyRounds.contains(round) else { return }
        guard gameState.currentPhase == .bidding else { return }

        var difficultyByPlayer: [PlayerId: Double] = [:]
        var midDensityByPlayer: [PlayerId: Double] = [:]
        for player in gameState.players {
            let hand = player.hand
            guard !hand.isEmpty else { continue }
            let midDensity = midCardDensity(in: hand)
            let maxSuitConcentration = dominantSuitConcentration(in: hand)
            let difficulty = handDifficultyIndex(midDensity: midDensity, dominantSuitConcentration: maxSuitConcentration)
            difficultyByPlayer[player.id] = difficulty
            midDensityByPlayer[player.id] = midDensity
        }
        roundDifficultyByPlayer[round] = difficultyByPlayer
        roundMidCardDensityByPlayer[round] = midDensityByPlayer
        trackedDifficultyRounds.insert(round)
    }

    func trackRandomBetIfEligible(playerId: PlayerId, round: Int) {
        guard round > 3 else { return }
        guard !randomBetRecordedByRound.contains(round) else { return }
        guard roundFirstBettor[round] == playerId else { return }
        guard isRandomBetModeEligible(for: playerId, round: round) else { return }

        randomBetByPlayer[playerId, default: 0] += 1
        randomBetRecordedByRound.insert(round)
    }

    func refreshLatestGameInsights() async {
        var loaded: GameInsightsSummary?
        for attempt in 0..<3 {
            loaded = try? await FirebaseService.shared.loadLatestGameInsights()
            if loaded != nil { break }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
        if let expectedWinner = lastGameWinner,
           let loadedWinner = loaded?.winner,
           loadedWinner == expectedWinner {
            latestGameInsightFacts = loaded?.topFacts ?? []
            latestGameAllInsightFacts = loaded?.allFacts ?? loaded?.topFacts ?? []
        } else {
            latestGameInsightFacts = []
            latestGameAllInsightFacts = []
        }
    }

    func publishInsightsSummaryForCurrentGame() async throws {
        let samples = buildInsightSamples()
        guard !samples.isEmpty else { return }

        let keys = Array(Set(samples.map(\.key)))
        let existingStats = try await FirebaseService.shared.loadGameInsightMetricStats(keys: keys)

        let rankedFacts = rankFacts(from: samples, using: existingStats)
        let topFacts = selectTopFacts(from: rankedFacts, maxCount: 3)
        let metrics = Dictionary(uniqueKeysWithValues: samples.map { ($0.key, $0.value) })
        let summary = GameInsightsSummary(
            id: UUID().uuidString,
            createdAt: Date(),
            winner: lastGameWinner,
            topFacts: topFacts,
            allFacts: rankedFacts,
            metrics: metrics
        )

        var updatedStats = existingStats
        for sample in samples {
            let current = updatedStats[sample.key] ?? GameInsightMetricStats(key: sample.key)
            updatedStats[sample.key] = current.updating(with: sample.value)
        }

        try await FirebaseService.shared.saveLatestGameInsights(summary)
        try await FirebaseService.shared.saveGameInsightMetricStats(updatedStats)
        latestGameInsightFacts = topFacts
        latestGameAllInsightFacts = rankedFacts
    }

    private func buildInsightSamples() -> [InsightSample] {
        var samples: [InsightSample] = []
        let players = gameState.players
        guard players.count == 3 else { return [] }

        let finalScores = players.map { ($0.id, $0.scores.last ?? 0) }
        let sortedFinal = finalScores.sorted { $0.1 > $1.1 }
        if let top = sortedFinal.first {
            samples.append(InsightSample(
                key: "final_score_max",
                category: "score",
                value: Double(top.1),
                direction: .high,
                text: "\(displayName(for: top.0)) a terminé avec \(top.1) points."
            ))
        }
        if let bottom = sortedFinal.last {
            samples.append(InsightSample(
                key: "final_score_min",
                category: "score",
                value: Double(bottom.1),
                direction: .low,
                text: "\(displayName(for: bottom.0)) a terminé avec seulement \(bottom.1) points."
            ))
        }
        if sortedFinal.count >= 2 {
            let gap = sortedFinal[0].1 - sortedFinal[1].1
            samples.append(InsightSample(
                key: "final_gap_1v2",
                category: "score",
                value: Double(gap),
                direction: .high,
                text: "\(displayName(for: sortedFinal[0].0)) a gagné avec \(gap) points d'avance sur le 2e."
            ))
            samples.append(InsightSample(
                key: "final_gap_close",
                category: "score",
                value: Double(gap),
                direction: .low,
                text: "\(displayName(for: sortedFinal[0].0)) a gagné avec seulement \(gap) point(s) d'écart."
            ))
        }

        let roundCount = players.map { $0.scores.count }.min() ?? 0
        if roundCount > 0 {
            var leadChanges = 0
            var previousLeader: PlayerId?
            var allTiedRounds = 0
            for roundIdx in 0..<roundCount {
                let scoresAtRound = players.map { ($0.id, $0.scores[safe: roundIdx] ?? 0) }
                let uniqueScores = Set(scoresAtRound.map(\.1))
                if uniqueScores.count == 1 {
                    allTiedRounds += 1
                }
                let maxScore = scoresAtRound.map(\.1).max() ?? 0
                let leaders = scoresAtRound.filter { $0.1 == maxScore }
                if leaders.count == 1 {
                    let currentLeader = leaders[0].0
                    if let prev = previousLeader, prev != currentLeader {
                        leadChanges += 1
                    }
                    previousLeader = currentLeader
                }
            }
            samples.append(InsightSample(
                key: "lead_changes",
                category: "momentum",
                value: Double(leadChanges),
                direction: .high,
                text: "Le joueur en première position a changé \(leadChanges) fois."
            ))
            samples.append(InsightSample(
                key: "all_tied_rounds",
                category: "momentum",
                value: Double(allTiedRounds),
                direction: .high,
                text: "Égalité parfaite sur \(allTiedRounds) tour(s)."
            ))
        }

        var exactBest: (player: PlayerId, streak: Int) = (.gg, 0)
        var missedBest: (player: PlayerId, streak: Int) = (.gg, 0)
        var overbidBest: (player: PlayerId, count: Int) = (.gg, 0)
        var underbidBest: (player: PlayerId, count: Int) = (.gg, 0)
        var maxBidError: (player: PlayerId, value: Int) = (.gg, 0)
        var latestZeroRound: (player: PlayerId, round: Int) = (.gg, 0)
        var roundDeltaMax: (player: PlayerId, value: Int) = (.gg, Int.min)
        var roundDeltaMin: (player: PlayerId, value: Int) = (.gg, Int.max)
        var gameTotalBetDeltaAbs = 0
        var roundTotalBetDeltaAbsMax = 0
        var roundTotalBetDeltaAbsMaxRound = 0
        var roundTotalBetDeltaSignedAtMax = 0

        for player in players {
            let count = Swift.min(player.announcedTricks.count, player.madeTricks.count)
            var exactCurrent = 0
            var missedCurrent = 0
            var overbidCount = 0
            var underbidCount = 0

            for i in 0..<count {
                let announced = player.announcedTricks[i]
                let made = player.madeTricks[i]
                if announced == made {
                    exactCurrent += 1
                    missedCurrent = 0
                } else {
                    missedCurrent += 1
                    exactCurrent = 0
                }
                exactBest = exactCurrent > exactBest.streak ? (player.id, exactCurrent) : exactBest
                missedBest = missedCurrent > missedBest.streak ? (player.id, missedCurrent) : missedBest

                if announced > made { overbidCount += 1 }
                if announced < made { underbidCount += 1 }

                let absError = abs(announced - made)
                if absError > maxBidError.value {
                    maxBidError = (player.id, absError)
                }
            }

            if overbidCount > overbidBest.count {
                overbidBest = (player.id, overbidCount)
            }
            if underbidCount > underbidBest.count {
                underbidBest = (player.id, underbidCount)
            }

            var previousScore = 0
            for (idx, score) in player.scores.enumerated() {
                if score == 0 && idx + 1 > latestZeroRound.round {
                    latestZeroRound = (player.id, idx + 1)
                }
                let delta = score - previousScore
                previousScore = score
                if delta > roundDeltaMax.value {
                    roundDeltaMax = (player.id, delta)
                }
                if delta < roundDeltaMin.value {
                    roundDeltaMin = (player.id, delta)
                }
            }
        }

        if exactBest.streak > 0 {
            samples.append(InsightSample(
                key: "streak_exact_bid",
                category: "bidding",
                value: Double(exactBest.streak),
                direction: .high,
                text: "\(displayName(for: exactBest.player)) a enchaîné \(exactBest.streak) mises exactes."
            ))
        }
        if missedBest.streak > 0 {
            samples.append(InsightSample(
                key: "streak_missed_bid",
                category: "bidding",
                value: Double(missedBest.streak),
                direction: .high,
                text: "\(displayName(for: missedBest.player)) a enchaîné \(missedBest.streak) mises ratées."
            ))
        }
        if overbidBest.count > 0 {
            samples.append(InsightSample(
                key: "overbid_count",
                category: "bidding",
                value: Double(overbidBest.count),
                direction: .high,
                text: "\(displayName(for: overbidBest.player)) a surmisé \(overbidBest.count) fois."
            ))
        }
        if underbidBest.count > 0 {
            samples.append(InsightSample(
                key: "underbid_count",
                category: "bidding",
                value: Double(underbidBest.count),
                direction: .high,
                text: "\(displayName(for: underbidBest.player)) a sous-misé \(underbidBest.count) fois."
            ))
        }
        if maxBidError.value > 0 {
            samples.append(InsightSample(
                key: "max_bid_error_abs",
                category: "bidding",
                value: Double(maxBidError.value),
                direction: .high,
                text: "Erreur de mise max: \(displayName(for: maxBidError.player)) s'est trompé de \(maxBidError.value)."
            ))
        }

        if latestZeroRound.round > 0 {
            samples.append(InsightSample(
                key: "zero_score_round_latest",
                category: "score",
                value: Double(latestZeroRound.round),
                direction: .high,
                text: "\(displayName(for: latestZeroRound.player)) était encore à 0 au tour \(latestZeroRound.round)."
            ))
        }
        if roundDeltaMax.value > Int.min {
            samples.append(InsightSample(
                key: "round_delta_max",
                category: "score",
                value: Double(roundDeltaMax.value),
                direction: .high,
                text: "Pic de score: \(displayName(for: roundDeltaMax.player)) a fait \(roundDeltaMax.value) points sur un tour."
            ))
        }
        if roundDeltaMin.value < Int.max {
            samples.append(InsightSample(
                key: "round_delta_min",
                category: "score",
                value: Double(roundDeltaMin.value),
                direction: .low,
                text: "Tour difficile: \(displayName(for: roundDeltaMin.player)) a fait \(roundDeltaMin.value) points."
            ))
        }

        if roundCount > 0 {
            for roundIdx in 0..<roundCount {
                let totalBet = players.reduce(0) { partialResult, player in
                    partialResult + (player.announcedTricks[safe: roundIdx] ?? 0)
                }
                let cardsThisRound = max((roundIdx + 1) - 2, 1)
                let absDelta = abs(totalBet - cardsThisRound)
                if absDelta > roundTotalBetDeltaAbsMax {
                    roundTotalBetDeltaAbsMax = absDelta
                    roundTotalBetDeltaSignedAtMax = totalBet - cardsThisRound
                    roundTotalBetDeltaAbsMaxRound = roundIdx + 1
                }
                gameTotalBetDeltaAbs += absDelta
            }
            let maxDeltaText: String
            if roundTotalBetDeltaSignedAtMax > 0 {
                maxDeltaText = "Vous avez annoncé \(roundTotalBetDeltaAbsMax) de trop au tour \(roundTotalBetDeltaAbsMaxRound)."
            } else if roundTotalBetDeltaSignedAtMax < 0 {
                maxDeltaText = "Vous avez annoncé \(roundTotalBetDeltaAbsMax) de moins au tour \(roundTotalBetDeltaAbsMaxRound)."
            } else {
                maxDeltaText = "Vous avez annoncé le bon nombre de plis au tour \(roundTotalBetDeltaAbsMaxRound)."
            }
            samples.append(InsightSample(
                key: "round_total_bet_delta_abs_max",
                category: "bidding",
                value: Double(roundTotalBetDeltaAbsMax),
                direction: .high,
                text: maxDeltaText
            ))
            samples.append(InsightSample(
                key: "game_total_bet_delta_abs_sum",
                category: "bidding",
                value: Double(gameTotalBetDeltaAbs),
                direction: .high,
                text: "Écart cumulé entre les mises et les plis possibles: \(gameTotalBetDeltaAbs)."
            ))
        }
        // TODO: Ajouter l'écart cumulé au cours de la partie (0 = tous les tours étaient parfaits)

        if let bestGlobalSuit = trumpSelectionsBySuit.max(by: { $0.value < $1.value }) {
            samples.append(InsightSample(
                key: "trump_suit_global_max",
                category: "trump",
                value: Double(bestGlobalSuit.value),
                direction: .high,
                text: "Atout dominant: \(displayName(for: bestGlobalSuit.key)) est sorti \(bestGlobalSuit.value) fois."
            ))
        }

        if let bestPlayerSuit = trumpSelectionsByPlayer
            .flatMap({ pair in pair.value.map { (pair.key, $0.key, $0.value) } })
            .max(by: { $0.2 < $1.2 }) {
            samples.append(InsightSample(
                key: "trump_suit_by_player_max",
                category: "trump",
                value: Double(bestPlayerSuit.2),
                direction: .high,
                text: "\(displayName(for: bestPlayerSuit.0)) a choisi \(displayName(for: bestPlayerSuit.1)) \(bestPlayerSuit.2) fois."
            ))
        }

        if trumpCancelCount > 0 {
            samples.append(InsightSample(
                key: "trump_cancel_count",
                category: "trump",
                value: Double(trumpCancelCount),
                direction: .high,
                text: "\(trumpCancelCount) annulation(s) de choix d'atout."
            ))
        }

        if let randomLeader = randomBetByPlayer.max(by: { $0.value < $1.value }) {
            samples.append(InsightSample(
                key: "random_bet_first_player_count",
                category: "bidding",
                value: Double(randomLeader.value),
                direction: .high,
                text: "\(displayName(for: randomLeader.key)) a misé aléatoirement \(randomLeader.value) fois en premier."
            ))
        }

        let allDifficulties = roundDifficultyByPlayer.values.flatMap { $0.values }
        if !allDifficulties.isEmpty {
            let avgDifficulty = allDifficulties.reduce(0, +) / Double(allDifficulties.count)
            samples.append(InsightSample(
                key: "hand_difficulty_game",
                category: "difficulty",
                value: avgDifficulty,
                direction: .high,
                text: "Partie exigeante côté mains (indice \(String(format: "%.3f", avgDifficulty)))."
            ))
            samples.append(InsightSample(
                key: "hand_easiness_game",
                category: "difficulty",
                value: avgDifficulty,
                direction: .low,
                text: "Partie plutôt facile côté mains (indice \(String(format: "%.3f", avgDifficulty)))."
            ))
        }

        var roundGapMax = 0.0
        var roundGapMin = Double.greatestFiniteMagnitude
        for (_, map) in roundDifficultyByPlayer {
            let values = Array(map.values)
            guard let maxV = values.max(), let minV = values.min() else { continue }
            let gap = maxV - minV
            roundGapMax = max(roundGapMax, gap)
            roundGapMin = min(roundGapMin, gap)
        }
        if roundGapMax > 0 {
            samples.append(InsightSample(
                key: "round_difficulty_gap_max",
                category: "difficulty",
                value: roundGapMax,
                direction: .high,
                text: "Un tour a présenté un gros écart de difficulté (\(String(format: "%.3f", roundGapMax)))."
            ))
        }
        if roundGapMin != Double.greatestFiniteMagnitude {
            samples.append(InsightSample(
                key: "round_difficulty_gap_min",
                category: "difficulty",
                value: roundGapMin,
                direction: .low,
                text: "Un tour a été très équitable en difficulté (\(String(format: "%.3f", roundGapMin)))."
            ))
        }

        let allMidDensities = roundMidCardDensityByPlayer.values.flatMap { $0.values }
        if let maxMidDensity = allMidDensities.max() {
            samples.append(InsightSample(
                key: "mid_card_density_max_round",
                category: "difficulty",
                value: maxMidDensity,
                direction: .high,
                text: "Tour très chargé en cartes moyennes (9/10/V/D) avec \(Int((maxMidDensity * 100).rounded()))%."
            ))
        }

        if let maxConcentration = trumpChoiceConcentrationRecords.max(by: { $0.concentration < $1.concentration }) {
            samples.append(InsightSample(
                key: "trump_chooser_suit_concentration_max",
                category: "trump",
                value: maxConcentration.concentration,
                direction: .high,
                text: "\(displayName(for: maxConcentration.playerId)) a choisi \(displayName(for: maxConcentration.suit)) avec une forte concentration (\(Int((maxConcentration.concentration * 100).rounded()))%)."
            ))
        }
        if let minConcentration = trumpChoiceConcentrationRecords.min(by: { $0.concentration < $1.concentration }) {
            samples.append(InsightSample(
                key: "trump_chooser_suit_concentration_min",
                category: "trump",
                value: minConcentration.concentration,
                direction: .low,
                text: "\(displayName(for: minConcentration.playerId)) a choisi \(displayName(for: minConcentration.suit)) avec peu de cartes (\(Int((minConcentration.concentration * 100).rounded()))%)."
            ))
        }

        return samples
    }

    private func rankFacts(from samples: [InsightSample],
                           using statsByKey: [String: GameInsightMetricStats]) -> [GameInsightFact] {
        samples.map { sample in
            let stats = statsByKey[sample.key]
            let score = insightScore(for: sample, stats: stats)
            return GameInsightFact(
                id: UUID().uuidString,
                metricKey: sample.key,
                category: sample.category,
                value: sample.value,
                rarityScore: score,
                text: sample.text
            )
        }
        .sorted {
            if $0.rarityScore == $1.rarityScore {
                return abs($0.value) > abs($1.value)
            }
            return $0.rarityScore > $1.rarityScore
        }
    }

    private func selectTopFacts(from ranked: [GameInsightFact], maxCount: Int) -> [GameInsightFact] {
        let filtered = ranked.filter { isDisplayableFact($0) }
        let minimumRarityScore = 0.85
        let prioritized = filtered.filter { $0.rarityScore >= minimumRarityScore }
        let pool = prioritized.isEmpty ? filtered : prioritized

        var selected: [GameInsightFact] = []
        var usedCategories: Set<String> = []

        for fact in pool where selected.count < maxCount {
            if !usedCategories.contains(fact.category) {
                selected.append(fact)
                usedCategories.insert(fact.category)
            }
        }
        if selected.count < maxCount {
            for fact in pool where selected.count < maxCount {
                if !selected.contains(where: { $0.id == fact.id }) {
                    selected.append(fact)
                }
            }
        }
        return Array(selected.prefix(maxCount)).map(applyTextVariation)
    }

    private func isDisplayableFact(_ fact: GameInsightFact) -> Bool {
        switch fact.metricKey {
        case "overbid_count",
             "underbid_count",
             "max_bid_error_abs",
             "random_bet_first_player_count",
             "trump_cancel_count",
             "lead_changes",
             "all_tied_rounds":
            return fact.value > 0
        default:
            return true
        }
    }

    private func applyTextVariation(_ fact: GameInsightFact) -> GameInsightFact {
        let variants: [String]
        switch fact.metricKey {
        case "final_score_max", "final_score_min", "final_gap_1v2", "final_gap_close",
             "round_delta_max", "round_delta_min", "zero_score_round_latest":
            variants = [fact.text, "Stat score: \(fact.text)", "Côté score: \(fact.text)"]
        case "streak_exact_bid", "streak_missed_bid", "overbid_count", "underbid_count",
             "max_bid_error_abs", "round_total_bet_delta_abs_max", "game_total_bet_delta_abs_sum",
             "random_bet_first_player_count":
            variants = [fact.text, "Côté mises: \(fact.text)", "Lecture des annonces: \(fact.text)"]
        case "trump_suit_global_max", "trump_suit_by_player_max", "trump_cancel_count",
             "trump_chooser_suit_concentration_max", "trump_chooser_suit_concentration_min":
            variants = [fact.text, "Côté atout: \(fact.text)", "Tendance atout: \(fact.text)"]
        case "hand_difficulty_game", "hand_easiness_game", "round_difficulty_gap_max",
             "round_difficulty_gap_min", "mid_card_density_max_round":
            variants = [fact.text, "Lecture des mains: \(fact.text)", "Côté difficulté: \(fact.text)"]
        default:
            variants = [fact.text, "Fait marquant: \(fact.text)", "À noter: \(fact.text)"]
        }
        let index = stableVariantIndex(for: fact.metricKey, value: fact.value, optionsCount: variants.count)
        return GameInsightFact(
            id: fact.id,
            metricKey: fact.metricKey,
            category: fact.category,
            value: fact.value,
            rarityScore: fact.rarityScore,
            text: variants[index]
        )
    }

    private func stableVariantIndex(for key: String, value: Double, optionsCount: Int) -> Int {
        guard optionsCount > 0 else { return 0 }
        var hash = 5381
        let seed = "\(key)|\(Int((value * 1000).rounded()))"
        for unicode in seed.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ Int(unicode.value)
        }
        return abs(hash) % optionsCount
    }

    private func insightScore(for sample: InsightSample, stats: GameInsightMetricStats?) -> Double {
        guard let stats else {
            return min(abs(sample.value) / 25.0, 1.2) + 0.5
        }
        let std = sqrt(max(stats.variance, 0))
        let fallbackSpread = max(abs(stats.max - stats.min), 1)
        let scale = max(std, fallbackSpread / 2.0, 1)
        let centered: Double
        switch sample.direction {
        case .high:
            centered = (sample.value - stats.mean) / scale
        case .low:
            centered = (stats.mean - sample.value) / scale
        }
        let sidedZ = max(0, centered)
        var recordBonus = 0.0
        if stats.count > 0 {
            switch sample.direction {
            case .high:
                if sample.value > stats.max {
                    recordBonus = 1.5 + min((sample.value - stats.max) / fallbackSpread, 2.0)
                }
            case .low:
                if sample.value < stats.min {
                    recordBonus = 1.5 + min((stats.min - sample.value) / fallbackSpread, 2.0)
                }
            }
        }
        let warmupBonus = stats.count < 6 ? 0.35 : 0
        let magnitudeBonus = min(abs(sample.value) / 40.0, 0.75)
        return sidedZ + recordBonus + warmupBonus + magnitudeBonus
    }

    private func displayName(for playerId: PlayerId) -> String {
        playerId.rawValue.uppercased()
    }

    private func displayName(for suit: Suit) -> String {
        switch suit {
        case .hearts: return "cœur"
        case .diamonds: return "carreau"
        case .clubs: return "trèfle"
        case .spades: return "pique"
        }
    }

    private func midCardDensity(in hand: [Card]) -> Double {
        guard !hand.isEmpty else { return 0 }
        let midRanks: Set<Rank> = [.nine, .ten, .jack, .queen]
        let count = hand.filter { midRanks.contains($0.rank) }.count
        return Double(count) / Double(hand.count)
    }

    private func dominantSuitConcentration(in hand: [Card]) -> Double {
        guard !hand.isEmpty else { return 0 }
        var bySuit: [Suit: Int] = [:]
        for card in hand {
            bySuit[card.suit, default: 0] += 1
        }
        let dominantCount = bySuit.values.max() ?? 0
        return Double(dominantCount) / Double(hand.count)
    }

    private func suitConcentration(in hand: [Card], targetSuit: Suit) -> Double {
        guard !hand.isEmpty else { return 0 }
        let count = hand.filter { $0.suit == targetSuit }.count
        return Double(count) / Double(hand.count)
    }

    private func handDifficultyIndex(midDensity: Double, dominantSuitConcentration: Double) -> Double {
        let dispersionHardness = 1.0 - dominantSuitConcentration
        return (0.7 * midDensity) + (0.3 * dispersionHardness)
    }

    private func isRandomBetModeEligible(for playerId: PlayerId, round: Int) -> Bool {
        guard round > 3 else { return false }
        let scoreIndex = round - 2
        let roundScores = gameState.players.map { (id: $0.id, score: $0.scores[safe: scoreIndex] ?? 0) }
        guard let me = roundScores.first(where: { $0.id == playerId }) else { return false }
        let sorted = roundScores.map(\.score).sorted(by: >)
        let best = sorted.first ?? 0
        let second = sorted.dropFirst().first ?? 0
        return me.score == best && me.score != second && me.score >= 2 * second
    }
}
