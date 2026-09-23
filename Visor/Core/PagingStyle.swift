import Foundation

/// How the expanded island moves between its screens.
///
/// A picker rather than a `NewFeature` switch, because the two candidate
/// booleans (`stack`, `stackTint`) give four states and one of them — tint
/// on, stack off — means nothing. The §2.1 guarantee survives the change of
/// shape: `.crossFade` is what an unwritten *or unrecognised* key resolves
/// to, so an unset default is today's behaviour exactly as `bool(forKey:)`'s
/// false is for the switches. Same construction as `NotchScreenChoice`.
enum PagingStyle: String, CaseIterable, Sendable {
    /// What Visor does today: one box, content swapped in place.
    case crossFade
    /// The deck — adjacent pages peek below the front card and the stack
    /// cycles.
    case cardStack

    var title: String {
        switch self {
        case .crossFade: "Cross-fade"
        case .cardStack: "Card stack"
        }
    }

    var detail: String {
        switch self {
        case .crossFade: "Pages swap in place inside one box."
        case .cardStack: "Adjacent pages peek below the front card, and the stack cycles."
        }
    }

    static func current(in defaults: UserDefaults = .standard) -> PagingStyle {
        PagingStyle(rawValue: defaults.string(forKey: Preferences.pagingStyleKey) ?? "") ?? .crossFade
    }
}
