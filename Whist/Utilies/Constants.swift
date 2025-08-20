//
//  constants.swift
//  Whist
//
//  Created by Tony Buffard on 2024-11-18.
//  Application-wide constants.

import Foundation
import SwiftUI

struct GameConstants {
    // Cards
    static let deckOffset = CGPoint(x: 0.25, y: -0.25)
    static let deckShuffleOffset: CGFloat = 50
    static let deckShuffleAngle: Double = 15
    static let deckShuffleDuration: TimeInterval = 0.9
    static var deckCardsScale: CGFloat { 2 / 3 }
    static var sidePlayerCardScale: CGFloat { 2 / 3 }
    static var localPlayerCardScale: CGFloat = 1.0
    static var trickScale: CGFloat { 1 / 3 }
    static var trickOverlap: CGFloat = 0.7

    // Animation Durations
    static let cardMoveDuration: TimeInterval = 0.5
    static let optionsRandomDuration: TimeInterval = 1
    
    // Background related constants
    static let feltColors: [Color] = [
        Color(red: 34 / 255, green: 139 / 255, blue: 34 / 255), // Classic Green
        Color(red: 0 / 255, green: 0 / 255, blue: 139 / 255),   // Deep Blue
        Color(red: 139 / 255, green: 0 / 255, blue: 0 / 255),   // Wine Red
        Color(red: 75 / 255, green: 0 / 255, blue: 130 / 255),  // Royal Purple
        Color(red: 0 / 255, green: 128 / 255, blue: 128 / 255), // Teal
        Color(red: 54 / 255, green: 69 / 255, blue: 79 / 255),  // Charcoal Gray
        Color(red: 205 / 255, green: 92 / 255, blue: 0 / 255),  // Burnt Orange
        Color(red: 34 / 255, green: 90 / 255, blue: 34 / 255),  // Forest Green
        Color(red: 139 / 255, green: 69 / 255, blue: 19 / 255), // Chocolate Brown
        Color(red: 220 / 255, green: 20 / 255, blue: 60 / 255)  // Crimson Red
    ]
}

// Dynamic UI-related constants
struct DynamicSize {
    let width: CGFloat
    let height: CGFloat
    let widthProportion: CGFloat
    let heightProportion: CGFloat
    let proportion: CGFloat
    
    init(from geometry: GeometryProxy) {
        self.width = geometry.size.width
        self.height = geometry.size.height
        self.widthProportion = width / 800
        self.heightProportion = height / 600
        self.proportion = min(widthProportion, heightProportion)
    }
    
    // Game Views
    var localPlayerWidth: CGFloat { width * 0.5 } // 25% of total width
    var localPlayerHeight: CGFloat { height * 0.33 } // 58% of total height
    var sidePlayerWidth: CGFloat { width * 0.25 } // 25% of total width
    var sidePlayerHeight: CGFloat { height * 0.58 } // 58% of total height
    
    // Table View
    var tableWidth: CGFloat { width * 0.5 } // 50% of total width
    var tableHeight: CGFloat { height * 0.35 } // 30% of total height
    var tableOffset: CGFloat { proportion * 40 }
    
    // Scoreboard
    var scoreboardWidth: CGFloat { width * 0.5 }
    var scoreboardHeight: CGFloat { height * 0.25 }
    var vstackScoreSpacing: CGFloat { proportion * 10 }
    var roundSize: CGFloat { proportion * 20 }
    var nameSize: CGFloat { proportion * 14 }
    var scoreSize: CGFloat { proportion * 12 }
    var announceSize: CGFloat { proportion * 20 }
    var dotSize: CGFloat { proportion * 6 }
    
    // Cards attributes
    var cardWidth: CGFloat { proportion * 90 }
    var cardHeight: CGFloat { proportion * 135 }
    var cardShadowRadius: CGFloat = 2
    var cardHoverOffset: CGFloat = 20

    // Player View
    var sidePlayerHandWidth: CGFloat { sidePlayerWidth * 0.5 }
    var sidePlayerHandHeight: CGFloat { sidePlayerHeight * 0.8 }
    var sidePlayerStateYOffset: CGFloat { proportion * -20 }
    var sidePlayerInfoWidth: CGFloat { sidePlayerWidth }
    let localFanRadius: CGFloat = 500
    let minLocalCardAngle: CGFloat = 5
    let sideFanRadius: CGFloat = 300
    let minSideCardAngle: CGFloat = 5
    var playerViewHorizontalSpacing: CGFloat { widthProportion * 30 }
    var localPlayerHandWidth: CGFloat { localPlayerWidth * 1 }
    var localPlayerHandHeight: CGFloat { localPlayerHeight * 0.5 }
    var localPlayerStateWidth: CGFloat { localPlayerWidth * 0.25 }
    var localPlayerStateHeight: CGFloat { localPlayerHeight * 0.25 }
    var localPlayerInfoWidth: CGFloat { localPlayerWidth * 1 }
    var localPlayerInfoHeight: CGFloat { localPlayerHeight * 0.25 }
    var localPlayerTrickWidth: CGFloat { localPlayerWidth * 0.25 }
    var localPlayerTrickHeight: CGFloat { localPlayerHeight * 0.25 }
    var playerImageWidth: CGFloat { proportion * 80 }
    var playerImageHeight: CGFloat { proportion * 80 }
    var otherTrickSpacing: CGFloat { heightProportion * 5 }
    var localTrickSpacing: CGFloat { widthProportion * 5 }
    var stateTextSize: CGFloat { proportion * 12 }
    
    // Dealer button
    var dealerButtonSize: CGFloat { 50 * proportion }
    var dealerButtonLocalOffset: CGSize { CGSize(width: 0, height: proportion * 50) }
    var dealerButtonLeftOffset: CGSize { CGSize(width: proportion * -50, height: 0) }
    var dealerButtonRightOffset: CGSize { CGSize(width: proportion * 50, height: 0) }
    
    // Betting options
    var optionsVerticalSpacing : CGFloat { 20 * proportion }
    var optionsButtonSize: CGFloat { 40 * proportion }
}
