import Foundation

enum ActivityKind: Int, CaseIterable, Comparable, Sendable {
    case nowPlaying = 10
    case timer = 20
    case charging = 30
    case hud = 40

    static func < (lhs: ActivityKind, rhs: ActivityKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Transient kinds always win while live, then revert — they never
    /// become the persistent compact-state owner. See RESEARCH.md §2.6.
    var isTransient: Bool {
        switch self {
        case .charging, .hud: true
        case .nowPlaying, .timer: false
        }
    }
}

struct Activity: Equatable, Sendable {
    let kind: ActivityKind
    var expiresAt: Date?

    var isLive: Bool {
        guard let expiresAt else { return true }
        return Date.now < expiresAt
    }
}

/// A live transient activity always wins, for as long as it's live;
/// otherwise the lowest-`rawValue` live activity wins.
func resolveCurrentActivity(_ activities: [ActivityKind: Activity]) -> Activity? {
    let live = activities.values.filter(\.isLive)
    if let transient = live.first(where: { $0.kind.isTransient }) {
        return transient
    }
    return live.min { $0.kind < $1.kind }
}
