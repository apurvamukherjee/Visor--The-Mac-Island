import Foundation

/// A screen recording or share in progress. Only the start date is stored:
/// the elapsed figure is projected from it on screen by `TimelineView`, so
/// nothing ticks — the same reason `IslandTimer` stores a deadline.
struct ScreenRecording: Equatable, Sendable {
    let startedAt: Date

    func elapsed(at date: Date) -> TimeInterval {
        max(0, date.timeIntervalSince(startedAt))
    }

    /// mm:ss, and hh:mm:ss once a recording passes the hour.
    static func formatted(_ elapsed: TimeInterval) -> String {
        Duration.seconds(Int(elapsed)).clockText
    }
}
