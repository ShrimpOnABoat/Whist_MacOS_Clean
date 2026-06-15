//
//  GameResultView.swift
//  Whist
//
//  Created by Codex on 2026-06-15.
//

import SwiftUI
import AppKit

struct GameResultView: View {
    @EnvironmentObject var gameManager: GameManager
    @ObservedObject var gameState: GameState
    @Binding var showRoundHistory: Bool
    let feltColorIndex: Int
    let dynamicSize: DynamicSize

    @State private var showAllInsights: Bool = false
    @State private var hasTriggeredCelebration: Bool = false

    private var rankedPlayers: [Player] {
        gameState.players.sorted { lhs, rhs in
            let lhsPlace = lhs.place > 0 ? lhs.place : Int.max
            let rhsPlace = rhs.place > 0 ? rhs.place : Int.max
            if lhsPlace != rhsPlace {
                return lhsPlace < rhsPlace
            }
            let lhsScore = lhs.scores.last ?? Int.min
            let rhsScore = rhs.scores.last ?? Int.min
            if lhsScore != rhsScore {
                return lhsScore > rhsScore
            }
            return lhs.username.localizedCaseInsensitiveCompare(rhs.username) == .orderedAscending
        }
    }

    private var winner: Player? {
        if let winnerId = gameManager.lastGameWinner,
           let player = gameState.players.first(where: { $0.id == winnerId }) {
            return player
        }
        return rankedPlayers.first
    }

    private var winnerDisplayName: String {
        (winner?.username ?? "Joueur").uppercased()
    }

    private var primaryActionTitle: String {
        gameManager.hasDeferredStartNewGame ? "Rejoindre la partie" : "Nouvelle partie"
    }

    private var theme: ResultTheme {
        ResultTheme(feltColorIndex: feltColorIndex)
    }

    private var displayedInsightTexts: [String] {
        let primaryFacts = gameManager.latestGameInsightFacts.map(\.text)
        var texts = Array(primaryFacts.prefix(3))

        for fallback in fallbackInsightTexts where texts.count < 3 {
            if !texts.contains(fallback) {
                texts.append(fallback)
            }
        }

        return texts
    }

    private var allInsightTexts: [String] {
        let allFacts = gameManager.latestGameAllInsightFacts.map(\.text)
        return allFacts.isEmpty ? displayedInsightTexts : allFacts
    }

    private var fallbackInsightTexts: [String] {
        let winnerSummary: String = {
            guard let winner else {
                return "La partie est terminee et le resultat final est pret."
            }
            return "\(winner.username.uppercased()) termine en tete avec \(winner.scores.last ?? 0) points."
        }()

        let rankingSummary: String = {
            let ranking = rankedPlayers.map { $0.username.uppercased() }.joined(separator: " • ")
            if ranking.isEmpty {
                return "Le classement final est disponible dans les details."
            }
            return "Classement final : \(ranking)."
        }()

        let roundSummary: String = {
            let visibleRound = max(gameState.round - 2, gameState.round)
            if visibleRound > 0 {
                return "La partie s'est jouee sur \(visibleRound) tours."
            }
            return "Rejoignez la table quand vous etes pret pour la prochaine partie."
        }()

        return [winnerSummary, rankingSummary, roundSummary]
    }

    private var layoutScale: CGFloat {
        min(1.0, max(0.72, dynamicSize.height / 1100))
    }

    private var contentWidth: CGFloat {
        let scaledWidth = dynamicSize.width * 0.76
        return min(940, max(620, scaledWidth)) * layoutScale
    }

    private var podiumWidth: CGFloat {
        let scaledWidth = dynamicSize.width * 0.60
        return min(700, max(460, scaledWidth)) * layoutScale
    }

    private var insightsWidth: CGFloat {
        let scaledWidth = dynamicSize.width * 0.70
        return min(820, max(540, scaledWidth)) * layoutScale
    }

    private var primaryButtonWidth: CGFloat {
        min(380, max(280, dynamicSize.width * 0.32)) * layoutScale
    }

