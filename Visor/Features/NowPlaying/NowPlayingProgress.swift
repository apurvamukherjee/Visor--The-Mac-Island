import Foundation

/// Playback position, stored as an anchor rather than a live value — the
/// same idea `IslandTimer` uses for its countdown. The adapter re-emits
/// elapsed/timestamp on every position tick, which is exactly the constant
/// rewrite `NowPlayingInfo`'s doc comment says was cut from the store once
/// already (see the Power fix in `docs/RESEARCH.md`). Keeping the anchor in
/// its own `Equatable` type, written only when `shouldReplace` says a real
/// event happened, is what lets a scrub bar exist without reintroducing
/// that per-tick re-render.
struct NowPlayingProgress: Equatable, Sendable {
    let duration: TimeInterval
    let elapsedAtAnchor: TimeInterval
    let anchorDate: Date
    let isPlaying: Bool
    let rate: Double

    /// The live position, computed from the anchor rather than accumulated
    /// — `TimelineView` calls this with its own `context.date` the way
    /// `ExpandedTimerView` calls `IslandTimer.remaining(at:)`.
    func elapsed(at now: Date) -> TimeInterval {
        guard isPlaying else { return elapsedAtAnchor }
        let projected = elapsedAtAnchor + now.timeIntervalSince(anchorDate) * rate
        return min(max(0, projected), duration)
    }

    /// Past this much disagreement between where `current`'s anchor projects
    /// to and where `incoming` actually reports, the difference reads as a
    /// seek rather than ordinary clock drift or network jitter.
    private static let driftTolerance: TimeInterval = 1.5

    /// Whether the store should be written. True for the first anchor, a
    /// play/pause flip, a track of a different length, or a jump the
    /// projection above cannot explain — false for the adapter's routine
    /// re-emission of the same playback already in progress, which is most
    /// of them.
    static func shouldReplace(_ current: NowPlayingProgress?, with incoming: NowPlayingProgress) -> Bool {
        guard let current else { return true }
        guard current.isPlaying == incoming.isPlaying, current.duration == incoming.duration else { return true }
        let expected = current.elapsed(at: incoming.anchorDate)
        return abs(expected - incoming.elapsedAtAnchor) > driftTolerance
    }
}
