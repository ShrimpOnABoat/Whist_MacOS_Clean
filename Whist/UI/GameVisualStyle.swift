//
//  GameVisualStyle.swift
//  Whist
//
//  Shared visual styling for the game table.
//

import SwiftUI

enum GameVisualStyle {
    static let tableHighlight = Color.white.opacity(0.18)
    static let glassFill = Color.white.opacity(0.46)
    static let glassStroke = Color.white.opacity(0.58)
    static let glassHairline = Color.white.opacity(0.24)
    static let primaryAccent = Color(red: 0.24, green: 0.72, blue: 0.34)
    static let warmAccent = Color(red: 1.0, green: 0.79, blue: 0.22)
    static let labelShadow = Color.black.opacity(0.45)
    static let cardShadow = Color.black.opacity(0.30)
    static let cardFaceTint = Color(red: 0.97, green: 0.94, blue: 0.88)

    static func playerAccent(for playerId: PlayerId) -> Color {
        switch playerId {
        case .dd:
            return Color(red: 0.86, green: 0.58, blue: 0.08)
        case .gg:
            return Color(red: 0.05, green: 0.38, blue: 0.86)
        case .toto:
            return Color(red: 0.10, green: 0.58, blue: 0.28)
        }
    }

    static func playerAccentHighlight(for playerId: PlayerId) -> Color {
        switch playerId {
        case .dd:
            return Color(red: 1.0, green: 0.78, blue: 0.18)
        case .gg:
            return Color(red: 0.14, green: 0.56, blue: 1.0)
        case .toto:
            return Color(red: 0.20, green: 0.78, blue: 0.42)
        }
    }

    static func playerAccentShadow(for playerId: PlayerId) -> Color {
        switch playerId {
        case .dd:
            return Color(red: 0.48, green: 0.28, blue: 0.02)
        case .gg:
            return Color(red: 0.02, green: 0.13, blue: 0.42)
        case .toto:
            return Color(red: 0.02, green: 0.26, blue: 0.12)
        }
    }
}

struct GlassPanelModifier: ViewModifier {
    let cornerRadius: CGFloat
    var strokeColor: Color = GameVisualStyle.glassStroke
    var fillOpacity: Double = 1

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(GameVisualStyle.glassFill.opacity(fillOpacity))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 1.2)
            )
            .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
            .shadow(color: Color.white.opacity(0.12), radius: 1, x: 0, y: 1)
    }
}

extension View {
    func gameGlassPanel(cornerRadius: CGFloat, strokeColor: Color = GameVisualStyle.glassStroke, fillOpacity: Double = 1) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, strokeColor: strokeColor, fillOpacity: fillOpacity))
    }
}
