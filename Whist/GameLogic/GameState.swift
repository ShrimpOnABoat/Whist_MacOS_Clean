//
//  GameState.swift
//  Whist
//
//  Created by Tony Buffard on 2024-11-18.
//  Represents the overall game state.

import Foundation
import SwiftUI

class GameState: ObservableObject, Codable, @unchecked Sendable {
    @Published var round: Int = 0 // 1 is the first round, 12 is the last (12th) one
    @Published var deck: [Card] = []
    var newDeck: [Card] = [] // Used to store the deck from the dealer - DO NOT SAVE
    @Published var trumpCards: [Card] = []
    @Published var table: [Card] = [] // Must be [] after each trick grab. It follows the same order as in playOrder
    @Published var lastTrick: [PlayerId: Card] = [:]
    @Published var lastTrickCardStates: [PlayerId: CardState] = [:] // UI State - DO NOT SAVE
    @Published var players: [Player] = []
    @Published var trumpSuit: Suit? = nil
    @Published var playOrder: [PlayerId] = [] // should be reset after each trick grab
    @Published var dealer: PlayerId? = nil {
        didSet {
            logger.log("💟💟 The dealer is now \(dealer?.rawValue ?? "nobody!") 💟💟")
        }
    }
    @Published var currentPhase: GamePhase = .waitingForPlayers
    // ADD: Add properties to be saved
    @Published var tricksGrabbed: [Bool] = []
    @Published var currentTrick: Int = 0

    // MARK: - Codable Conformance
    enum CodingKeys: String, CodingKey {
        case round
        case deck
        case trumpCards
        case table
        case lastTrick
        case players
        case trumpSuit
        case playOrder
        case dealer
        case currentPhase
        case tricksGrabbed
        case currentTrick
    }

    // Custom initializer (ensure it initializes new properties)
    init(round: Int = 0, deck: [Card] = [], trumpCards: [Card] = [Card(suit: .clubs, rank: .two), Card(suit: .spades, rank: .two), Card(suit: .diamonds, rank: .two), Card(suit: .hearts, rank: .two)], table: [Card] = [], players: [Player] = [], trumpSuit: Suit? = nil, playOrder: [PlayerId] = [], dealer: PlayerId? = nil, currentPhase: GamePhase = .waitingForPlayers, tricksGrabbed: [Bool] = [], currentTrick: Int = 0) { // ADD: Added new properties
        self.round = round
        self.deck = deck
        self.trumpCards = trumpCards // Ensure this is set
        self.table = table
        self.players = players
        self.trumpSuit = trumpSuit
        self.playOrder = playOrder
        self.dealer = dealer
        self.currentPhase = currentPhase // Ensure this is set
        self.tricksGrabbed = tricksGrabbed
        self.currentTrick = currentTrick
        if players.isEmpty { self.createDefaultPlayers() }
    }

    // Decodable
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        round = try container.decode(Int.self, forKey: .round)
        deck = try container.decode([Card].self, forKey: .deck)
        trumpCards = try container.decode([Card].self, forKey: .trumpCards) // ADD: Decode trumpCards
        table = try container.decode([Card].self, forKey: .table)
        lastTrick = try container.decode([PlayerId: Card].self, forKey: .lastTrick)
        players = try container.decode([Player].self, forKey: .players) // Assumes Player is Codable
        trumpSuit = try container.decodeIfPresent(Suit.self, forKey: .trumpSuit)
        playOrder = try container.decode([PlayerId].self, forKey: .playOrder)
        dealer = try container.decodeIfPresent(PlayerId.self, forKey: .dealer)
        currentPhase = try container.decode(GamePhase.self, forKey: .currentPhase)
        // ADD: Decode new properties
        tricksGrabbed = try container.decode([Bool].self, forKey: .tricksGrabbed)
        currentTrick = try container.decode(Int.self, forKey: .currentTrick)

