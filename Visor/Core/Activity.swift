/// What can own the island. There is no priority ladder, just an order:
/// user-initiated beats system-initiated beats ambient. `.wave` (a
/// deliberate double-click) is user-initiated like `.screenshot`;
/// `.greeting` is the most passive of all — it only ever activates when
/// nothing else is, so its low rank is really just documentation.
enum ActivityKind: Sendable, CaseIterable, Equatable {
    /// The screen locking or unlocking. Outranks everything in the wings:
    /// while the padlock is showing, nothing else about the machine matters.
    case lock
    case screenshot
    case airDrop
    case wave
    case volume
    case network
    case batteryAlert
    case bluetooth
    case focus
    case charging
    case deviceBattery
    case screenRecording
    case download
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
    .lock, .screenshot, .airDrop, .wave, .volume, .network, .batteryAlert, .bluetooth, .focus,
    .charging, .deviceBattery, .screenRecording, .download, .nowPlaying, .timer, .greeting
]

/// Who gets the *expanded* island, which is not the same question: a
/// charging peek outranks music in the wings but must never replace the
/// music card when the user hovers. A long-running timer sits below music
/// for the opposite reason — it would otherwise hide the card for minutes.
/// `.screenRecording` sits below music for the same reason `.timer` does:
/// a recording runs for minutes, and hiding the music card for all of it
/// would be worse than showing the recording only in the wings.
private let expandedPriority: [ActivityKind] = [
    .screenshot, .airDrop, .volume, .network, .batteryAlert, .bluetooth, .download,
    .nowPlaying, .timer, .screenRecording
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
