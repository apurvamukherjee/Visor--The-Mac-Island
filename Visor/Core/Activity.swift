/// What can own the island. There is no priority ladder, just an order:
/// user-initiated beats system-initiated beats ambient. `.wave` (a
/// deliberate double-click) is user-initiated like `.screenshot`;
/// `.greeting` is the most passive of all — it only ever activates when
/// nothing else is, so its low rank is really just documentation.
enum ActivityKind: Sendable, CaseIterable {
    case screenshot
    case wave
    case volume
    case network
    case batteryAlert
    case charging
    case deviceBattery
    case nowPlaying
    case timer
    case greeting
}

struct Activity: Equatable, Sendable {
    let kind: ActivityKind
}

/// Who gets the compact wings. Lifetime is owned by whoever activated it:
/// `BatteryService` cancels the charging peek on its own schedule. A second
/// expiry clock here would never fire a re-render anyway, since
/// `@Observable` only notifies on mutation.
private let compactPriority: [ActivityKind] = [
    .screenshot, .wave, .volume, .network, .batteryAlert, .charging, .deviceBattery,
    .nowPlaying, .timer, .greeting
]

/// Who gets the *expanded* island, which is not the same question: a
/// charging peek outranks music in the wings but must never replace the
/// music card when the user hovers. A long-running timer sits below music
/// for the opposite reason — it would otherwise hide the card for minutes.
private let expandedPriority: [ActivityKind] = [
    .screenshot, .volume, .network, .batteryAlert, .nowPlaying, .timer
]

func resolveCurrentActivity(_ activities: [ActivityKind: Activity]) -> Activity? {
    compactPriority.lazy.compactMap { activities[$0] }.first
}

/// Resolved once and read by both the layout and the view that fills it —
/// two switches over the same question drifted apart the moment a feature
/// started declaring its own size. Nil means the idle agenda.
func resolveExpandedKind(_ activities: [ActivityKind: Activity]) -> ActivityKind? {
    expandedPriority.first { activities[$0] != nil }
}
