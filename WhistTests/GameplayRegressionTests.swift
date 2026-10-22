import Combine
import Foundation
import Testing
@testable import Whist

@MainActor
struct GameplayRegressionTests {
    @Test(arguments: [PlayerState.choosingTrump, .bidding, .discarding, .playing])
    func recheckingDecisionPreservesHonkTimer(state: PlayerState) throws {
        let manager = makeManager()
        defer { manager.cancelSlowpokeTimer() }
        manager.setPlayerState(to: state)
        let timer = try #require(manager.slowpokeTimer)

        manager.setPlayerState(to: state)

        #expect(!timer.isCancelled)
        #expect(manager.slowpokeTimer != nil)
        manager.setPlayerState(to: .waiting)
        #expect(timer.isCancelled)
        #expect(manager.slowpokeTimer == nil)
    }

    @Test func honkTimerStillFiresAfterBiddingRecheck() async throws {
        let manager = makeManager()
        defer { manager.cancelSlowpokeTimer() }
        manager.setPlayerState(to: .bidding)
        let timer = try #require(manager.slowpokeTimer)
        timer.schedule(deadline: .now() + 0.02)
        manager.setPlayerState(to: .bidding)

        try await Task.sleep(for: .milliseconds(150))

        #expect(manager.amSlowPoke)
        manager.setPlayerState(to: .bidding)
        #expect(manager.amSlowPoke)
        manager.setPlayerState(to: .waiting)
        #expect(!manager.amSlowPoke)
    }

    @Test func restorationRestartsHonkTimerForAnUnfinishedDecision() {
        let manager = makeManager()
        defer { manager.cancelSlowpokeTimer() }
        manager.setPlayerState(to: .choosingTrump)
        manager.isRestoring = true
        #expect(manager.slowpokeTimer == nil)
        manager.setPlayerState(to: .discarding)
        #expect(manager.slowpokeTimer == nil)

        manager.isRestoring = false

        #expect(manager.slowpokeTimer != nil)
    }

    @Test func autoPlayTracksTheCurrentBidAsTricksAreWon() {
        let manager = makeManager()
        let player = manager.gameState.getPlayer(by: .dd)
        player.announcedTricks = [1, 1, 1, 2]
        player.madeTricks = [0, 0, 0, 1]
        #expect(manager.autoPilotShouldWinTricks)

        player.madeTricks[3] = 2
        #expect(!manager.autoPilotShouldWinTricks)
        player.madeTricks[3] = 3
        #expect(!manager.autoPilotShouldWinTricks)
        player.announcedTricks[3] = 0
        player.madeTricks[3] = 0
        #expect(!manager.autoPilotShouldWinTricks)
    }

    @Test func autoPlayDoesNotReuseThePreviousRoundsBid() {
        let manager = makeManager()
        manager.gameState.getPlayer(by: .dd).announcedTricks = [1, 1, 1]
        #expect(!manager.autoPilotShouldWinTricks)
    }

    @Test func autoPlayChoosesHighWhenBehindBidAndLowAfterReachingIt() {
        let manager = makeManager()
        let player = manager.gameState.getPlayer(by: .dd)
        player.hand = [card(.hearts, .seven), card(.hearts, .ace)]
        player.announcedTricks[3] = 2
        #expect(manager.autoPlayCardChoice()?.id == "hearts_ace")

        player.madeTricks[3] = 2
        #expect(manager.autoPlayCardChoice()?.id == "hearts_7")
    }

    @Test func autoPlayLeadsLowestNonTrumpWhenAvoidingTricks() {
        let manager = makeManager()
        manager.gameState.getPlayer(by: .dd).hand = [card(.spades, .seven), card(.clubs, .king), card(.hearts, .eight)]
        #expect(manager.autoPlayCardChoice()?.id == "hearts_8")
    }

    @Test func autoPlayLeadsHighestOffSuitRankWhenTryingToWin() {
        let manager = makeManager()
        let player = manager.gameState.getPlayer(by: .dd)
        player.announcedTricks[3] = 2
        player.hand = [card(.clubs, .seven), card(.hearts, .ace)]
        #expect(manager.autoPlayCardChoice()?.id == "hearts_ace")
    }

    @Test func autoPlayDiscardsHighestCardThatWillLose() {
        let manager = makeManager()
        manager.gameState.playOrder = [.gg, .dd, .toto]
        manager.gameState.table = [card(.hearts, .king)]
        manager.gameState.getPlayer(by: .dd).hand = [card(.hearts, .seven), card(.hearts, .queen), card(.hearts, .ace)]
        #expect(manager.autoPlayCardChoice()?.id == "hearts_queen")
    }

    @Test func autoPlayUsesSmallestWinnerWhenEveryLegalCardWins() {
        let manager = makeManager()
        manager.gameState.playOrder = [.gg, .dd, .toto]
        manager.gameState.table = [card(.hearts, .seven)]
        manager.gameState.getPlayer(by: .dd).hand = [card(.hearts, .ace), card(.hearts, .eight)]
        #expect(manager.autoPlayCardChoice()?.id == "hearts_8")
    }

    @Test func autoPlayFollowsSuitEvenWithStalePlayableFlags() {
        let manager = makeManager()
        manager.gameState.playOrder = [.gg, .dd, .toto]
        manager.gameState.table = [card(.hearts, .king)]
        let player = manager.gameState.getPlayer(by: .dd)
        player.announcedTricks[3] = 2
        let trumpAce = card(.spades, .ace)
        trumpAce.isPlayable = true
        player.hand = [trumpAce, card(.hearts, .seven)]
        #expect(manager.autoPlayCardChoice()?.id == "hearts_7")
    }

