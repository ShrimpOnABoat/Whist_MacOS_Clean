//
//  ScoresManager.swift
//  Whist
//
//  Created by Tony Buffard on 2024-11-22.
//

import Foundation

struct GameScore: Codable, Identifiable {
    var id = UUID() // Keep UUID for Identifiable conformance and potential local use
    let date: Date
    let ggScore: Int
    let ddScore: Int
    let totoScore: Int
    let ggPosition: Int?
    let ddPosition: Int?
    let totoPosition: Int?
    let ggConsecutiveWins: Int?
    let ddConsecutiveWins: Int?
    let totoConsecutiveWins: Int?

    init(date: Date, ggScore: Int, ddScore: Int, totoScore: Int,
         ggPosition: Int? = nil, ddPosition: Int? = nil, totoPosition: Int? = nil,
         ggConsecutiveWins: Int? = nil, ddConsecutiveWins: Int? = nil, totoConsecutiveWins: Int? = nil) {
        self.date = date
        self.ggScore = ggScore
        self.ddScore = ddScore
        self.totoScore = totoScore
        self.ggPosition = ggPosition
        self.ddPosition = ddPosition
        self.totoPosition = totoPosition
        self.ggConsecutiveWins = ggConsecutiveWins
        self.ddConsecutiveWins = ddConsecutiveWins
        self.totoConsecutiveWins = totoConsecutiveWins
    }

    enum CodingKeys: String, CodingKey {
        case date
        case ggScore = "gg_score"
        case ddScore = "dd_score"
        case totoScore = "toto_score"
        case ggPosition = "gg_position"
        case ddPosition = "dd_position"
        case totoPosition = "toto_position"
        case ggConsecutiveWins = "gg_consecutive_wins"
        case ddConsecutiveWins = "dd_consecutive_wins"
        case totoConsecutiveWins = "toto_consecutive_wins"
    }
}

struct Loser {
    let playerId: PlayerId
    let losingMonths: Int
}

enum ScoresManagerError: Error {
    case directoryCreationFailed
    case encodingFailed
    case decodingFailed
    case fileWriteFailed
    case fileReadFailed
    case firebaseError(Error)
    case backupOperationFailed(String)
}

class ScoresManager {
    static let shared = ScoresManager()
    private let firebaseService = FirebaseService.shared
    private let fileManager = FileManager.default
    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    init() {}

    func saveScore(_ gameScore: GameScore) async throws {
        do {
            try await firebaseService.saveGameScore(gameScore)
            logger.log("✅ Successfully saved GameScore with id: \(gameScore.id)")
        } catch {
            logger.log("❌ Error saving GameScore: \(error.localizedDescription)")
            throw ScoresManagerError.firebaseError(error)
        }
    }

    func saveScores(_ scores: [GameScore]) async throws {
        guard !scores.isEmpty else {
            logger.log("No scores provided to save.")
            return
        }
        do {
            try await firebaseService.saveGameScores(scores)
            logger.log("✅ Successfully saved \(scores.count) scores to Firebase.")
        } catch {
            logger.log("❌ Error saving batch of scores: \(error.localizedDescription)")
            throw ScoresManagerError.firebaseError(error)
        }
    }

    func loadScores(for year: Int? = Calendar.current.component(.year, from: Date())) async throws -> [GameScore] {
        do {
            let scores = try await firebaseService.loadScores(for: year)
            logger.log("✅ Successfully loaded \(scores.count) scores from Firebase\(year == nil ? "" : " for year \(year!)").")
            return scores
        } catch {
            logger.log("❌ Error loading scores from Firebase: \(error.localizedDescription)")
            throw ScoresManagerError.firebaseError(error)
        }
    }

    func loadScoresSafely(for year: Int? = Calendar.current.component(.year, from: Date())) async -> [GameScore] {
        do {
            return try await loadScores(for: year)
        } catch {
            logger.log("Error loading scores safely: \(error)")
            return []
        }
    }

    func deleteAllScores() async throws {
        do {
            try await firebaseService.deleteAllGameScores()
            logger.log("✅ Successfully deleted all scores from Firebase.")
        } catch {
            logger.log("❌ Error deleting all scores from Firebase: \(error.localizedDescription)")
            throw ScoresManagerError.firebaseError(error)
        }
    }