        if players.isEmpty { self.createDefaultPlayers() }
        // Note: lastTrickCardStates and newDeck are not decoded as they are transient/UI state
    }

    // Encodable
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(round, forKey: .round)
        try container.encode(deck, forKey: .deck)
        try container.encode(trumpCards, forKey: .trumpCards) // ADD: Encode trumpCards
        try container.encode(table, forKey: .table)
        try container.encode(lastTrick, forKey: .lastTrick)
        try container.encode(players, forKey: .players) // Assumes Player is Codable
        try container.encodeIfPresent(trumpSuit, forKey: .trumpSuit)
        try container.encode(playOrder, forKey: .playOrder)
        try container.encodeIfPresent(dealer, forKey: .dealer)
        try container.encode(currentPhase, forKey: .currentPhase)
        // ADD: Encode new properties
        try container.encode(tricksGrabbed, forKey: .tricksGrabbed)
        try container.encode(currentTrick, forKey: .currentTrick)
        // Note: lastTrickCardStates and newDeck are not encoded
    }

    // MARK: - Player Creation
    private func createDefaultPlayers() {
        let allPossiblePlayers: [PlayerId] = [.dd, .gg, .toto]

        for playerID in allPossiblePlayers {
            // Assign placeholder images for players based on their IDs
            let placeholderImage: Image
            let background: Color
            switch playerID {
            case .dd:
//                placeholderImage = Image(systemName: "figure.pool.swim.circle.fill")
                placeholderImage = Image("dd")
                background = Color.yellow
            case .gg:
//                placeholderImage = Image(systemName: "safari.fill")
                placeholderImage = Image("gg")
                background = Color.blue
            case .toto:
//                placeholderImage = Image(systemName: "figure.run.treadmill.circle.fill")
                placeholderImage = Image("toto")
                background = Color.green
            }

            // Add the player to the game state
            let newPlayer = Player(id: playerID, image: placeholderImage)
            newPlayer.firebasePresenceOnline = false
            newPlayer.imageBackgroundColor = background
            players.append(newPlayer)
        }
    }

    // MARK: - Helper Methods
    
    // Get cards in a player's hand
    func getPlayerHand(playerId: PlayerId) -> [Card] {
        let player = getPlayer(by: playerId)
        return player.hand
    }
    
    // Method to update player references
    func updatePlayerReferences() {
        if let localPlayerId = localPlayer?.id,
           let localIndex = playOrder.firstIndex(of: localPlayerId) {
            for (index, playerId) in playOrder.enumerated() {
                if let player = players.first(where: { $0.id == playerId }) {
                    if index == localIndex {
                        player.tablePosition = .local
                    } else if index == (localIndex + 1) % playOrder.count {
                        player.tablePosition = .left
                    } else if index == (localIndex + playOrder.count - 1) % playOrder.count {
                        player.tablePosition = .right
                    }
                    // ADD: Ensure other players don't have conflicting table positions if not in playOrder?
                    // Or handle the 'unknown' position explicitly if needed.
                }
            }
        } else {
            // CHANGE: Log a warning instead of crashing.
            // This could happen temporarily during state loading before playOrder is fully set.
            if let localPlayerId = localPlayer?.id {
                logger.log("Warning: Local player ID \(localPlayerId) found but not present in playOrder \(playOrder). Table positions might be incorrect temporarily.")
            } else {
                logger.log("Warning: Could not find local player (tablePosition == .local) to update references.")
            }
            // Consider resetting all positions to unknown if this state is invalid.
            // players.forEach { $0.tablePosition = .unknown }
        }
        logger.log("Players references updated!")
    }
    /// Verifies the game state before saving. Returns an array of error messages (empty if valid).
    func checkIntegrity() -> [String] {
        var errors: [String] = []
        
        // 1. Round within valid bounds
        if round < 0 || round > 12 {
            errors.append("Round \(round) is out of valid range (0...12).")
        }
        
        // 2. All 36 cards accounted for and no duplicates
        var allCards = deck
        players.forEach { allCards.append(contentsOf: $0.hand) }
        players.forEach { allCards.append(contentsOf: $0.trickCards) }
        allCards.append(contentsOf: table)
        allCards.append(contentsOf: trumpCards)
        allCards.append(contentsOf: lastTrick.values)
        
        if allCards.count != 36 {
            errors.append("Total card count is \(allCards.count), expected 36.")
        }
        
        // 3. Trump cards must include the four twos
        let expectedTwos = [Suit.clubs, .spades, .diamonds, .hearts].map { Card(suit: $0, rank: .two) }
        expectedTwos.forEach { two in
            if !trumpCards.contains(two) {
                errors.append("Missing \(two.rank) of \(two.suit) in trumpCards.")
            }
        }
        
        // 4. playOrder must list all players exactly once
        let playerIds = Set(players.map { $0.id })
        let playOrderSet = Set(playOrder)
        if playOrderSet != playerIds {
            errors.append("playOrder \(playOrder) does not include exactly all players: \(playerIds).")
        }
        
        // 5. Dealer must be set and valid
        if let dealerId = dealer {
            if !playerIds.contains(dealerId) {
                errors.append("Dealer \(dealerId) is not among players.")
            }
        } else {
            errors.append("Dealer is not defined.")
        }
        
        return errors
    }
}

