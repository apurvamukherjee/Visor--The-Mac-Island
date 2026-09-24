import AppKit
import SwiftUI

enum Motion {
    /// Every spring below is derived from this. Read once at launch and on
    /// change, not per access: these are read from view bodies.
    private nonisolated(unsafe) static var cachedPreset = MotionPreset(
        rawValue: UserDefaults.standard.string(forKey: Preferences.motionPresetKey) ?? ""
    ) ?? .balanced

    static var preset: MotionPreset {
        get { cachedPreset }
        set {
            cachedPreset = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Preferences.motionPresetKey)
        }
    }

    // MARK: - Shape

    /// closed/compact → expanded. Arrival, and the longest travel the shape
    /// ever makes, so it takes the slowest spring and the only real bounce —
    /// the overshoot is what gives the island mass on the way in.
    static var open: Animation {
        .spring(duration: preset.expandResponse, bounce: MotionPreset.openBounce)
    }

    /// **Any move that ends smaller.** expanded → compact, expanded →
    /// closed, compact → closed, compact → a narrower compact.
    ///
    /// Named for the rule rather than for one transition, because that is
    /// precisely how it was got wrong: it was called `close`, so
    /// `exitCompact()` reached past it for `morph` — a spring *with* bounce
    /// — and compact → closed became the one shrink in the app that
    /// rebounded. Simulated 2026-09-24 on the pair that actually shipped
    /// (0.47 at bounce 0.175): 1.56pt of overshoot and a 0.617s settle,
    /// against 0.525s and none at all critically damped. A token named for
    /// its rule generalises to the next shrink somebody adds; one named for a
    /// transition invites the same bug. `SettleDampingTests` pins the rule by
    /// simulating the spring rather than by asserting the constant, so a
    /// future retune that breaks it fails there too.
    ///
    /// Monotonic on purpose. A spring on a dismissal bounces the shape back
    /// toward someone who has already looked away, and the tail of that
    /// bounce is visible in the shoulders after the body has settled.
    static var settle: Animation {
        .spring(duration: preset.settleResponse, bounce: MotionPreset.settleBounce)
    }

    /// Turning from one screen to the next. Nothing about the island's size
    /// changes — one box holds every page (RESEARCH §2.6b) — so this only
    /// carries content across, and is the shortest geometry spring there is.
    static var tab: Animation {
        .spring(duration: preset.tabResponse, bounce: MotionPreset.growBounce)
    }

    /// The deck's chins tucking back behind the front card, immediately
    /// before a collapse. Bounce 0 for the same reason `settle` has none:
    /// this is the first beat of a dismissal, and a chin that overshoots
    /// past the card's edge pops back into view after it has gone.
    /// `Dwell.stackRetract` is derived from the same number, so the collapse
    /// begins only once the tuck has actually landed.
    static var retract: Animation {
        .spring(duration: preset.retractResponse, bounce: MotionPreset.settleBounce)
    }

    /// **Growing only**: closed → compact, or a wing widening for a new
    /// activity. Its shrinking counterpart is `settle`, and the two are
    /// separate tokens rather than one because the direction is what decides
    /// whether bounce is wanted at all.
    static var morph: Animation {
        .spring(duration: preset.baseResponse, bounce: MotionPreset.growBounce)
    }

    // MARK: - Content

    /// Content arriving in the **expanded** card, delayed so the shape gets
    /// a clear head start. Frame-stepping the motion reference's slow-motion
    /// pass shows what the delay is buying: at 60% and again at 95% of the
    /// open the card is *absolutely empty* — not faded, not blurred, black —
    /// and content only materialises once the shape has essentially landed.
    /// The island does not reveal its content by growing past it; it
    /// arrives, and then the content appears inside it.
    ///
    /// Critically damped: content that overshoots its own opacity or scale
    /// reads as a wobble inside a shape that has already stopped.
    static var contentIn: Animation {
        .spring(duration: preset.contentResponse, bounce: MotionPreset.settleBounce)
            .delay(preset.expandedContentDelay)
    }

    /// The same arrival in a **compact wing**, which waits less because the
    /// wing has travelled a fraction of the distance the card does.
    static var wingIn: Animation {
        .spring(duration: preset.contentResponse, bounce: MotionPreset.settleBounce)
            .delay(preset.compactContentDelay)
    }

    /// Content removal, always the fastest thing in the system: outgoing
    /// content has to be gone before the island closes over it. The
    /// reference's close frames show the card already empty while the shape
    /// is still well above notch height.
    static var contentOut: Animation {
        .spring(duration: preset.contentOutResponse, bounce: MotionPreset.settleBounce)
    }

    /// idle ↔ music expanded column redistribution — one coordinated layout
    /// change, not two sequential ones
    static var layout: Animation {
        .spring(duration: preset.baseResponse, bounce: MotionPreset.growBounce)
    }

    /// The drop-target ring fading in and out.
    static var strokeVisibility: Animation {
        .spring(duration: preset.baseResponse, bounce: 0)
    }

    // MARK: - Feature-specific

    /// album art crossfade + scale-pop, used when Reduce Motion rules the
    /// flip out
    static let artSwap = Animation.spring(duration: 0.30, bounce: 0.20)
    /// first half of the album-art flip: accelerating into the edge-on frame
    static let artFlipOut = Animation.easeIn(duration: 0.16)
    /// second half: the new face swinging out with a little overshoot
    static let artFlipIn = Animation.spring(duration: 0.26, bounce: 0.28)
    /// `artFlipIn`'s duration, for Core Animation, which cannot take a
    /// SwiftUI `Animation` but must land on the same frame as one
    static let artFlipInDuration = 0.26
    /// a caught screenshot arriving in the wing
    static let catchIn = Animation.spring(duration: 0.34, bounce: 0.24)
    /// title/artist swap — the new track's text rises into place
    static let textSwap = Animation.spring(duration: 0.34, bounce: 0.18)
    /// Onboarding step glyph entrance — a light bounce as each step's icon
    /// appears, ported from the reference flow's own timing.
    static let onboardingIconIn = Animation.spring(duration: 0.4, bounce: 0.35)
    /// Onboarding button press feedback: a small scale/opacity dip.
    static let onboardingPress = Animation.easeOut(duration: 0.12)

    // MARK: - Squash and swipe feedback

    /// The "gulp" before a collapse: the island narrows and stretches taller
    /// for a beat, then releases into the close. It has to be an *additive
    /// offset* on its own spring rather than a second animation on the frame
    /// — measured, SwiftUI collapses a scoped `.animation(_:value:)` onto the
    /// ambient `withAnimation` transaction, so the two axes cannot be given
    /// different curves directly.
    static var squash: Animation {
        .spring(duration: preset.baseResponse, bounce: 0.30)
    }

    /// How long the squash is held before it releases and the shape closes.
    /// Long enough to read as a beat, short enough to stay under the ~150ms
    /// where a delay starts to read as lag.
    static let squashHold: Duration = .milliseconds(100)
    /// Fractions of the resting island the squash displaces, and how much of
    /// the height stretch bleeds into the corner radius so the shape bulges
    /// rather than merely scaling.
    static let squashWidthFraction: CGFloat = 0.2
    static let squashHeightFraction: CGFloat = 0.2
    static let squashRadiusFraction: CGFloat = 0.3

    /// Cached, not queried per read. These are read from view bodies and from
    /// `mouseMoved`, and each raw access is an IPC round-trip into the
    /// accessibility server — enough to show up in the render path. macOS
    /// posts a notification when any of them changes, which is the only time
    /// the cache can go stale.
    private nonisolated(unsafe) static var cachedFlags = AccessibilityFlags.current
    private nonisolated(unsafe) static var observer: NSObjectProtocol?

    struct AccessibilityFlags {
        var reduceMotion: Bool
        var reduceTransparency: Bool
        var increaseContrast: Bool

        static var current: AccessibilityFlags {
            let workspace = NSWorkspace.shared
            return AccessibilityFlags(
                reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
                reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
                increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast
            )
        }
    }

    static var flags: AccessibilityFlags {
        cachedFlags
    }

    static var reduceMotion: Bool {
        cachedFlags.reduceMotion
    }

    /// Called once at launch. Without it the cache is still correct for the
    /// life of the process — it just stops tracking a mid-session change.
    @MainActor
    static func startObservingAccessibility() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            cachedFlags = AccessibilityFlags.current
        }
    }

    /// Reduce Motion keeps the spring but takes the bounce and most of the
    /// duration out of it, rather than swapping in an ease. The reference's
    /// own figure: response 0.28, damping 1.0. It was `.easeOut(0.15)`,
    /// which is a different *curve* as well as a different length — so the
    /// island moved in a way it never moves otherwise, which is its own
    /// small surprise for someone who asked for less motion, not different
    /// motion.
    static func resolved(_ animation: Animation) -> Animation {
        reduceMotion ? .spring(duration: 0.28, bounce: MotionPreset.settleBounce) : animation
    }
}

