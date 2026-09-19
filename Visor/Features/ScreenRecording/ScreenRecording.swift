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
        let total = Int(elapsed)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}