extension GameState {
    /// Returns the first Card matching the given suit and rank from all relevant locations.
    func getCard(suit: Suit, rank: Rank) -> Card? {
        let allCards = deck
            + trumpCards
            + table
            + players.flatMap { $0.hand + $0.trickCards }
            + Array(lastTrick.values)
        return allCards.first { $0.suit == suit && $0.rank == rank }
    }
}

extension GameState {
    func getPlayer(by id: PlayerId) -> Player {
        guard let player = players.first(where: { $0.id == id }) else {
            logger.fatalErrorAndLog("Error: Player with ID \(id.rawValue) not found.")
        }
        return player
    }
    
    func getPlayerId(username: String) -> PlayerId {
        guard let player = players.first(where: { $0.username == username}) else {
            logger.fatalErrorAndLog( "Error: Player with username \(username) not found.")
        }
        return player.id
    }
}

extension GameState {
    var localPlayer: Player? {
        players.first(where: { $0.tablePosition == .local })
    }
    
    var leftPlayer: Player? {
        players.first(where: { $0.tablePosition == .left })
    }
    
    var rightPlayer: Player? {
        players.first(where: { $0.tablePosition == .right })
    }
    
    var lastPlayer: Player? {
        players.first(where: { $0.place == 3 })
    }
    
    var allPlayersConnected: Bool {
        // Only consider non-local players for connectivity
        players
            .filter { $0.tablePosition != .local }
            .allSatisfy(\.isP2PConnected)
    }
    
    func bonusCardsNeeded(for playerId: PlayerId) -> Int {
        guard let player = players.first(where: { $0.id == playerId }) else { return 0 }

        var extraCards = 0

        if round > 3 {
            if player.place == 2 {
                if player.monthlyLosses > 1 && round < 12 {
                    extraCards = 2
                } else {
                    extraCards = 1
                }
            } else if player.place == 3 {
                extraCards = 1
                let playerScore = player.scores[safe: round - 2] ?? 0
                let secondPlayerScore = players[safe: 1]?.scores[safe: round - 2] ?? 0

                if player.monthlyLosses > 0 || Double(playerScore) <= 0.5 * Double(secondPlayerScore) {
                    extraCards = 2
                }
            }
        }

        return extraCards
    }
    
    func playerPlaced(_ place: Int) -> Player? {
        guard place >= 1 && place <= 3 else { return nil }
        return players.first(where: { $0.place == place })
    }
}

extension GameState: CustomDebugStringConvertible {
    var debugDescription: String {
        var desc = "📦 GameState Snapshot:\n"
        desc += "- Phase: \(currentPhase)\n"
        desc += "- Round: \(round)\n"
        desc += "- Trump Suit: \(String(describing: trumpSuit))\n"
        desc += "- Players:\n"
        for player in players {
            desc += "  • \(player.username) (\(player.id)) - state: \(player.state) - place: \(player.place), scores: \(player.scores), tablePosition: \(String(describing: player.tablePosition)), isPresent: \(player.firebasePresenceOnline)\n"
        }
        return desc
    }
}
