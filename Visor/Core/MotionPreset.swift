/// How fast the whole island moves. One knob rather than a dozen: every
/// token in `Motion` is derived from the preset's base response, so the
/// relationships between them hold at any speed — each spring's period
/// follows how far the thing it moves has to travel (open is the longest,
/// a page turn the shortest), and content always trails the shape in and
/// clears out ahead of it.
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
    ///
    /// Re-tuned 2026-09-24 so `.balanced` *is* the motion reference's own
    /// table rather than an approximation of it. The reference specifies six
    /// springs in Apple's `response`/`dampingFraction` vocabulary; expressed
    /// in `duration`/`bounce` they all fall out of one base of 0.42:
    ///
    ///     open    0.48 / 0.78  ->  base + 0.06, bounce 0.22
    ///     grow    0.42 / 0.86  ->  base,        bounce 0.14
    ///     settle  0.38 / 1.00  ->  base - 0.04, bounce 0
    ///     tab     0.34 / 0.86  ->  base - 0.08, bounce 0.14
    ///     content 0.30 / 1.00  ->  base - 0.12, bounce 0
    ///     out     0.14 / 1.00  ->  base / 3,    bounce 0
    ///
    /// The ladder kept its 0.03 step, so every other preset still scales the
    /// same relationships around the new centre.
    var baseResponse: Double {
        switch self {
        case .snappy: 0.36
        case .fast: 0.39
        case .balanced: 0.42
        case .slow: 0.45
        case .relaxed: 0.48
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

    /// Opening is arrival. Longer than the base period, not shorter: the
    /// expanded island has the furthest to travel of any move the shape
    /// makes, and the reference gives it the slowest spring *and* the only
    /// real bounce, so the arrival has somewhere to land. It ran at
    /// `baseResponse - 0.02` before, which made opening quicker than
    /// growing a wing — the opposite of the distances involved.
    var expandResponse: Double {
        baseResponse + 0.06
    }

    /// Any move that ends smaller. Quicker than the base period, and — see
    /// `MotionPreset.settleBounce` — critically damped, which is the part
    /// that matters. Departure should be brisk and monotonic: nothing that
    /// is leaving should rebound toward someone who has already looked away.
    var settleResponse: Double {
        baseResponse - 0.04
    }

    /// Turning from one screen to the next. The shortest of the geometry
    /// springs because nothing about the island's *size* changes — one box
    /// holds every page — so this only carries content across.
    var tabResponse: Double {
        baseResponse - 0.08
    }

    /// Content arriving inside a shape that has already landed.
    var contentResponse: Double {
        baseResponse - 0.12
    }

    /// Content leaving. Always the fastest thing in the system: outgoing
    /// content has to be gone before the island closes over it, and the
    /// reference's slow-motion pass shows the card already empty while the
    /// shape is still well above notch height.
    var contentOutResponse: Double {
        baseResponse / 3
    }

    /// How long the deck's chins take to tuck back behind the front card
    /// before the island is allowed to close. Derived rather than flat, so
    /// the "Animation speed" setting moves it with everything else — at a
    /// flat 120ms against `Motion.retract`'s own period the collapse fired
    /// roughly a quarter of the way through the tuck, and the chins were
    /// still out and moving when the shape started shrinking under them.
    /// That is the "fades in the middle of the screen" report.
    var retractResponse: Double {
        baseResponse - 0.13
    }

    /// How long the shape leads its content on the way open, per the
    /// reference's two figures: 0.10 expanded, 0.08 compact. Two numbers
    /// rather than one because the expanded shape travels several times
    /// further than a wing does, so its content has longer to wait before
    /// there is a card to land in.
    ///
    /// Derived from the same ladder as everything else. The compact ratio is
    /// the 0.24 this file already used, so a wing's timing is exactly what it
    /// has always been; only the expanded delay is new.
    var expandedContentDelay: Double {
        hideShowDelay * 0.30
    }

    var compactContentDelay: Double {
        hideShowDelay * 0.24
    }

    /// `1 - dampingFraction`, one per spring in the reference's table.
    ///
    /// `settleBounce` is zero and that is the whole point of it: **any move
    /// that ends smaller must be critically damped.** A shrink with bounce
    /// undershoots its target and rebounds past it, which on the island reads
    /// as the shape pinching inside the cutout and then swelling back out
    /// under it. Simulated 2026-09-24: the bouncing token that actually
    /// shipped here (0.47 at bounce 0.175) overshot a compact → closed
    /// shrink by 1.56pt and took 0.617s to settle, against 0.525s and no
    /// overshoot at all critically damped. The retuned `growBounce` below
    /// still overshoots the same shrink by 0.75pt — smaller, and just as
    /// wrong for a dismissal. The rule is zero, not "not much".
    static let openBounce = 0.22
    static let growBounce = 0.14
    static let settleBounce = 0.0
}
