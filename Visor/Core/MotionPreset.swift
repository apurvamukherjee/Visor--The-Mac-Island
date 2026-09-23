/// How fast the whole island moves. One knob rather than a dozen: every
/// token in `Motion` is derived from the preset's base response, so the
/// relationships between them (open is quicker than close, content trails
/// the shape) hold at any speed.
///
/// The ladder and its derived offsets follow the model DynamicNotch uses,
/// which in turn follows Apple's `response`/`dampingFraction` vocabulary
/// from WWDC23. Expressed here in `duration`/`bounce`, which is the same
/// spring: `bounce == 1 - dampingFraction`.
enum MotionPreset: String, CaseIterable, Sendable {
    case snappy
    case fast
    case balanced
    case slow
    case relaxed

    var title: String {
        switch self {
        case .snappy: "Snappiest"
        case .fast: "Fast"
        case .balanced: "Balanced"
        case .slow: "Slow"
        case .relaxed: "Relaxed"
        }
    }

    /// The natural period every other duration is derived from.
    var baseResponse: Double {
        switch self {
        case .snappy: 0.41
        case .fast: 0.44
        case .balanced: 0.47
        case .slow: 0.50
        case .relaxed: 0.53
        }
    }

    /// How long content waits for the shape before it fades in.
    var hideShowDelay: Double {
        switch self {
        case .snappy: 0.28
        case .fast: 0.31
        case .balanced: 0.34
        case .slow: 0.37
        case .relaxed: 0.40
        }
    }

    /// Opening is arrival, and slightly quicker than the base period.
    var expandResponse: Double {
        baseResponse - 0.02
    }

    /// Closing is departure, and *quicker* than the base period. This ran
    /// at `baseResponse + 0.08` following DynamicNotch; on hardware that
    /// read as the island being slow to let go, and the sprung close left
    /// the shoulders still settling after the body had stopped, which is
    /// half of why they looked like separate pieces. Back to NotchKit's
    /// argument, and to Visor's original number.
    var closeResponse: Double {
        baseResponse - 0.08
    }

    /// `1 - dampingFraction`. 0.20 is the content-bearing default; the
    /// close spring runs at SwiftUI's own 0.825 damping, hence 0.175.
    static let standardBounce = 0.20
    static let closeBounce = 0.175
}
