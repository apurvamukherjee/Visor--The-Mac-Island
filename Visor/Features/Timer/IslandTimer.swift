import Foundation

/// A countdown the island owns. macOS exposes no system timer to observe —
/// Clock.app's are private — so Visor keeps its own.
///
/// Stored as a deadline rather than a remaining count: nothing has to tick
/// for the value to stay correct, so a closed island costs nothing and the
/// figure is right the instant it reappears.
struct IslandTimer: Equatable, Sendable {
    let duration: TimeInterval
    var deadline: Date
    /// Non-nil only while paused, holding what was left at that moment.
    var pausedRemaining: TimeInterval?

    var isPaused: Bool {
        pausedRemaining != nil
    }

    func remaining(at now: Date) -> TimeInterval {
        if let pausedRemaining {
            return max(0, pausedRemaining)
        }
        return max(0, deadline.timeIntervalSince(now))
    }

    func isFinished(at now: Date) -> Bool {
        remaining(at: now) <= 0
    }

    /// Rounded up, so a timer started at 5m reads "05:00" rather than
    /// "04:59" on its first frame.
    static func format(_ remaining: TimeInterval) -> String {
        let total = Int(remaining.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    /// What the idle island offers. Four is enough to cover the common
    /// cases without turning the row into a picker.
    static let presets: [(label: String, duration: TimeInterval)] = [
        ("1m", 60), ("5m", 300), ("10m", 600), ("25m", 1500)
    ]
}
