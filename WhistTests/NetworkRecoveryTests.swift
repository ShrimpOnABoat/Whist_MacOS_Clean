import Foundation
import FirebaseFirestore
import Testing
@testable import Whist

@MainActor
struct NetworkRecoveryTests {
    @Test func lostCommitAcknowledgementRetriesTheSameMoveAndSequence() async throws {
        let store = TestActionStore()
        let manager = makeManager(store)
        store.failAfterFirstCommit = true
        let payload = try JSONEncoder().encode(PlayerId.gg)

        let action = await manager.commitActionWithSequence(type: .dealer, payload: payload, playerId: .dd)

        #expect(action?.sequence == 1)
        #expect(store.commitIDs.count == 2)
        #expect(Set(store.commitIDs).count == 1)
        #expect(store.actions.count == 1)
        #expect(store.nextSequence == 2)
        #expect(manager.localActionCommitsInFlight == 0)
    }

    @Test func failedCommitDoesNotConsumeASequenceOrChangeTheGame() async throws {
        let store = TestActionStore()
        let manager = makeManager(store)
        store.commitError = NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.permissionDenied.rawValue)
        let action = await manager.commitActionWithSequence(type: .dealer, payload: try JSONEncoder().encode(PlayerId.gg), playerId: .dd)

        #expect(action == nil)
        #expect(store.nextSequence == 1)
        #expect(store.actions.isEmpty)
        #expect(manager.lastAppliedSequence == 0)
        #expect(manager.gameState.dealer == nil)
        #expect(store.commitIDs.count == 1)
    }

    @Test func serverNotificationRecoversTheLastMoveEvenWithoutAnotherPeerMessage() async throws {
        let store = TestActionStore()
        store.actions = [try dealerAction(1, .gg)]
        let manager = makeManager(store)
        defer { manager.canCatchUp = false }
        manager.canCatchUp = true
        manager.networkingStarted = true

        store.onSequence?(.success(1))
        try await waitUntil { manager.lastAppliedSequence == 1 }

        #expect(manager.gameState.dealer == .gg)
        #expect(store.loadStarts == [1])
        #expect(!manager.isRestoring)
    }

    @Test func healthyP2PDeliveryAvoidsDownloadingTheSameMove() async throws {
        let store = TestActionStore()
        let manager = makeManager(store)
        defer { manager.canCatchUp = false }
        manager.canCatchUp = true
        manager.receiveServerActionSequence(1)
        manager.receiveOrderedAction(try dealerAction(1, .gg))

        try await Task.sleep(for: .milliseconds(600))

        #expect(store.loadStarts.isEmpty)
        #expect(manager.lastAppliedSequence == 1)
    }

    @Test func outOfOrderAndDuplicateMovesApplyOnceInSequence() async throws {
        let store = TestActionStore()
        let manager = makeManager(store)
        defer { manager.canCatchUp = false }
        manager.canCatchUp = true
        let first = try dealerAction(1, .dd)
        let second = try dealerAction(2, .gg)
        let third = try dealerAction(3, .toto)
        store.actions = [third, second, first, second]
        manager.receiveOrderedAction(third)
        #expect(manager.lastAppliedSequence == 0)

        await manager.catchUp(from: 1, to: nil)
        manager.receiveOrderedAction(second)

        #expect(manager.lastAppliedSequence == 3)
        #expect(manager.gameState.dealer == .toto)
        #expect(manager.buffered.isEmpty)
        #expect(!manager.isRestoring)
    }

    @Test func transientServerFailureRetriesWithoutNewNetworkEvents() async throws {
        let store = TestActionStore()
        store.failNextLoad = true
        store.actions = [try dealerAction(1, .gg)]
        let manager = makeManager(store)
        defer { manager.canCatchUp = false }
        manager.canCatchUp = true
        manager.receiveServerActionSequence(1)

        try await waitUntil { manager.lastAppliedSequence == 1 }

        #expect(store.loadStarts == [1, 1])
        #expect(manager.catchUpRetryCount == 0)
    }

    @Test func overlappingRecoveryRequestsShareOneFetchAndDoNotPauseGameplay() async throws {
        let store = TestActionStore()
        store.suspendLoads = true
        let manager = makeManager(store)
        defer { manager.canCatchUp = false }
        manager.canCatchUp = true
        let first = Task { await manager.catchUp(from: 1, to: nil) }
        try await waitUntil { store.loadContinuation != nil }
        #expect(!manager.isRestoring)

        await manager.catchUp(from: 1, to: nil)
        #expect(store.loadStarts == [1])
        store.resumeLoad()
        await first.value
        #expect(!manager.catchUpInProgress)
    }

    @Test func delayedRecoveryCannotApplyToAResetGame() async throws {
        let store = TestActionStore()
        store.suspendLoads = true
        store.actions = [try dealerAction(1, .gg)]
        let manager = makeManager(store)
        manager.canCatchUp = true
        let fetch = Task { await manager.catchUp(from: 1, to: nil) }
        try await waitUntil { store.loadContinuation != nil }

        manager.canCatchUp = false
        manager.gameState.dealer = .toto
        store.resumeLoad()
        await fetch.value

        #expect(manager.gameState.dealer == .toto)
        #expect(manager.lastAppliedSequence == 0)
        #expect(manager.catchUpWorkItem == nil)
    }

    @Test func actionsWaitingForAnimationDoNotCauseRepeatedDownloads() async throws {
        let store = TestActionStore()
        let manager = makeManager(store)
        defer { manager.canCatchUp = false }
        manager.canCatchUp = true
        manager.gameState.currentPhase = .grabTrick
        let action = GameAction(playerId: .dd, type: .playCard,
                                payload: try JSONEncoder().encode(Card(suit: .hearts, rank: .ace)),
                                timestamp: 1, sequence: 1, context: nil)
        manager.receiveOrderedAction(action)
        manager.receiveOrderedAction(try dealerAction(2, .gg))
        manager.receiveServerActionSequence(2)

        #expect(manager.lastAppliedSequence == 0)
        #expect(manager.pendingActions.count == 1)
        #expect(manager.nextMissingActionSequence == 3)
        #expect(!manager.needsActionCatchUp)
        try await Task.sleep(for: .milliseconds(600))
        #expect(store.loadStarts.isEmpty)
    }

    @Test func nextRoundsDeckWaitsForTheCurrentRoundToFinish() async throws {
        let store = TestActionStore()
        let manager = makeManager(store)
        defer { manager.canCatchUp = false }
        manager.canCatchUp = true
        manager.gameState.currentPhase = .scoring
        let deck = [Card(suit: .hearts, rank: .ace)]
        store.actions = [GameAction(playerId: .gg, type: .sendDeck,
                                    payload: try JSONEncoder().encode(deck),
                                    timestamp: 1, sequence: 1, context: nil)]

        await manager.catchUp(from: 1, to: nil)

        #expect(manager.lastAppliedSequence == 0)
        #expect(manager.pendingActions.count == 1)
        #expect(!manager.isDeckReceived)
        #expect(manager.gameState.newDeck.isEmpty)
        manager.gameState.currentPhase = .waitingForDeck
        #expect(manager.processPendingActionsForCurrentPhase(checkState: false))
        #expect(manager.lastAppliedSequence == 1)
        #expect(manager.isDeckReceived)
    }

    @Test func stalePlayDoesNotBlockRecoveryWhileWaitingForAnotherPhase() throws {
        let manager = makeManager(TestActionStore())
        manager.gameState.round = 5
        manager.gameState.currentPhase = .bidding
        let action = GameAction(playerId: .dd, type: .playCard, payload: Data(),
                                timestamp: 1, sequence: 1,
                                context: GameAction.Context(round: 4, trickIndex: 0, turnIndex: 0, phase: .playingTricks))
        manager.receiveOrderedAction(action)
        #expect(manager.lastAppliedSequence == 1)
        #expect(manager.pendingActions.isEmpty)
    }

    @Test func dealersOwnDeckStillAppliesWhileDealing() throws {
        let manager = makeManager(TestActionStore())
        manager.gameState.currentPhase = .dealingCards
        let action = GameAction(playerId: .dd, type: .sendDeck,
                                payload: try JSONEncoder().encode([Card(suit: .hearts, rank: .ace)]),
                                timestamp: 1, sequence: 1, context: nil)
        manager.receiveOrderedAction(action)
        #expect(manager.lastAppliedSequence == 1)
        #expect(manager.isDeckReceived)
    }

    @Test func recoveryNeverSkipsAGenuinelyMissingMove() async throws {
        let store = TestActionStore()
        store.actions = [try dealerAction(2, .gg)]
        let manager = makeManager(store)
        defer { manager.canCatchUp = false }
        manager.canCatchUp = true
        manager.latestServerActionSequence = 2

        await manager.catchUp(from: 1, to: nil)

        #expect(manager.lastAppliedSequence == 0)
        #expect(manager.nextMissingActionSequence == 1)
        #expect(manager.needsActionCatchUp)
        #expect(manager.catchUpWorkItem != nil)
    }

    @Test func recoveryWaitsUntilLocalCommitCallbacksCanBeRegistered() async throws {
        let store = TestActionStore()
        let manager = makeManager(store)
        defer { manager.canCatchUp = false }
        manager.canCatchUp = true
        manager.localActionCommitsInFlight = 1
        manager.receiveServerActionSequence(1)

        await manager.catchUp(from: 1, to: nil)

        #expect(store.loadStarts.isEmpty)
        #expect(manager.catchUpWorkItem != nil)
        manager.localActionCommitsInFlight = 0
    }

    @Test func endingRecoveryCancelsItsServerObservation() {
        let store = TestActionStore()
        let manager = makeManager(store)
        manager.canCatchUp = true
        manager.networkingStarted = true
        #expect(store.observationCount == 1)
        manager.updateActionSequenceObservation()
        #expect(store.observationCount == 1)

        manager.canCatchUp = false

        #expect(store.observationCancellations == 1)
        #expect(manager.actionSequenceObservation == nil)
    }

    @Test func reconnectContinuesAfterFiveFailuresWithoutDuplicateRetries() {
        let manager = makeManager(TestActionStore())
        let peer = manager.gameState.getPlayer(by: .gg)
        peer.firebasePresenceOnline = true
        peer.connectionPhase = .failed
        manager.p2pReconnectRetryCounts[.gg] = 5

        manager.scheduleReconnectAttempt(for: .gg, reason: "test outage", fallbackPhase: .failed)
        #expect(manager.p2pReconnectTasks[.gg] != nil)
        #expect(manager.p2pReconnectRetryCounts[.gg] == 6)
        manager.scheduleReconnectAttempt(for: .gg, reason: "duplicate failure", fallbackPhase: .failed)
        #expect(manager.p2pReconnectRetryCounts[.gg] == 6)

        manager.updatePlayerConnectionPhase(playerId: .gg, phase: .connected)

        #expect(manager.p2pReconnectTasks[.gg] == nil)
        #expect(manager.p2pReconnectRetryCounts[.gg] == 0)
    }

    private func makeManager(_ store: TestActionStore) -> GameManager {
        let manager = GameManager(connectionManager: .shared, signalingManager: .shared,
                                  preferences: Preferences(), actionStore: store)
        manager.gameState.getPlayer(by: .dd).tablePosition = .local
        manager.gameState.getPlayer(by: .gg).tablePosition = .left
        manager.gameState.getPlayer(by: .toto).tablePosition = .right
        manager.gameState.playOrder = [.dd, .gg, .toto]
        return manager
    }

    private func dealerAction(_ sequence: Int, _ dealer: PlayerId) throws -> GameAction {
        GameAction(playerId: .dd, type: .dealer, payload: try JSONEncoder().encode(dealer),
                   timestamp: Double(sequence), sequence: sequence, context: nil)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition())
    }
}

