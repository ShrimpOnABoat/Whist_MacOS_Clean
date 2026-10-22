import Foundation

/// The durable move log is also the recovery path when a peer connection loses messages.
protocol GameActionStore {
    @MainActor func commitGameAction(_ draft: GameAction, documentID: String) async throws -> GameAction
    @MainActor func loadGameActions(sequenceGreaterThanOrEqual start: Int, sequenceLessThanOrEqual end: Int?) async throws -> [GameAction]
    @MainActor func observeActionSequence(_ onChange: @escaping (Result<Int, Error>) -> Void) -> GameActionObservation
}

final class GameActionObservation {
    private var onCancel: (() -> Void)?

    init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    func cancel() {
        onCancel?()
        onCancel = nil
    }

    deinit { onCancel?() }
}