    func findLoser() async -> Loser? {
        let scores = await loadScoresSafely(for: currentYear)
        guard !scores.isEmpty else {
            return nil
        }

        let currentMonth = Calendar.current.component(.month, from: Date())

        let gamePoints: (GameScore) -> [String: Int] = { game in
            if let ggPos = game.ggPosition, let ddPos = game.ddPosition, let totoPos = game.totoPosition {
                let positions = [("gg", ggPos), ("dd", ddPos), ("toto", totoPos)]
                let sorted = positions.sorted { $0.1 < $1.1 }
                var points: [String: Int] = ["gg": 0, "dd": 0, "toto": 0]
                points[sorted[0].0] = 2
                points[sorted[1].0] = 1
                return points
            }

            let scores: [(String, Int)] = [("gg", game.ggScore), ("dd", game.ddScore), ("toto", game.totoScore)]
            let sorted = scores.sorted { $0.1 > $1.1 }

            if sorted[0].1 == sorted[1].1 && sorted[1].1 == sorted[2].1 {
                return ["gg": 2, "dd": 2, "toto": 2]
            } else if sorted[0].1 == sorted[1].1 {
                var points: [String: Int] = ["gg": 0, "dd": 0, "toto": 0]
                for entry in scores where entry.1 == sorted[0].1 {
                    points[entry.0] = 2
                }
                return points
            } else if sorted[1].1 == sorted[2].1 {
                var points: [String: Int] = ["gg": 0, "dd": 0, "toto": 0]
                points[sorted[0].0] = 2
                points[sorted[1].0] = 1
                points[sorted[2].0] = 1
                return points
            } else {
                var points: [String: Int] = ["gg": 0, "dd": 0, "toto": 0]
                points[sorted[0].0] = 2
                points[sorted[1].0] = 1
                return points
            }
        }

        let calculatePlayerPoints: ([GameScore]) -> [String: Int] = { games in
            var points: [String: Int] = ["gg": 0, "dd": 0, "toto": 0]
            for game in games {
                for (player, value) in gamePoints(game) {
                    points[player, default: 0] += value
                }
            }
            return points
        }

        let getGamesForMonth: (Int) -> [GameScore] = { month in
            return scores.filter {
                let gameMonth = Calendar.current.component(.month, from: $0.date)
                return gameMonth == month
            }
        }

        let findLoserInMonth: ([String: Int]) -> String? = { points in
            let sortedPoints = points.sorted { $0.value < $1.value }
            if sortedPoints.count > 1 && sortedPoints[0].value != sortedPoints[1].value {
                return sortedPoints[0].key
            }
            return nil
        }

        var losingMonths = 0
        var loserName: String?
        var previousMonth = currentMonth - 1

        while previousMonth > 0 {
            let games = getGamesForMonth(previousMonth)
            if games.isEmpty {
                previousMonth -= 1
                continue
            }

            let points = calculatePlayerPoints(games)
            let loser = findLoserInMonth(points)

            if loserName == nil {
                loserName = loser
            }

            if loserName != nil && loserName == loser {
                losingMonths += 1
                previousMonth -= 1
            } else {
                break
            }
        }

        guard let loser = loserName, let loserId = PlayerId(rawValue: loser), losingMonths > 0 else {
            return nil
        }

        return Loser(playerId: loserId, losingMonths: losingMonths)
    }