@MainActor
private final class TestActionStore: GameActionStore {
    var actions: [GameAction] = []
    var committedByID: [String: GameAction] = [:]
    var commitIDs: [String] = []
    var nextSequence = 1
    var failAfterFirstCommit = false
    var commitError: Error?
    var failNextLoad = false
    var suspendLoads = false
    var loadContinuation: CheckedContinuation<Void, Never>?
    var loadStarts: [Int] = []
    var onSequence: ((Result<Int, Error>) -> Void)?
    var observationCount = 0
    var observationCancellations = 0

    func commitGameAction(_ draft: GameAction, documentID: String) async throws -> GameAction {
        commitIDs.append(documentID)
        if let commitError { throw commitError }
        if let existing = committedByID[documentID] { return existing }
        let action = GameAction(playerId: draft.playerId, type: draft.type, payload: draft.payload,
                                timestamp: draft.timestamp, sequence: nextSequence, context: draft.context)
        committedByID[documentID] = action
        actions.append(action)
        nextSequence += 1
        if failAfterFirstCommit {
            failAfterFirstCommit = false
            throw NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.unavailable.rawValue)
        }
        return action
    }

    func loadGameActions(sequenceGreaterThanOrEqual start: Int, sequenceLessThanOrEqual end: Int?) async throws -> [GameAction] {
        loadStarts.append(start)
        if suspendLoads {
            await withCheckedContinuation { loadContinuation = $0 }
        }
        if failNextLoad {
            failNextLoad = false
            throw NSError(domain: FirestoreErrorDomain, code: FirestoreErrorCode.unavailable.rawValue)
        }
        return actions.filter { $0.sequence >= start && (end == nil || $0.sequence <= end!) }
    }

    func resumeLoad() {
        suspendLoads = false
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func observeActionSequence(_ onChange: @escaping (Result<Int, Error>) -> Void) -> GameActionObservation {
        observationCount += 1
        onSequence = onChange
        return GameActionObservation { [weak self] in
            self?.observationCancellations += 1
            self?.onSequence = nil
        }
    }
}
