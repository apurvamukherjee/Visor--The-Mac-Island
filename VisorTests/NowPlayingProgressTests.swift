import Foundation
import Testing
@testable import Visor

struct NowPlayingProgressTests {
    private let anchor = Date(timeIntervalSince1970: 1_000_000)

    private func progress(
        elapsed: TimeInterval,
        isPlaying: Bool = true,
        duration: TimeInterval = 200
    ) -> NowPlayingProgress {
        NowPlayingProgress(
            duration: duration,
            elapsedAtAnchor: elapsed,
            anchorDate: anchor,
            isPlaying: isPlaying,
            rate: 1
        )
    }

    @Test func elapsedProjectsForwardAtTheStoredRateWhilePlaying() {
        let value = progress(elapsed: 10)
        #expect(value.elapsed(at: anchor.addingTimeInterval(5)) == 15)
    }

    @Test func elapsedHoldsStillWhilePaused() {
        let value = progress(elapsed: 10, isPlaying: false)
        #expect(value.elapsed(at: anchor.addingTimeInterval(5)) == 10)
    }

    @Test func elapsedNeverExceedsDuration() {
        let value = progress(elapsed: 195, duration: 200)
        #expect(value.elapsed(at: anchor.addingTimeInterval(30)) == 200)
    }

    @Test func nilCurrentAlwaysReplaces() {
        #expect(NowPlayingProgress.shouldReplace(nil, with: progress(elapsed: 0)))
    }

    @Test func ordinaryReemissionOnTheExpectedTrackDoesNotReplace() {
        let current = progress(elapsed: 10)
        // The adapter's routine re-emission 2s later, exactly where the
        // anchor already projects it — this is the case the whole type
        // exists to filter out.
        let incoming = NowPlayingProgress(
            duration: 200, elapsedAtAnchor: 12, anchorDate: anchor.addingTimeInterval(2), isPlaying: true, rate: 1
        )
        #expect(!NowPlayingProgress.shouldReplace(current, with: incoming))
    }

    @Test func aSeekBeyondDriftToleranceReplaces() {
        let current = progress(elapsed: 10)
        let incoming = NowPlayingProgress(
            duration: 200, elapsedAtAnchor: 90, anchorDate: anchor.addingTimeInterval(2), isPlaying: true, rate: 1
        )
        #expect(NowPlayingProgress.shouldReplace(current, with: incoming))
    }

    @Test func aPlayPauseFlipReplacesEvenWithoutAPositionJump() {
        let current = progress(elapsed: 10)
        let incoming = progress(elapsed: 10, isPlaying: false)
        #expect(NowPlayingProgress.shouldReplace(current, with: incoming))
    }

    @Test func aDifferentTrackLengthReplaces() {
        let current = progress(elapsed: 10, duration: 200)
        let incoming = progress(elapsed: 10, duration: 180)
        #expect(NowPlayingProgress.shouldReplace(current, with: incoming))
    }
}