    func restoreBackup(from backupDirectory: URL) async throws {
        do {
            let backupFiles = try fileManager.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }

            if backupFiles.isEmpty {
                logger.log("⚠️ No backup JSON files found in directory: \(backupDirectory.path). Aborting restore.")
                throw ScoresManagerError.backupOperationFailed("No JSON files found in backup directory.")
            }

            logger.log("🔍 Found \(backupFiles.count) JSON backup files. Starting restore process...")

            var allScores: [GameScore] = []

            for fileURL in backupFiles {
                logger.log("  Processing backup file: \(fileURL.lastPathComponent)")
                do {
                    let data = try Data(contentsOf: fileURL)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .custom { decoder in
                        let container = try decoder.singleValueContainer()
                        let dateString = try container.decode(String.self)

                        let isoFormatter = ISO8601DateFormatter()
                        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                        if let date = isoFormatter.date(from: dateString) { return date }

                        isoFormatter.formatOptions = [.withInternetDateTime]
                        if let date = isoFormatter.date(from: dateString) { return date }

                        let fallbackFormatter = DateFormatter()
                        fallbackFormatter.locale = Locale(identifier: "en_US_POSIX")
                        fallbackFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
                        if let date = fallbackFormatter.date(from: dateString) { return date }

                        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date string \(dateString) does not match expected formats")
                    }
                    let scores = try decoder.decode([GameScore].self, from: data)
                    logger.log("    ✅ Decoded \(scores.count) scores from \(fileURL.lastPathComponent).")
                    allScores.append(contentsOf: scores)
                } catch {
                    logger.log("    🚨 Error processing file \(fileURL.lastPathComponent): \(error.localizedDescription)")
                    throw ScoresManagerError.decodingFailed
                }
            }

            logger.log("📊 Total scores decoded from backup files: \(allScores.count)")
            guard !allScores.isEmpty else {
                logger.log("⚠️ No scores decoded from backup files. Restore aborted.")
                throw ScoresManagerError.backupOperationFailed("No scores found in backup files.")
            }

            logger.log("🔥 Deleting existing scores from Firebase...")
            try await deleteAllScores()

            logger.log("☁️ Uploading \(allScores.count) backup scores to Firebase...")
            try await saveScores(allScores)

            logger.log("✅ Restore completed successfully!")

        } catch let error as ScoresManagerError {
            logger.log("🚨 Restore failed: \(error)")
            throw error
        } catch {
            logger.log("🚨 An unexpected error occurred during restore: \(error)")
            throw ScoresManagerError.backupOperationFailed(error.localizedDescription)
        }
    }

    func exportScoresToLocalDirectory(_ directory: URL) async throws {
        do {
            if !fileManager.fileExists(atPath: directory.path) {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            }

            logger.log("☁️ Loading all scores from Firebase for export...")
            let scores = try await loadScores(for: nil)

            if scores.isEmpty {
                logger.log("⚠️ No scores found in Firebase to export.")
                return
            }

            // Normalize scores: compute missing positions only when not already present
            let normalizedScores: [GameScore] = scores.map { score in
                // If all positions already exist, return as-is
                if score.ggPosition != nil && score.ddPosition != nil && score.totoPosition != nil {
                    return score
                }

                // Determine rankings based on scores with tie handling
                let entries: [(key: String, value: Int)] = [
                    ("gg", score.ggScore),
                    ("dd", score.ddScore),
                    ("toto", score.totoScore)
                ]

                // Sort descending by score
                let sorted = entries.sorted { $0.value > $1.value }

                // Compute positions with ties: equal scores share the same position
                var positionByKey: [String: Int] = [:]
                var currentPosition = 1
                var lastScore: Int? = nil
                var itemsAtCurrentRank = 0

                for (index, item) in sorted.enumerated() {
                    if let last = lastScore, item.value == last {
                        // same score as previous -> same position
                        positionByKey[item.key] = currentPosition
                        itemsAtCurrentRank += 1
                    } else {
                        // new score bucket -> advance position by number of items in previous bucket
                        if index != 0 {
                            currentPosition += itemsAtCurrentRank
                        }
                        positionByKey[item.key] = currentPosition
                        lastScore = item.value
                        itemsAtCurrentRank = 1
                    }
                }

                // Only fill positions that are currently nil, keep existing ones intact
                return GameScore(
                    date: score.date,
                    ggScore: score.ggScore,
                    ddScore: score.ddScore,
                    totoScore: score.totoScore,
                    ggPosition: score.ggPosition ?? positionByKey["gg"],
                    ddPosition: score.ddPosition ?? positionByKey["dd"],
                    totoPosition: score.totoPosition ?? positionByKey["toto"],
                    ggConsecutiveWins: score.ggConsecutiveWins,
                    ddConsecutiveWins: score.ddConsecutiveWins,
                    totoConsecutiveWins: score.totoConsecutiveWins
                )
            }

            logger.log("📊 Loaded \(scores.count) scores for export. Normalized missing positions. Grouping by year...")

            let groupedByYear = Dictionary(grouping: normalizedScores) { score in
                Calendar.current.component(.year, from: score.date)
            }.mapValues { yearlyScores in
                yearlyScores.sorted { $0.date < $1.date }
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            encoder.dateEncodingStrategy = .formatted(formatter)

            logger.log("💾 Writing scores to JSON files in \(directory.path)...")
            for (year, yearlyScores) in groupedByYear {
                let fileURL = directory.appendingPathComponent("scores_\(year).json")
                do {
                    let data = try encoder.encode(yearlyScores)
                    try data.write(to: fileURL, options: .atomic)
                    logger.log("  ✅ Exported \(yearlyScores.count) scores for year \(year) to \(fileURL.lastPathComponent)")
                } catch {
                    logger.log("  🚨 Error exporting scores for year \(year): \(error.localizedDescription)")
                    throw ScoresManagerError.fileWriteFailed
                }
            }

            logger.log("✅ Export completed successfully!")

        } catch let error as ScoresManagerError {
            logger.log("🚨 Export failed: \(error)")
            throw error
        } catch {
            logger.log("🚨 An unexpected error occurred during export: \(error)")
            throw ScoresManagerError.backupOperationFailed("Export failed: \(error.localizedDescription)")
        }
    }
}
