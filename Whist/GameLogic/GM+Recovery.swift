import Foundation

extension GameManager {
    /// Include actions already waiting for animations or the next game. They do
    /// not need downloading again just because they have not been applied yet.
    var nextMissingActionSequence: Int {
        let received = Set(buffered.keys).union(pendingActions.filter { $0.type.isDurableOrdered }.map(\.sequence))
        var next = lastAppliedSequence + 1
        while received.contains(next) { next += 1 }
        return next
    }

    var needsActionCatchUp: Bool {
        let newestKnown = max(latestServerActionSequence, buffered.keys.max() ?? lastAppliedSequence)
        return nextMissingActionSequence <= newestKnown
    }

    func updateActionSequenceObservation() {
        guard networkingStarted, canCatchUp else {
            actionSequenceObservation?.cancel()
            actionSequenceObservation = nil
            actionObservationRetry?.cancel()
            actionObservationRetry = nil
            catchUpWorkItem?.cancel()
            catchUpWorkItem = nil
            actionSyncGeneration = UUID()
            latestServerActionSequence = 0
            catchUpInProgress = false
            catchUpRequested = false
            catchUpRetryCount = 0
            return
        }
        guard actionSequenceObservation == nil else { return }
        actionObservationRetry?.cancel()
        actionObservationRetry = nil
        let generation = actionSyncGeneration
        actionSequenceObservation = actionStore.observeActionSequence { [weak self] result in
            guard let self, generation == self.actionSyncGeneration else { return }
            switch result {
            case .success(let sequence):
                self.receiveServerActionSequence(sequence)
            case .failure(let error):
                logger.log("Action sequence listener failed: \(error.localizedDescription). Retrying.")
                self.actionSequenceObservation?.cancel()
                self.actionSequenceObservation = nil
                let retry = DispatchWorkItem { [weak self] in
                    guard let self, generation == self.actionSyncGeneration else { return }
                    self.updateActionSequenceObservation()
                }
                self.actionObservationRetry = retry
                DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: retry)
            }
        }
    }

    func receiveServerActionSequence(_ sequence: Int) {
        latestServerActionSequence = max(latestServerActionSequence, sequence)
        if needsActionCatchUp {
            scheduleCatchUp(reason: "Server has actions through seq \(sequence)")
        }
    }

    func scheduleCatchUp(reason: String, force: Bool = false, delay: TimeInterval = 0.4) {
        guard canCatchUp else { return }
        if catchUpInProgress {
            catchUpRequested = true
            return
        }
        // Coalesce notifications without continually postponing recovery.
        guard catchUpWorkItem == nil else { return }
        let generation = actionSyncGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, generation == self.actionSyncGeneration else { return }
            self.catchUpWorkItem = nil
            guard force || self.needsActionCatchUp else { return }
            self.requestCatchUp(from: self.nextMissingActionSequence)
        }
        catchUpWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func requestCatchUp(from start: Int, to end: Int? = nil) {
        Task { await catchUp(from: start, to: end) }
    }

    func catchUp(from start: Int, to end: Int?) async {
        guard canCatchUp else { return }
        guard !isRestoring, localActionCommitsInFlight == 0 else {
            scheduleCatchUp(reason: "Waiting for local action or restoration", force: true)
            return
        }
        guard !catchUpInProgress else {
            catchUpRequested = true
            return
        }
        catchUpInProgress = true
        catchUpRequested = false
        let generation = actionSyncGeneration
        var retryNeeded = false
        defer {
            if generation == actionSyncGeneration {
                catchUpInProgress = false
                if retryNeeded || needsActionCatchUp || catchUpRequested {
                    let delay = min(0.4 * pow(2, Double(catchUpRetryCount)), 30)
                    scheduleCatchUp(reason: "Continue action recovery", force: retryNeeded || catchUpRequested, delay: delay)
                }
            }
        }

        do {
            let from = max(start, nextMissingActionSequence)
            if let end, from > end { return }
            let actions = try await actionStore.loadGameActions(sequenceGreaterThanOrEqual: from,
                                                                sequenceLessThanOrEqual: end)
            guard generation == actionSyncGeneration else { return }
            guard !isRestoring, localActionCommitsInFlight == 0 else {
                retryNeeded = true
                return
            }
            // Use normal ordered processing. Network reads must not switch the
            // running game into restoration mode or bypass animation completion.
            for action in actions.sorted(by: { $0.sequence < $1.sequence }) where action.type.isDurableOrdered {
                receiveOrderedAction(action)
            }
            catchUpRetryCount = needsActionCatchUp ? min(catchUpRetryCount + 1, 7) : 0
            logger.log("Recovered \(actions.count) actions starting at seq \(from).")
        } catch {
            guard generation == actionSyncGeneration else { return }
            catchUpRetryCount = min(catchUpRetryCount + 1, 7)
            retryNeeded = true
            logger.log("Action recovery failed: \(error.localizedDescription). Will retry automatically.")
        }
    }
}
