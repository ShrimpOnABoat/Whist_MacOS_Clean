import Foundation
import Testing
@testable import Whist

@MainActor
struct PlayerStatusRegressionTests {
    @Test(arguments: PlayerId.allCases)
    func onlinePlayersCanJoinWithoutDirectConnections(localID: PlayerId) {
        let state = GameState()
        state.getPlayer(by: localID).tablePosition = .local
        for player in state.players where player.id != localID {
            player.firebasePresenceOnline = true
            player.connectionPhase = .failed
        }

        #expect(state.allPlayersConnected)
        let remotePlayers = state.players.filter { $0.id != localID }
        #expect(remotePlayers.allSatisfy { $0.isOnline })
        state.players.first { $0.id != localID }?.firebasePresenceOnline = false
        #expect(!state.allPlayersConnected)
    }

    @Test func lobbyWaitsForLocalIdentityAndOfflinePeers() {
        let state = GameState()
        state.players.forEach { $0.firebasePresenceOnline = true }
        #expect(!state.allPlayersConnected)
        state.getPlayer(by: .dd).tablePosition = .local
        state.getPlayer(by: .gg).firebasePresenceOnline = false
        #expect(!state.allPlayersConnected)
        state.getPlayer(by: .gg).connectionPhase = .connected
        #expect(state.allPlayersConnected)
    }

    @Test func latestActionStatusArrivesWithoutAPeerMessage() {
        let presence = PresenceManager()
        let manager = makeManager()
        presence.onPeerPresenceChanged = { id, online in
            manager.gameState.getPlayer(by: id).firebasePresenceOnline = online
        }
        presence.onPeerStateChanged = { id, state in
            manager.updatePlayerWithState(from: id, with: state)
        }
        presence.handlePeerStatus(["online": true, "sessionId": "toto-session", "state": "choosingTrump"], for: .toto)
        presence.handlePeerStatus(["online": true, "sessionId": "gg-session", "state": "bidding"], for: .gg)

        #expect(manager.gameState.getPlayer(by: .toto).isOnline)
        #expect(manager.gameState.getPlayer(by: .toto).state == .choosingTrump)
        #expect(manager.gameState.getPlayer(by: .gg).state == .bidding)
        #expect(manager.gameState.players.allSatisfy { !$0.isP2PConnected })
    }

    @Test func restartedPeerCleansUpBeforeRestoringItsLatestStatus() {
        let presence = PresenceManager()
        var events: [String] = []
        presence.onPeerPresenceChanged = { _, online in events.append(online ? "online" : "offline") }
        presence.onPeerStateChanged = { _, state in events.append(state.rawValue) }
        presence.handlePeerStatus(["online": true, "sessionId": "old", "state": "playing"], for: .toto)
        events.removeAll()

        presence.handlePeerStatus(["online": true, "sessionId": "new", "state": "bidding"], for: .toto)

        #expect(events == ["offline", "online", "bidding"])
        #expect(presence.getSessionId(for: .toto) == "new")
    }

    @Test func offlineOrLegacyPresenceDoesNotOverwriteActionStatus() {
        let presence = PresenceManager()
        var states: [PlayerState] = []
        presence.onPeerStateChanged = { _, state in states.append(state) }
        presence.handlePeerStatus(["online": false, "state": "playing"], for: .gg)
        presence.handlePeerStatus(["online": true], for: .gg)
        presence.handlePeerStatus(["online": true, "state": "unknown"], for: .gg)
        presence.handlePeerStatus(nil, for: .gg)
        #expect(states.isEmpty)
    }

    @Test func repeatedStartupWaitsForOneAuthenticationAttempt() async throws {
        let manager = makeManager()
        manager.preferences.playerId = "dd"
        var attempts = 0
        var authentication: CheckedContinuation<Void, Error>?
        let authenticate: () async throws -> Void = {
            attempts += 1
            try await withCheckedThrowingContinuation { authentication = $0 }
        }
        manager.startNetworkingIfNeeded(authenticate: authenticate)
        manager.startNetworkingIfNeeded(authenticate: authenticate)
        #expect(manager.networkingStartupTask != nil)
        #expect(!manager.networkingStarted)
        while authentication == nil { await Task.yield() }
        #expect(attempts == 1)
        #expect(!manager.networkingStarted)

        let startup = manager.networkingStartupTask
        startup?.cancel()
        authentication?.resume(throwing: CancellationError())
        await startup?.value
        #expect(manager.networkingStartupTask == nil)
        #expect(!manager.networkingStarted)
    }

    private func makeManager() -> GameManager {
        let manager = GameManager(connectionManager: .shared, signalingManager: .shared, preferences: Preferences())
        manager.gameState.getPlayer(by: .dd).tablePosition = .local
        return manager
    }
}