/// The island's one content transition: content condenses into place out of
/// the shape, rather than sliding in from somewhere the shape is not.
///
/// Four properties move together, all of them **draw-time** — blur, opacity,
/// scale and offset. None of them is a layout property, so a card in the
/// middle of materialising costs no layout pass (RESEARCH §5.1b). The
/// anchor is the top because the island grows down out of the cutout, so
/// content should appear to come from up there too.
struct Materialize: ViewModifier {
    let progress: CGFloat

    /// Reduce Motion: opacity and nothing else. Blur and displacement are
    /// exactly the kinds of movement the setting exists to remove, and an
    /// accessibility setting is not somewhere to be clever.
    func body(content: Content) -> some View {
        if Motion.reduceMotion {
            content.opacity(1 - progress)
        } else {
            content
                .blur(radius: 6 * progress)
                .opacity(1 - progress)
                .scaleEffect(1 - 0.05 * progress, anchor: .top)
                // The reference's y −8 → 0. Content settles *downward* into
                // the card, following the shape that just grew down past it.
                .offset(y: -8 * progress)
        }
    }
}

extension AnyTransition {
    /// Expanded-card content, which waits `expandedContentDelay` for the
    /// shape.
    static var island: AnyTransition {
        materialize(in: Motion.contentIn)
    }

    /// Compact-wing content, which waits the shorter `compactContentDelay`.
    /// The wing travels a fraction of the card's distance, so it does not
    /// need the card's head start.
    static var islandWing: AnyTransition {
        materialize(in: Motion.wingIn)
    }

    private static func materialize(in insertion: Animation) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: Materialize(progress: 1),
                identity: Materialize(progress: 0)
            )
            .animation(insertion),
            removal: .modifier(
                active: Materialize(progress: 1),
                identity: Materialize(progress: 0)
            )
            .animation(Motion.contentOut)
        )
    }
}
