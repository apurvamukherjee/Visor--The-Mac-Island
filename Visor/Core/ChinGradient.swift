import SwiftUI

/// What the cards behind the front one are filled with.
///
/// Dark gradients rather than flat tints, and dark on purpose: a chin is a
/// *card*, not a highlight, so it has to read as the same material as the
/// island seen further away. The earlier flat white/clear/orange tints made
/// the agenda chin look like the island lightening and gave `.home` no chin
/// colour at all, which is the one page most often in front.
///
/// Presets rather than a colour well per page: three pages times a colour
/// each is three keys to store, three to restore and three ways to pick a
/// combination that reads as one blur. A family picked once, with each page
/// taking a different stop from it, cannot do that.
///
/// `.charcoal` is what an unwritten *or unrecognised* key resolves to — the
/// same construction as `PagingStyle` and `NotchScreenChoice`, so §2.1's
/// guarantee holds structurally rather than by memory.
enum ChinGradient: String, CaseIterable, Sendable {
    case charcoal
    case midnight
    case midnightPurple
    case burgundy
    case crimson
    case ember
    case forest
    case slate
    /// The one family that is not a family: every page takes its own hue
    /// rather than its own stop. See `hue(depth:page:)`.
    case perPage

    var title: String {
        switch self {
        case .charcoal: "Charcoal"
        case .midnight: "Midnight"
        case .midnightPurple: "Midnight Purple"
        case .burgundy: "Burgundy"
        case .crimson: "Crimson"
        case .ember: "Ember"
        case .forest: "Forest"
        case .slate: "Slate"
        case .perPage: "Per page (accent)"
        }
    }

    /// The family's hue and saturation. Lightness comes from the depth, not
    /// from here, so one family covers every card in the stack.
    private var base: (hue: Double, saturation: Double) {
        switch self {
        case .charcoal: (0.00, 0.00)
        case .midnight: (0.62, 0.55)
        case .midnightPurple: (0.75, 0.58)
        case .burgundy: (0.96, 0.62)
        case .crimson: (0.99, 0.72)
        case .ember: (0.06, 0.60)
        case .forest: (0.38, 0.45)
        case .slate: (0.55, 0.22)
        // Unused: `.perPage` takes its hue from the card, not the family.
        case .perPage: (0.00, 0.00)
        }
    }

    /// The fill for a card at `depth` behind the front one.
    ///
    /// Each depth is *lighter* than the one in front of it, which is what
    /// separates two adjacent chins from each other — receding by getting
    /// darker would run them both into the black island above.
    func fill(depth: Int, page: IslandPage? = nil) -> LinearGradient {
        let step = Double(max(depth, 1))
        let tone = tone(for: page)
        let top = colour(tone, brightness: 0.10 + 0.06 * step)
        let bottom = colour(tone, brightness: 0.05 + 0.04 * step)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    /// One hue per page, so a chin says *which* screen is behind the front
    /// card rather than only that one is. Kept as dark and as saturated as
    /// every other family — a chin that reads as a highlight is the failure
    /// the flat tints were removed for.
    static func accent(for page: IslandPage?) -> (hue: Double, saturation: Double) {
        switch page {
        case .home: (0.62, 0.55)
        case .agenda: (0.38, 0.45)
        case .usage: (0.06, 0.60)
        case nil: (0.00, 0.00)
        }
    }

    /// The hue and saturation this family draws `page` with. Split out of
    /// `fill` because it is the part that varies and the part worth pinning:
    /// `LinearGradient` is not `Equatable`, so a test cannot compare fills.
    func tone(for page: IslandPage?) -> (hue: Double, saturation: Double) {
        self == .perPage ? Self.accent(for: page) : base
    }

    private func colour(_ tone: (hue: Double, saturation: Double), brightness: Double) -> Color {
        Color(hue: tone.hue, saturation: tone.saturation, brightness: min(brightness, 1))
    }

    static func current(in defaults: UserDefaults = .standard) -> ChinGradient {
        ChinGradient(rawValue: defaults.string(forKey: Preferences.chinGradientKey) ?? "") ?? .charcoal
    }
}
