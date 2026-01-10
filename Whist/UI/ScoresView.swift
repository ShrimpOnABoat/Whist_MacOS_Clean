//
//  ScoresView.swift
//  Whist
//
//  Created by Tony Buffard on 2025-02-06.
//  Updated by ChatGPT on 2025-02-06.
//

import SwiftUI

struct ScoresView: View {
    @EnvironmentObject var gameManager: GameManager
    @State private var selectedYear: Int = Calendar.current.component(.year, from: Date())
    @State private var selectedTab: ScoreTab = .summary

    var body: some View {
        VStack {
            // Year selection controls
            HStack {
                Button {
                    if selectedYear > firstYear {
                        selectedYear -= 1
                    }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(selectedYear <= firstYear)

                Text(String(selectedYear))
                    .font(.title)

                Button {
                    if selectedYear < currentYear {
                        selectedYear += 1
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(selectedYear >= currentYear)
            }
            .padding()

            // Tab selection: Summary vs Details
            Picker("Mode", selection: $selectedTab) {
                Text("Résumé").tag(ScoreTab.summary)
                Text("Détails").tag(ScoreTab.details)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)

            // Display content based on the selected tab
            if selectedTab == .summary {
                SummaryView(year: selectedYear)
                    .environmentObject(gameManager)
                    .id(selectedYear)
            } else {
                DetailedScoresView(year: selectedYear)
                    .id(selectedYear)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 460, minHeight: 500)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

enum ScoreTab {
    case summary, details
}

// MARK: - Summary (Résumé) View

struct MonthlySummary: Identifiable {
    let id = UUID()
    let month: String
    let ggPoints: Int
    let ddPoints: Int
    let totoPoints: Int
    let ggTally: Int
    let ddTally: Int
    let totoTally: Int
}

struct SummaryView: View {
    @EnvironmentObject var gameManager: GameManager
    let year: Int
    @State private var monthlySummaries: [MonthlySummary] = []
    @State private var glowPulse: Bool = false

    // Compute overall totals from the monthly summaries.
    var total: (gg: Int, dd: Int, toto: Int, ggTally: Int, ddTally: Int, totoTally: Int) {
        var total = (gg: 0, dd: 0, toto: 0, ggTally: 0, ddTally: 0, totoTally: 0)
        for summary in monthlySummaries {
            total.gg += summary.ggPoints
            total.dd += summary.ddPoints
            total.toto += summary.totoPoints
            total.ggTally += summary.ggTally
            total.ddTally += summary.ddTally
            total.totoTally += summary.totoTally
        }
        return total
    }
    
    private var currentYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    // Decide yearly ranking.
    // Primary: yearly tallies; Secondary: total points (tie-breaker).
    private func podiumOrder() -> [PlayerId] {
        let candidates: [(id: PlayerId, tally: Int, points: Int)] = [
            (.gg, total.ggTally, total.gg),
            (.dd, total.ddTally, total.dd),
            (.toto, total.totoTally, total.toto)
        ]

        return candidates
            .sorted {
                if $0.tally != $1.tally { return $0.tally > $1.tally }
                if $0.points != $1.points { return $0.points > $1.points }
                return String(describing: $0.id) < String(describing: $1.id)
            }
            .map { $0.id }
    }

    private func avatarView(for id: PlayerId, size: CGFloat) -> some View {
        let p = gameManager.gameState.getPlayer(by: id)
        
        return VStack(spacing: 6) {
            ZStack {
                (p.imageBackgroundColor ?? Color.gray)
                (p.image ?? Image(systemName: "person.crop.circle"))
                    .resizable()
                    .scaledToFit()
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
        }
    }


    @ViewBuilder
    private func annualPodiumHeader() -> some View {
        if year == currentYear || monthlySummaries.isEmpty {
            EmptyView() // hide for current year
        } else {
            let order = podiumOrder()
            if order.count != 3 {
                EmptyView()
            } else {
                ZStack {
                    Image("palmares annuel")
                        .resizable()
                        .scaledToFit()
                        // Golden glow: layered soft shadows
                        .shadow(color: Color(red: 1.0, green: 0.84, blue: 0.0).opacity(glowPulse ? 0.55 : 0.25), radius: glowPulse ? 36 : 12, x: 0, y: 0)
                        .shadow(color: Color(red: 1.0, green: 0.65, blue: 0.0).opacity(glowPulse ? 0.35 : 0.15), radius: glowPulse ? 22 : 8, x: 0, y: 0)
                        // Subtle radiant bloom along the edges
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    LinearGradient(colors: [
                                        Color(red: 1.0, green: 0.95, blue: 0.6),
                                        Color(red: 1.0, green: 0.85, blue: 0.2),
                                        Color(red: 1.0, green: 0.70, blue: 0.0)
                                    ], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    lineWidth: glowPulse ? 3 : 1.5
                                )
                                .blur(radius: glowPulse ? 6 : 2)
                                .opacity(0.85)
                                .blendMode(.plusLighter)
                        )
                        .overlay(alignment: .topLeading) {
                            GeometryReader { geo in
                                let rect = aspectFitRect(container: geo.size, imageSize: palmaresSize)

                                // Your “relative to image” coordinates:
                                let winnerX = rect.minX + rect.width  * 0.50
                                let winnerY = rect.minY + rect.height * 0.36 // 0.35 // 0.38

                                let leftX   = rect.minX + rect.width  * 0.28
                                let rightX  = rect.minX + rect.width  * 0.72
                                let othersY = rect.minY + rect.height * 0.63 // 0.64 // 0.65 // 0.63 // 0.60 // 0.78

                                let winnerSize = min(rect.width, rect.height) * 0.35 // 0.34
                                let otherSize  = min(rect.width, rect.height) * 0.28 // 0.29 // 0.26

                                avatarView(for: order[0], size: winnerSize)
                                    .position(x: winnerX, y: winnerY)

                                avatarView(for: order[1], size: otherSize)
                                    .position(x: leftX, y: othersY)

                                avatarView(for: order[2], size: otherSize)
                                    .position(x: rightX, y: othersY)
                            }
                        }
                        .animation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true), value: glowPulse)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 12)
                .onAppear { glowPulse = true }
                .onDisappear { glowPulse = false }
            }
        }
    }

    var body: some View {
        ScrollView {
            annualPodiumHeader()
                .scaleEffect(x: 1.2, y: 1.2, anchor: .center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading) {
                // Table header row
                HStack {
                    Text("Mois").frame(width: 100, alignment: .leading).foregroundColor(.secondary)
                    Spacer()
                    Text("GG").frame(width: 40, alignment: .center).foregroundColor(.secondary)
                    Text("DD").frame(width: 40, alignment: .center).foregroundColor(.secondary)
                    Text("Toto").frame(width: 40, alignment: .center).foregroundColor(.secondary)
                    Rectangle()
                        .frame(width: 1, height: 20)
                        .foregroundColor(Color(NSColor.separatorColor))
                    Text("GG").frame(width: 40, alignment: .center).foregroundColor(.secondary)
                    Text("DD").frame(width: 40, alignment: .center).foregroundColor(.secondary)
                    Text("Toto").frame(width: 40, alignment: .center).foregroundColor(.secondary)
                }
                .font(.subheadline)
                .padding(.vertical, 4)

                Divider()

                // Data rows
                ForEach(monthlySummaries) { summary in
                    HStack {
                        Text(summary.month).frame(width: 100, alignment: .leading).foregroundColor(.primary)
                        Spacer()
                        Text("\(summary.ggPoints)").frame(width: 40, alignment: .center).foregroundColor(.primary)
                        Text("\(summary.ddPoints)").frame(width: 40, alignment: .center).foregroundColor(.primary)
                        Text("\(summary.totoPoints)").frame(width: 40, alignment: .center).foregroundColor(.primary)
                        Rectangle()
                            .frame(width: 1, height: 20)
                            .foregroundColor(Color(NSColor.separatorColor))
                        Text("\(summary.ggTally)").frame(width: 40, alignment: .center)
                        Text("\(summary.ddTally)").frame(width: 40, alignment: .center)
                        Text("\(summary.totoTally)").frame(width: 40, alignment: .center)
                    }
                    .padding(.vertical, 2)
                }

                Divider()

                // Total row
                HStack {
                    Text("Total").frame(width: 100, alignment: .leading).foregroundColor(.primary)
                    Spacer()
                    Text("\(total.gg)").frame(width: 40, alignment: .center).foregroundColor(.primary)
                    Text("\(total.dd)").frame(width: 40, alignment: .center).foregroundColor(.primary)
                    Text("\(total.toto)").frame(width: 40, alignment: .center).foregroundColor(.primary)
                    Rectangle()
                        .frame(width: 1, height: 20)
                        .foregroundColor(Color(NSColor.separatorColor))
                    Text("\(total.ggTally)").frame(width: 40, alignment: .center).foregroundColor(.primary)
                    Text("\(total.ddTally)").frame(width: 40, alignment: .center).foregroundColor(.primary)
                    Text("\(total.totoTally)").frame(width: 40, alignment: .center).foregroundColor(.primary)
                }
                .font(.headline)
                .padding(.vertical, 4)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1))
        }
        .onAppear {
            Task { await loadData() }
        }
        .onChange(of: year) { _ in
            monthlySummaries = []
            Task { await loadData() }
        }
    }
    
    private func loadData() async {
        let summaries = await computeMonthlySummaries(for: year)
        await MainActor.run {
            self.monthlySummaries = summaries
        }
    }
}

/// Computes the monthly summaries for the given year by loading the scores and grouping them.
/// Update the monthly summaries function to use the new point calculation.
func computeMonthlySummaries(for year: Int) async -> [MonthlySummary] {
    let scores = await ScoresManager.shared.loadScoresSafely(for: year)

    let monthNames = [
        1: "Janvier", 2: "Février", 3: "Mars", 4: "Avril",
        5: "Mai", 6: "Juin", 7: "Juillet", 8: "Août",
        9: "Septembre", 10: "Octobre", 11: "Novembre", 12: "Décembre"
    ]
    
    var monthlyData: [Int: (gg: Int, dd: Int, toto: Int)] = [:]
    
    for score in scores {
        let calendar = Calendar.current
        guard calendar.component(.year, from: score.date) == year else { continue }
        let gameMonth = calendar.component(.month, from: score.date)
        
        if monthlyData[gameMonth] == nil {
            monthlyData[gameMonth] = (0, 0, 0)
        }
        
        let points = calculateGamePoints(for: score)
        monthlyData[gameMonth]!.gg += points.gg
        monthlyData[gameMonth]!.dd += points.dd
        monthlyData[gameMonth]!.toto += points.toto
    }
    
    var summaries: [MonthlySummary] = []
    for (month, points) in monthlyData {
        let tallies = calculateTallies(for: points)
        if let monthName = monthNames[month] {
            summaries.append(MonthlySummary(month: monthName,
                                            ggPoints: points.gg,
                                            ddPoints: points.dd,
                                            totoPoints: points.toto,
                                            ggTally: tallies.gg,
                                            ddTally: tallies.dd,
                                            totoTally: tallies.toto))
        }
    }
    // Sort summaries in month order.
    let order = ["Janvier", "Février", "Mars", "Avril", "Mai", "Juin",
                 "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre"]
    summaries.sort { order.firstIndex(of: $0.month)! < order.firstIndex(of: $1.month)! }
    
    return summaries
}

/// Calculate the game points for a single GameScore according to tie-breaking rules.
func calculateGamePoints(for game: GameScore) -> (gg: Int, dd: Int, toto: Int) {
    // If position information is available, use it.
    if let ggPos = game.ggPosition, let ddPos = game.ddPosition, let totoPos = game.totoPosition {
        let positions = [("gg", ggPos), ("dd", ddPos), ("toto", totoPos)]
        let sorted = positions.sorted { $0.1 < $1.1 } // lower is better
        var points = (gg: 0, dd: 0, toto: 0)
        // First gets 2 points, second gets 1, third gets 0.
        switch sorted[0].0 {
        case "gg": points.gg = 2
        case "dd": points.dd = 2
        case "toto": points.toto = 2
        default: break
        }
        switch sorted[1].0 {
        case "gg": points.gg = 1
        case "dd": points.dd = 1
        case "toto": points.toto = 1
        default: break
        }
        return points
    } else {
        // Positions not available, so use score values.
        let scores: [(String, Int)] = [("gg", game.ggScore), ("dd", game.ddScore), ("toto", game.totoScore)]
        let sorted = scores.sorted { $0.1 > $1.1 } // descending order (highest first)
        
        // Case 1: All three scores are tied.
        if sorted[0].1 == sorted[1].1 && sorted[1].1 == sorted[2].1 {
            return (gg: 2, dd: 2, toto: 2)
        }
        // Case 2: Tie for first (top two are equal).
        else if sorted[0].1 == sorted[1].1 {
            var points = (gg: 0, dd: 0, toto: 0)
            // Award 2 points to any player whose score equals the top score; the remaining player gets 0.
            for entry in scores {
                if entry.1 == sorted[0].1 {
                    switch entry.0 {
                    case "gg": points.gg = 2
                    case "dd": points.dd = 2
                    case "toto": points.toto = 2
                    default: break
                    }
                }
            }
            return points
        }
        // Case 3: Tie for second (i.e. first is clear, but second and third are equal).
        else if sorted[1].1 == sorted[2].1 {
            var points = (gg: 0, dd: 0, toto: 0)
            // Clear winner gets 2 points.
            switch sorted[0].0 {
            case "gg": points.gg = 2
            case "dd": points.dd = 2
            case "toto": points.toto = 2
            default: break
            }
            // Both tied players get 1 point each.
            for entry in sorted[1...2] {
                switch entry.0 {
                case "gg": points.gg = 1
                case "dd": points.dd = 1
                case "toto": points.toto = 1
                default: break
                }
            }
            return points
        }
        // Case 4: No ties.
        else {
            var points = (gg: 0, dd: 0, toto: 0)
            switch sorted[0].0 {
            case "gg": points.gg = 2
            case "dd": points.dd = 2
            case "toto": points.toto = 2
            default: break
            }
            switch sorted[1].0 {
            case "gg": points.gg = 1
            case "dd": points.dd = 1
            case "toto": points.toto = 1
            default: break
            }
            // Third automatically gets 0.
            return points
        }
    }
}

/// Given the total points for a month, calculate the tally for each player.
/// The highest gets 2 points and the second highest gets 1 point.
func calculateTallies(for points: (gg: Int, dd: Int, toto: Int)) -> (gg: Int, dd: Int, toto: Int) {
    let values = [points.gg, points.dd, points.toto]
    let sorted = values.sorted(by: >)
    let tallyFor = { (score: Int) -> Int in
        if score == sorted[0] {
            return 2
        } else if score == sorted[1] {
            return 1
        } else {
            return 0
        }
    }
    return (gg: tallyFor(points.gg),
            dd: tallyFor(points.dd),
            toto: tallyFor(points.toto))
}

// MARK: - Detailed Scores View

struct MonthGroup: Identifiable {
    let id = UUID()
    let monthName: String
    let tallies: (gg: Int, dd: Int, toto: Int)
    let scores: [GameScore]
}

struct DetailedScoresView: View {
    let year: Int
    @State private var monthGroups: [MonthGroup] = []
    @State private var longestStreakValue: Int = 0
    @State private var longestStreakPlayers: [String] = []
    private let dayColWidth: CGFloat = 70
    private let scoreColWidth: CGFloat = 62
    private let colSpacing: CGFloat = 10

    private var gridWidth: CGFloat {
        dayColWidth + (scoreColWidth * 3) + (colSpacing * 3) // 4 columns => 3 gaps
    }

    var body: some View {
        ZStack {
            // Rounded‑corner background
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )

            VStack(spacing: 10) {
                if longestStreakValue > 0 {
                    HStack {
                        Spacer()
                        (Text("Plus longue série (") + Text("\(longestStreakValue)").bold() + Text("): ") + Text(longestStreakPlayers.joined(separator: ", ")).bold())
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding(.top, 6)
                    .padding(.horizontal, 12)
                }

                List {
                    ForEach(monthGroups) { group in
                        Section(
                            header: monthHeader(group)
                        ) {
                            // Group this month’s games by day
                            let calendar = Calendar.current
                            let byDay = Dictionary(grouping: group.scores) {
                                calendar.component(.day, from: $0.date)
                            }
                            let days = byDay.keys.sorted()

                            ForEach(days, id: \ .self) { day in
                                let dayScores = byDay[day]!.sorted { $0.date < $1.date }

                                ForEach(dayScores) { score in
                                    let pts = calculateGamePoints(for: score)

                                    HStack(alignment: .firstTextBaseline, spacing: colSpacing) {
                                        if score.id == dayScores.first?.id {
                                            Text("\(day)")
                                                .font(.headline)
                                                .frame(width: dayColWidth, alignment: .leading)
                                                .foregroundColor(.secondary)
                                        } else {
                                            Text("")
                                                .frame(width: dayColWidth, alignment: .leading)
                                        }

                                        ScoreValueCell(value: score.ggScore, rankPoints: pts.gg)
                                            .frame(width: scoreColWidth)
                                        ScoreValueCell(value: score.ddScore, rankPoints: pts.dd)
                                            .frame(width: scoreColWidth)
                                        ScoreValueCell(value: score.totoScore, rankPoints: pts.toto)
                                            .frame(width: scoreColWidth)
                                    }
                                    .frame(width: gridWidth, alignment: .leading)          // <- fixed grid
                                    .frame(maxWidth: .infinity, alignment: .center)        // <- centered in row
                                    .padding(.vertical, 4)
                                    .listRowSeparator(.hidden)
                                }

                                Divider()
                            }
                        }
                    }
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .listRowSeparator(.hidden)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding()
        .onAppear { Task { await loadData() } }
        .onChange(of: year) { _ in Task { await loadData() } }
    }
    
    private func computeLongestStreaks(for year: Int, scores: [GameScore]) -> (value: Int, players: [String]) {
        let calendar = Calendar.current
        // Filter scores to the given year
        let yearScores = scores.filter { calendar.component(.year, from: $0.date) == year }

        // Track the maximum consecutive wins observed for each player in the year
        var maxGG = 0
        var maxDD = 0
        var maxToto = 0

        for score in yearScores {
            // Prefer explicit consecutive win fields when available; otherwise fall back to 0.
            if let gg = score.ggConsecutiveWins { maxGG = max(maxGG, gg) }
            if let dd = score.ddConsecutiveWins { maxDD = max(maxDD, dd) }
            if let tt = score.totoConsecutiveWins { maxToto = max(maxToto, tt) }
        }

        // Determine the best value and which players achieved it
        let best = max(maxGG, max(maxDD, maxToto))
        var players: [String] = []
        if best > 0 {
            if maxGG == best { players.append("GG") }
            if maxDD == best { players.append("DD") }
            if maxToto == best { players.append("Toto") }
        }
        return (best, players)
    }

    private func monthHeader(_ group: MonthGroup) -> some View {
        HStack(spacing: colSpacing) {
            Text(group.monthName)
                .font(.headline)
                .frame(width: dayColWidth, alignment: .leading)

            PlayerHeader(title: "GG", points: group.tallies.gg)
                .frame(width: scoreColWidth)
            PlayerHeader(title: "DD", points: group.tallies.dd)
                .frame(width: scoreColWidth)
            PlayerHeader(title: "Toto", points: group.tallies.toto)
                .frame(width: scoreColWidth)
        }
        .frame(width: gridWidth, alignment: .leading)       // <- fixed grid
        .frame(maxWidth: .infinity, alignment: .center)     // <- centered
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
    }

    private func loadData() async {
        let allScores = await ScoresManager.shared.loadScoresSafely(for: year)
        let calendar = Calendar.current
        let yearScores = allScores.filter { calendar.component(.year, from: $0.date) == year }
        
        let longest = computeLongestStreaks(for: year, scores: allScores)
        await MainActor.run {
            self.longestStreakValue = longest.value
            self.longestStreakPlayers = longest.players
        }
        
        // Group by month
        var byMonth: [Int: [GameScore]] = [:]
        for score in yearScores {
            let month = calendar.component(.month, from: score.date)
            byMonth[month, default: []].append(score)
        }
        
        // Build month groups with tallies
        let monthNames = ["Janvier","Février","Mars","Avril","Mai","Juin",
                          "Juillet","Août","Septembre","Octobre","Novembre","Décembre"]
        let groups: [MonthGroup] = byMonth.keys.sorted().compactMap { month in
            let scores = byMonth[month]!.sorted { $0.date < $1.date }
            // Calculate monthly tallies
            var monthlyPoints = (gg: 0, dd: 0, toto: 0)
            for score in scores {
                let p = calculateGamePoints(for: score)
                monthlyPoints.gg += p.gg
                monthlyPoints.dd += p.dd
                monthlyPoints.toto += p.toto
            }
            return MonthGroup(
                monthName: monthNames[month - 1],
                tallies: monthlyPoints,
                scores: scores
            )
        }
        
        await MainActor.run {
            self.monthGroups = groups
        }
    }

    private struct PlayerHeader: View {
        let title: String
        let points: Int

        var body: some View {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("\(points)")
                    .font(.subheadline.weight(.semibold))
                    .padding(.vertical, 2)
                    .padding(.horizontal, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private struct ScoreValueCell: View {
        let value: Int
        let rankPoints: Int

        @Environment(\.colorScheme) private var colorScheme

        private var background: Color {
            let isDark = (colorScheme == .dark)
            switch rankPoints {
            case 2:
                // Stronger highlight for first place in dark mode
                return Color.accentColor.opacity(isDark ? 0.35 : 0.20)
            case 1:
                // Slightly stronger than before in dark mode
                return Color.accentColor.opacity(isDark ? 0.22 : 0.10)
            default:
                return Color.clear
            }
        }

        var body: some View {
            HStack(spacing: 6) {
                Text("\(value)")
                    .font(.body.monospacedDigit())
                    .fontWeight(rankPoints == 2 ? .bold : .regular)
                    .foregroundColor(.primary)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(rankPoints == 2 ? 1 : 0), lineWidth: 1)
            )
        }
    }
}

let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    return formatter
}()

let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "d"   // day of month
    return f
}()

private func aspectFitRect(container: CGSize, imageSize: CGSize) -> CGRect {
    guard container.width > 0, container.height > 0, imageSize.width > 0, imageSize.height > 0 else {
        return .zero
    }

    let scale = min(container.width / imageSize.width, container.height / imageSize.height)
    let fitted = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)

    let origin = CGPoint(
        x: (container.width  - fitted.width)  / 2,
        y: (container.height - fitted.height) / 2
    )

    return CGRect(origin: origin, size: fitted)
}

private let palmaresSize: CGSize = {
    return NSImage(named: "palmares annuel")?.size ?? .init(width: 1, height: 1)
}()

private let firstYear = 2017
private var currentYear: Int {
    Calendar.current.component(.year, from: Date())
}