    var body: some View {
        ZStack {
            resultBackdrop

            VStack(spacing: max(16, dynamicSize.proportion * 16) * layoutScale) {
                Spacer(minLength: dynamicSize.height * 0.02)

                heroSection

                insightsSection

                Spacer(minLength: dynamicSize.height * 0.008)

                Button(action: {
                    gameManager.startNewGameAction()
                }) {
                    Text(primaryActionTitle)
                        .font(.system(size: max(18, dynamicSize.proportion * 18) * layoutScale, weight: .semibold))
                        .foregroundColor(.white.opacity(0.98))
                        .padding(.vertical, 12)
                        .frame(width: primaryButtonWidth)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            theme.accentShadow.opacity(0.96),
                                            theme.accent.opacity(0.92),
                                            theme.accentHighlight.opacity(0.74)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(.ultraThinMaterial.opacity(0.24))
                                )
                        )
                        .clipShape(Capsule(style: .continuous))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.80), lineWidth: 1.2)
                        )
                        .shadow(color: theme.accentShadow.opacity(0.46), radius: 14, x: 0, y: 8)
                        .shadow(color: theme.accentHighlight.opacity(0.16), radius: 8, x: 0, y: 2)
                }
                .buttonStyle(GameHoverLiftButtonStyle(isActive: true))
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 2)
                .padding(.bottom, dynamicSize.height * 0.02)
            }
            .padding(.horizontal, dynamicSize.width * 0.05)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showAllInsights) {
            allInsightsSheet
        }
        .onAppear {
            guard !hasTriggeredCelebration else { return }
            hasTriggeredCelebration = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                gameManager.showConfetti.toggle()
                gameManager.playSound(named: "confetti")
            }
        }
    }

    private var resultBackdrop: some View {
        ZStack {
            Color.black.opacity(0.34)
            LinearGradient(
                colors: [
                    Color.black.opacity(0.24),
                    Color.black.opacity(0.08),
                    Color.black.opacity(0.42)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [
                    theme.accentHighlight.opacity(0.16),
                    theme.accent.opacity(0.10),
                    Color.clear
                ],
                center: .center,
                startRadius: 40,
                endRadius: max(dynamicSize.width, dynamicSize.height) * 0.52
            )
            RadialGradient(
                colors: [
                    Color.white.opacity(0.05),
                    Color.clear
                ],
                center: .top,
                startRadius: 10,
                endRadius: dynamicSize.height * 0.42
            )
        }
        .ignoresSafeArea()
    }

    private var heroSection: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: max(12, dynamicSize.proportion * 12) * layoutScale) {
                titleBlock
                podiumSection
            }
            .frame(maxWidth: .infinity)

            detailsButton
                .padding(.top, 2)
        }
        .frame(maxWidth: contentWidth)
    }

    private var titleBlock: some View {
        VStack(spacing: 8) {
            Text("Bravo \(winnerDisplayName)")
                .font(.system(size: max(30, dynamicSize.proportion * 30) * layoutScale, weight: .bold, design: .serif))
                .foregroundColor(GameVisualStyle.warmAccent)
                .shadow(color: Color.black.opacity(0.34), radius: 10, x: 0, y: 6)

            HStack(spacing: 10) {
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 88 * layoutScale, height: 1)
                Image(systemName: "diamond.fill")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(theme.accentHighlight.opacity(0.82))
                Rectangle()
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 88 * layoutScale, height: 1)
            }

            Text("Victoire finale")
                .font(.system(size: max(13, dynamicSize.proportion * 13) * layoutScale, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var detailsButton: some View {
        Button(action: {
            showRoundHistory = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet")
                    .font(.system(size: 10, weight: .semibold))
                Text("Détails")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.white.opacity(0.86))
            .padding(.vertical, 7)
            .padding(.horizontal, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .background(
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial.opacity(0.20))
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.20), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var podiumSection: some View {
        let first = rankedPlayers[safe: 0]
        let second = rankedPlayers[safe: 1]
        let third = rankedPlayers[safe: 2]

        return ZStack(alignment: .bottom) {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            theme.accentHighlight.opacity(0.30),
                            theme.accent.opacity(0.16),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 18,
                        endRadius: podiumWidth * 0.46
                    )
                )
                .frame(width: podiumWidth * 0.66, height: max(40, dynamicSize.proportion * 40) * layoutScale)
                .blur(radius: 16)
                .offset(y: 18 * layoutScale)

            HStack(alignment: .bottom, spacing: max(16, dynamicSize.proportion * 16) * layoutScale) {
                if let second {
                    ResultPodiumStep(
                        player: second,
                        rank: 2,
                        theme: theme,
                        avatarSize: max(74, dynamicSize.proportion * 74) * layoutScale,
                        pedestalWidth: max(138, dynamicSize.proportion * 138) * layoutScale,
                        pedestalHeight: max(54, dynamicSize.proportion * 54) * layoutScale,
                        highlight: false
                    )
                }

                if let first {
                    ResultPodiumStep(
                        player: first,
                        rank: 1,
                        theme: theme,
                        avatarSize: max(92, dynamicSize.proportion * 92) * layoutScale,
                        pedestalWidth: max(184, dynamicSize.proportion * 184) * layoutScale,
                        pedestalHeight: max(82, dynamicSize.proportion * 82) * layoutScale,
                        highlight: true
                    )
                }

                if let third {
                    ResultPodiumStep(
                        player: third,
                        rank: 3,
                        theme: theme,
                        avatarSize: max(74, dynamicSize.proportion * 74) * layoutScale,
                        pedestalWidth: max(138, dynamicSize.proportion * 138) * layoutScale,
                        pedestalHeight: max(54, dynamicSize.proportion * 54) * layoutScale,
                        highlight: false
                    )
                }
            }
        }
        .frame(width: podiumWidth)
    }

    private var insightsSection: some View {
        VStack(alignment: .leading, spacing: max(10, dynamicSize.proportion * 10) * layoutScale) {
            VStack(spacing: 10) {
                ForEach(Array(displayedInsightTexts.enumerated()), id: \.offset) { index, text in
                    insightRow(index: index + 1, text: text)
                }
            }

            Button(action: {
                showAllInsights = true
            }) {
                HStack(spacing: 8) {
                    Text("Plus")
                        .font(.system(size: 15, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(theme.accentHighlight)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 2)
        }
        .frame(width: insightsWidth, alignment: .leading)
    }

    private func insightRow(index: Int, text: String) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text("\(index)")
                .font(.system(size: max(18, dynamicSize.proportion * 18) * layoutScale, weight: .bold, design: .rounded))
                .foregroundColor(theme.accentHighlight)
                .monospacedDigit()
                .frame(width: 24, alignment: .center)

            Rectangle()
                .fill(Color.white.opacity(0.16))
                .frame(width: 1, height: 24 * layoutScale)

            Text(text)
                .font(.system(size: max(14, dynamicSize.proportion * 14) * layoutScale, weight: .medium))
                .foregroundColor(.white.opacity(0.95))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.08))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private var allInsightsSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Tous les insights")
                .font(.title2.bold())
                .foregroundColor(.white)

            if allInsightTexts.isEmpty {
                Text("Aucun insight disponible pour cette partie.")
                    .foregroundColor(.white.opacity(0.88))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(allInsightTexts.enumerated()), id: \.offset) { index, text in
                            Text("\(index + 1). \(text)")
                                .foregroundColor(.white.opacity(0.95))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(minWidth: 680, minHeight: 520)
        .background(Color.black.opacity(0.90))
    }
}

private struct ResultPodiumStep: View {
    let player: Player
    let rank: Int
    let theme: ResultTheme
    let avatarSize: CGFloat
    let pedestalWidth: CGFloat
    let pedestalHeight: CGFloat
    let highlight: Bool

    private var scoreValue: Int {
        player.scores.last ?? 0
    }

    private var scoreDisplay: String {
        scoreValue > 0 ? "+\(scoreValue)" : "\(scoreValue)"
    }

    private var topCapHeight: CGFloat {
        max(14, pedestalHeight * 0.20)
    }

    private var bodyGradient: LinearGradient {
        LinearGradient(
            colors: [
                theme.bodyTop,
                theme.bodyMid,
                theme.bodyBottom
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var topGradient: LinearGradient {
        if highlight {
            return LinearGradient(
                colors: [
                    theme.championTopLight,
                    theme.championTopMid,
                    theme.championTopDark
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        if rank == 2 {
            return LinearGradient(
                colors: [
                    theme.silverTopLight,
                    theme.silverTopMid,
                    theme.silverTopDark
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }

        return LinearGradient(
            colors: [
                theme.bronzeTopLight,
                theme.bronzeTopMid,
                theme.bronzeTopDark
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    var body: some View {
        VStack(spacing: max(6, avatarSize * 0.06)) {
            ResultAvatarView(player: player, size: avatarSize, highlight: highlight)

            Text(scoreDisplay)
                .font(.system(size: max(17, avatarSize * 0.18), weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(highlight ? 0.96 : 0.88))
                .monospacedDigit()
                .shadow(color: Color.black.opacity(0.26), radius: 6, x: 0, y: 3)
                .frame(height: max(20, avatarSize * 0.22))

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: pedestalHeight * 0.26, style: .continuous)
                    .fill(bodyGradient)
                    .frame(width: pedestalWidth, height: pedestalHeight)
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                Color.clear,
                                Color.black.opacity(0.18)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .clipShape(RoundedRectangle(cornerRadius: pedestalHeight * 0.26, style: .continuous))
                    )
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.10),
                                Color.clear,
                                Color.black.opacity(0.16)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: pedestalHeight * 0.26, style: .continuous))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: pedestalHeight * 0.26, style: .continuous)
                            .strokeBorder(Color.white.opacity(highlight ? 0.22 : 0.14), lineWidth: 1)
                    )
                    .shadow(color: theme.accentShadow.opacity(0.34), radius: 22, x: 0, y: 14)

                Ellipse()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: pedestalWidth * 0.84, height: topCapHeight * 0.70)
                    .blur(radius: 5)
                    .offset(y: topCapHeight * 0.16)

                Ellipse()
                    .fill(topGradient)
                    .frame(width: pedestalWidth * (highlight ? 0.90 : 0.92), height: topCapHeight)
                    .overlay(
                        Ellipse()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.28),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .padding(1)
                    )
                    .overlay(
                        Ellipse()
                            .strokeBorder(Color.white.opacity(0.30), lineWidth: 1)
                    )
                    .shadow(color: theme.accentShadow.opacity(0.18), radius: 7, x: 0, y: 4)
                    .offset(y: -topCapHeight * 0.34)

                Text("\(rank)")
                    .font(.system(size: max(24, pedestalHeight * 0.42), weight: .bold, design: .serif))
                    .foregroundColor(highlight ? GameVisualStyle.warmAccent.opacity(0.92) : rank == 2 ? Color.white.opacity(0.82) : Color(nsColor: NSColor(calibratedRed: 0.69, green: 0.45, blue: 0.30, alpha: 1.0)))
                    .monospacedDigit()
                    .frame(width: pedestalWidth, height: pedestalHeight, alignment: .center)
                    .offset(y: pedestalHeight * 0.08)
            }
            .frame(width: pedestalWidth, height: pedestalHeight + topCapHeight * 0.55)
        }
        .frame(width: pedestalWidth)
    }
}

private struct ResultAvatarView: View {
    let player: Player
    let size: CGFloat
    let highlight: Bool

    private var avatarColor: Color {
        GameVisualStyle.playerAccent(for: player.id)
    }

    private var avatarHighlight: Color {
        GameVisualStyle.playerAccentHighlight(for: player.id)
    }

    private var avatarShadow: Color {
        GameVisualStyle.playerAccentShadow(for: player.id)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            avatarHighlight,
                            avatarColor,
                            avatarShadow
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .blendMode(.softLight)
                )

            (player.image ?? Image(systemName: "person.crop.circle"))
                .resizable()
                .scaledToFit()
                .padding(size * 0.06)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(Color.white.opacity(highlight ? 0.96 : 0.90), lineWidth: highlight ? 3 : 2)
        )
        .overlay(
            Circle()
                .strokeBorder(highlight ? GameVisualStyle.warmAccent.opacity(0.84) : Color.clear, lineWidth: 4)
                .padding(-3)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 14, x: 0, y: 8)
    }
}

private struct ResultTheme {
    let accent: Color
    let accentHighlight: Color
    let accentShadow: Color
    let bodyTop: Color
    let bodyMid: Color
    let bodyBottom: Color
    let silverTopLight: Color
    let silverTopMid: Color
    let silverTopDark: Color
    let bronzeTopLight: Color
    let bronzeTopMid: Color
    let bronzeTopDark: Color
    let championTopLight: Color
    let championTopMid: Color
    let championTopDark: Color

    init(feltColorIndex: Int) {
        let clampedIndex = max(0, min(feltColorIndex, GameConstants.feltColors.count - 1))
        let base = NSColor(GameConstants.feltColors[clampedIndex]).deviceRGB
        let white = NSColor.white
        let black = NSColor.black
        let gold = NSColor(GameVisualStyle.warmAccent).deviceRGB

        let accentBase = base.mixed(with: white, amount: 0.36)
        let accentLight = base.mixed(with: white, amount: 0.56)
        let accentDark = base.mixed(with: black, amount: 0.62)
        let accentDeeper = base.mixed(with: black, amount: 0.78)

        self.accent = Color(nsColor: accentBase)
        self.accentHighlight = Color(nsColor: accentLight)
        self.accentShadow = Color(nsColor: accentDark)

        self.bodyTop = Color(nsColor: accentDark.mixed(with: white, amount: 0.08))
        self.bodyMid = Color(nsColor: accentDeeper)
        self.bodyBottom = Color(nsColor: accentDeeper.mixed(with: black, amount: 0.10))

        let silverBase = NSColor(calibratedRed: 0.79, green: 0.86, blue: 0.89, alpha: 1.0)
        let silverHighlight = NSColor(calibratedRed: 0.94, green: 0.98, blue: 0.99, alpha: 1.0)
        let silverShadow = NSColor(calibratedRed: 0.54, green: 0.63, blue: 0.68, alpha: 1.0)

        let bronzeBase = NSColor(calibratedRed: 0.69, green: 0.45, blue: 0.30, alpha: 1.0)
        let bronzeHighlight = NSColor(calibratedRed: 0.86, green: 0.66, blue: 0.50, alpha: 1.0)
        let bronzeShadow = NSColor(calibratedRed: 0.42, green: 0.24, blue: 0.14, alpha: 1.0)

        self.silverTopLight = Color(nsColor: silverHighlight.mixed(with: accentLight, amount: 0.12))
        self.silverTopMid = Color(nsColor: silverBase.mixed(with: accentBase, amount: 0.10))
        self.silverTopDark = Color(nsColor: silverShadow.mixed(with: accentDark, amount: 0.12))

        self.bronzeTopLight = Color(nsColor: bronzeHighlight.mixed(with: accentLight, amount: 0.10))
        self.bronzeTopMid = Color(nsColor: bronzeBase.mixed(with: accentBase, amount: 0.08))
        self.bronzeTopDark = Color(nsColor: bronzeShadow.mixed(with: accentDark, amount: 0.12))

        self.championTopLight = Color(nsColor: gold.mixed(with: accentLight, amount: 0.18).mixed(with: white, amount: 0.10))
        self.championTopMid = Color(nsColor: gold.mixed(with: accentBase, amount: 0.20))
        self.championTopDark = Color(nsColor: gold.mixed(with: accentDark, amount: 0.26))
    }
}

private extension NSColor {
    var deviceRGB: NSColor {
        usingColorSpace(.deviceRGB) ?? self
    }

    func mixed(with other: NSColor, amount: CGFloat) -> NSColor {
        let lhs = self.deviceRGB
        let rhs = other.deviceRGB
        let clamped = min(max(amount, 0), 1)

        return NSColor(
            calibratedRed: lhs.redComponent + (rhs.redComponent - lhs.redComponent) * clamped,
            green: lhs.greenComponent + (rhs.greenComponent - lhs.greenComponent) * clamped,
            blue: lhs.blueComponent + (rhs.blueComponent - lhs.blueComponent) * clamped,
            alpha: lhs.alphaComponent + (rhs.alphaComponent - lhs.alphaComponent) * clamped
        )
    }
}
