/// The two things that can own the compact state. There is no priority
/// ladder: charging is a brief peek that reverts to whatever was underneath,
/// so it simply wins while it exists. `.timer`/`.hud` were modelled ahead of
/// the phases that produce them — see RESEARCH.md §2.6 — and can come back
/// with the features themselves.
enum ActivityKind: Sendable {
    case nowPlaying
    case charging
}

struct Activity: Equatable, Sendable {
    let kind: ActivityKind
}

/// Lifetime is owned by whoever activated it: `BatteryService` cancels the
/// charging peek on its own schedule. A second expiry clock here would never
/// fire a re-render anyway, since `@Observable` only notifies on mutation.
func resolveCurrentActivity(_ activities: [ActivityKind: Activity]) -> Activity? {
    activities[.charging] ?? activities[.nowPlaying]
}
