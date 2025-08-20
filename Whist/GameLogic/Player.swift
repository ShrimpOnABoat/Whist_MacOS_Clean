//
//  Player.swift
//  Whist
//
//  Created by Tony Buffard on 2024-11-18.
//  Represents a player's state and actions.

import Foundation
import SwiftUI

enum TablePosition: String, Codable {
    case local
    case left
    case right
}

enum PlayerState: String, Codable {
    case idle
    case startNewGame
    case choosingTrump
    case bidding
    case discarding
    case playing
    case waiting
    
    var message: String {
        switch self {
        case .idle: return "Idle"
        case .startNewGame: return "Starting New Game"
        case .choosingTrump: return "Choosing Trump"
        case .bidding: return "Bidding"
        case .discarding: return "Discarding"
        case .playing: return "Playing"
        case .waiting: return "Waiting"
        }
    }
}

enum P2PConnectionPhase: String, CaseIterable {
    case idle = "Idle" // Initial state, or connection not yet attempted
    case initiating = "Initiating..." // Deciding to offer/answer or checking presence
    case offering = "Sending Offer..."
    case waitingForOffer = "Waiting for Offer..."
    case answering = "Sending Answer..."
    case waitingForAnswer = "Waiting for Answer..."
    case exchangingNetworkInfo = "Exchanging Network Info..." // ICE exchange
    case connecting = "Connecting..." // ICE connected, DTLS handshake
    case iceReconnecting = "ICE Reconnecting..." 
    case connected = "Connected"
    case failed = "Failed"
    case disconnected = "Disconnected"
}

class Player: Identifiable, ObservableObject, Codable {
    
    // Use PlayerId enum for the player's unique identifier
    let id: PlayerId
    
    // Player properties
    @Published var username: String
    @Published var scores: [Int] = []
    @Published var announcedTricks: [Int] = []
    @Published var madeTricks: [Int] = []
    @Published var monthlyLosses: Int = 0
    @Published var bonusCards: Int = 0
    @Published var onlyWins: Bool = true
    @Published var onlyWinsBonus: Bool = false
    @Published var firebasePresenceOnline: Bool = false // for UI
    @Published var connectionPhase: P2PConnectionPhase = .idle {
        didSet {
            logger.debug("🏀🏀🏀 \(id)'s connection phase is now \(connectionPhase)")
        }
    }
    @Published var place: Int = -1 // Player's rank (1, 2, or 3)
    @Published var hand: [Card] = []
    @Published var trickCards: [Card] = []
    @Published var tablePosition: TablePosition? //= .local - Transient, recalculated
    @Published var state: PlayerState = .idle
    var hasDiscarded: Bool = false
    
    // Image is not codable; handle separately if needed
    @Published var image: Image?
    @Published var imageBackgroundColor: Color?
    
    var isP2PConnected: Bool {
        connectionPhase == .connected
    }
    
    init(id: PlayerId, username: String? = nil, image: Image? = nil) {
        self.id = id
        self.username = username ?? id.rawValue
        self.image = image
        // Default values for other properties are handled by their declarations
    }
    
    // MARK: - Codable Conformance
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case scores
        case announcedTricks
        case madeTricks
        case monthlyLosses
        case bonusCards
        case place
        case state
        case hand
        case trickCards
        case hasDiscarded
        // Exclude 'image' and 'tablePosition' as they are transient or recalculated
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode all codable properties
        id = try container.decode(PlayerId.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        scores = try container.decode([Int].self, forKey: .scores)
        announcedTricks = try container.decode([Int].self, forKey: .announcedTricks)
        madeTricks = try container.decode([Int].self, forKey: .madeTricks)
        monthlyLosses = try container.decode(Int.self, forKey: .monthlyLosses)
        bonusCards = try container.decode(Int.self, forKey: .bonusCards)
        place = try container.decode(Int.self, forKey: .place) // ADD: Decode place
        hand = try container.decode([Card].self, forKey: .hand)
        trickCards = try container.decode([Card].self, forKey: .trickCards)
        state = try container.decode(PlayerState.self, forKey: .state)
        hasDiscarded = try container.decode(Bool.self, forKey: .hasDiscarded)
        
        // Transient properties are not decoded; handle image loading/table position/connection separately if needed post-load
        image = nil // Image is always nil after decoding
        tablePosition = nil // tablePosition recalculated later
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        // Encode all codable properties
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(scores, forKey: .scores)
        try container.encode(announcedTricks, forKey: .announcedTricks)
        try container.encode(madeTricks, forKey: .madeTricks)
        try container.encode(monthlyLosses, forKey: .monthlyLosses)
        try container.encode(bonusCards, forKey: .bonusCards)
        try container.encode(place, forKey: .place) // ADD: Encode place
        try container.encode(hand, forKey: .hand)
        try container.encode(trickCards, forKey: .trickCards)
        try container.encode(state, forKey: .state)
        try container.encode(hasDiscarded, forKey: .hasDiscarded)
        
        // 'image' and 'tablePosition' are not encoded
    }
}

extension Player: CustomStringConvertible {
    var description: String {
        return username
    }
}
