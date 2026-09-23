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
    case ember
    case slate

    var title: String {
        switch self {
        case .charcoal: "Charcoal"
        case .midnight: "Midnight"
        case .ember: "Ember"
        case .slate: "Slate"
        }
    }

    /// The family's hue and saturation. Lightness comes from the depth, not
    /// from here, so one family covers every card in the stack.
    private var base: (hue: Double, saturation: Double) {
        switch self {
        case .charcoal: (0.00, 0.00)
        case .midnight: (0.62, 0.55)
        case .ember: (0.06, 0.60)
        case .slate: (0.55, 0.22)
        }
    }

    /// The fill for a card at `depth` behind the front one.
    ///
    /// Each depth is *lighter* than the one in front of it, which is what
    /// separates two adjacent chins from each other — receding by getting
    /// darker would run them both into the black island above.
    func fill(depth: Int) -> LinearGradient {
        let step = Double(max(depth, 1))
        let top = brightness(0.10 + 0.06 * step)
        let bottom = brightness(0.05 + 0.04 * step)
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    private func brightness(_ value: Double) -> Color {
        Color(hue: base.hue, saturation: base.saturation, brightness: min(value, 1))
    }

    static func current(in defaults: UserDefaults = .standard) -> ChinGradient {
        ChinGradient(rawValue: defaults.string(forKey: Preferences.chinGradientKey) ?? "") ?? .charcoal
    }
}