    @Test func autoPlayRecognizesTrumpAlreadyWinningTheTrick() {
        let manager = makeManager()
        manager.gameState.playOrder = [.gg, .toto, .dd]
        manager.gameState.table = [card(.hearts, .king), card(.spades, .seven)]
        manager.gameState.getPlayer(by: .dd).hand = [card(.hearts, .ace), card(.hearts, .eight)]
        #expect(manager.autoPlayCardChoice()?.id == "hearts_ace")
    }

    @Test func autoPlaySkipsPlaceholdersAndOtherPlayersTurns() {
        let manager = makeManager()
        manager.gameState.getPlayer(by: .dd).hand = [Card(suit: .hearts, rank: .seven, isPlaceholder: true)]
        #expect(manager.autoPlayCardChoice() == nil)
        manager.gameState.getPlayer(by: .dd).hand = [card(.hearts, .ace)]
        manager.gameState.playOrder = [.gg, .dd, .toto]
        #expect(manager.autoPlayCardChoice() == nil)
    }

    @Test func enablingAutoPlayDuringYourTurnStartsPlayAndCanBeCancelledDuringAnimation() async throws {
        let manager = makeManager()
        defer { manager.cancelSlowpokeTimer() }
        let player = manager.gameState.getPlayer(by: .dd)
        player.hand = [card(.hearts, .seven), card(.hearts, .ace)]
        player.state = .waiting
        manager.activeAnimations = 1

        manager.setAutoPilotEnabled(true)

        #expect(manager.autoPilot)
        #expect(player.state == .playing)
        #expect(player.hand.allSatisfy { $0.isPlayable })
        manager.setAutoPilotEnabled(false)
        manager.activeAnimations = 0
        try await Task.sleep(for: .milliseconds(300))
        #expect(!manager.autoPlayInProgress)
        #expect(manager.gameState.table.isEmpty)
    }

    @Test(arguments: [false, true])
    func discardingTheLastClubResortsTheHandAndCompletesOnce(restoring: Bool) {
        let manager = makeManager()
        manager.isRestoring = restoring
        let player = manager.gameState.getPlayer(by: .dd)
        player.place = 2
        let discards = [card(.clubs, .seven), card(.clubs, .eight)]
        player.hand = [card(.hearts, .seven)] + discards + [card(.diamonds, .seven), card(.spades, .seven)]
        var completionCount = 0
        var publishedHand: [String] = []
        let subscription = player.$hand.sink { publishedHand = $0.map(\.id) }
        defer { subscription.cancel() }

        manager.updateGameStateWithDiscardedCards(from: .dd, with: discards) {
            completionCount += 1
            #expect(player.hand.map(\.id) == ["hearts_7", "spades_7", "diamonds_7"])
            #expect(manager.gameState.deck.filter { !$0.isPlaceholder }.count == 2)
        }
        if !restoring {
            #expect(completionCount == 0)
            let moves = manager.movingCards
            #expect(moves.count == 2)
            for move in moves.reversed() {
                move.toState = CardState(position: .zero, rotation: 0, scale: 1, zIndex: 0)
                manager.finalizeMove(move)
            }
        }

        #expect(completionCount == 1)
        #expect(publishedHand == ["hearts_7", "spades_7", "diamonds_7"])
    }

    @Test(arguments: [false, true])
    func finalRoundGiftIsSortedBeforeCompletion(restoring: Bool) {
        let manager = makeManager()
        manager.isRestoring = restoring
        manager.gameState.round = 12
        let local = manager.gameState.getPlayer(by: .dd)
        let giver = manager.gameState.getPlayer(by: .gg)
        local.place = 3
        local.monthlyLosses = 1
        giver.place = 2
        let gift = card(.clubs, .seven)
        giver.hand = [gift]
        local.hand = [card(.hearts, .seven), card(.spades, .seven), card(.diamonds, .seven)]
        var completionCount = 0

        manager.updateGameStateWithDiscardedCards(from: .gg, with: [gift]) {
            completionCount += 1
            #expect(local.hand.map(\.id) == ["hearts_7", "clubs_7", "diamonds_7", "spades_7"])
            #expect(giver.hand.isEmpty)
        }
        if !restoring {
            for move in manager.movingCards {
                move.toState = CardState(position: .zero, rotation: 0, scale: 1, zIndex: 0)
                manager.finalizeMove(move)
            }
        }
        #expect(completionCount == 1)
        #expect(!gift.isFaceDown)
    }

    private func card(_ suit: Suit, _ rank: Rank) -> Card {
        Card(suit: suit, rank: rank)
    }

    private func makeManager() -> GameManager {
        let manager = GameManager(connectionManager: .shared, signalingManager: .shared, preferences: Preferences())
        manager.gameState.round = 4
        manager.gameState.currentPhase = .playingTricks
        manager.gameState.trumpSuit = .spades
        manager.gameState.playOrder = [.dd, .gg, .toto]
        for (index, id) in manager.gameState.playOrder.enumerated() {
            let player = manager.gameState.getPlayer(by: id)
            player.tablePosition = [TablePosition.local, .left, .right][index]
            player.place = index + 1
            player.announcedTricks = [0, 0, 0, 0]
            player.madeTricks = [0, 0, 0, 0]
        }
        return manager
    }
}
