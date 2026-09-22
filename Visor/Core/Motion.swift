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

    /// closed/compact → expanded. Arrival, so a touch quicker than the base
    /// period and with enough bounce to read as mass.
    static var open: Animation {
        .spring(duration: preset.expandResponse, bounce: MotionPreset.standardBounce)
    }

    /// expanded → closed/compact. Monotonic, and quicker than the open.
    /// The slower sprung close DynamicNotch uses shipped first and was
    /// wrong on hardware: a spring on a dismissal bounces the shape back
    /// toward someone who has already looked away, and the tail of that
    /// bounce is visible in the shoulders after the body has settled.
    static var close: Animation {
        .spring(duration: preset.closeResponse, bounce: 0)
    }

    /// closed ↔ compact (live activity appears/disappears)
    static var morph: Animation {
        .spring(duration: preset.baseResponse, bounce: MotionPreset.closeBounce)
    }

    // MARK: - Content

    /// Content insertion, delayed so the shape gets a head start. Without
    /// it, text fades up while the island is still notch-sized.
    static var contentIn: Animation {
        .spring(duration: preset.baseResponse, bounce: MotionPreset.standardBounce)
            .delay(contentRevealDelay)
    }

    /// Content removal, always faster than the shape: outgoing content has
    /// to clear before the island closes over it.
    static var contentOut: Animation {
        .smooth(duration: preset.baseResponse * 0.3)
    }

    /// How long the shape leads the content in.
    static var contentRevealDelay: Double {
        preset.hideShowDelay * 0.24
    }

    /// How long an outgoing layout stays mounted. Strictly longer than the
    /// close, or it tears down mid-morph.
    static var unmountDelay: Double {
        preset.unmountDelay
    }

    /// idle ↔ music expanded column redistribution — one coordinated layout
    /// change, not two sequential ones
    static var layout: Animation {
        .spring(duration: preset.baseResponse, bounce: MotionPreset.standardBounce)
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

    /// How far a swipe-in-progress squeezes the island. The compression is
    /// clamped so the gesture feels the same on a wing as on a full expanded
    /// card.
    ///
    /// There is deliberately no blur or fade here any more: the squeeze is
    /// the whole feedback. Blurring the content as well read as the island
    /// losing focus rather than being pushed.
    enum SwipeFeedback {
        static let widthFactor: CGFloat = 0.18
        static let minimumWidth: CGFloat = 28
        static let maximumWidth: CGFloat = 44

        /// Points of squeeze for a given island width at full progress.
        static func compression(for width: CGFloat) -> CGFloat {
            min(max(width * widthFactor, minimumWidth), maximumWidth)
        }
    }

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

    static func resolved(_ animation: Animation) -> Animation {
        reduceMotion ? .easeOut(duration: 0.15) : animation
    }
}

struct Materialize: ViewModifier {
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .blur(radius: 6 * progress)
            .opacity(1 - progress)
            .scaleEffect(1 - 0.06 * progress, anchor: .top)
    }
}

extension AnyTransition {
    static var island: AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: Materialize(progress: 1),
                identity: Materialize(progress: 0)
            )
            .animation(Motion.contentIn),
            removal: .modifier(
                active: Materialize(progress: 1),
                identity: Materialize(progress: 0)
            )
            .animation(Motion.contentOut)
        )
    }
}
