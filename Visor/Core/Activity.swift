/// What can own the compact state. There is no priority ladder, just an
/// order: user-initiated beats system-initiated beats ambient. `.timer`/
/// `.hud` were modelled ahead of the phases that produce them — see
/// RESEARCH.md §2.6 — and can come back with the features themselves.
enum ActivityKind: Sendable {
    case nowPlaying
    case charging
    case screenshot
}

struct Activity: Equatable, Sendable {
    let kind: ActivityKind
}

/// Lifetime is owned by whoever activated it: `BatteryService` cancels the
/// charging peek on its own schedule. A second expiry clock here would never
/// fire a re-render anyway, since `@Observable` only notifies on mutation.
func resolveCurrentActivity(_ activities: [ActivityKind: Activity]) -> Activity? {
    activities[.screenshot] ?? activities[.charging] ?? activities[.nowPlaying]
}
