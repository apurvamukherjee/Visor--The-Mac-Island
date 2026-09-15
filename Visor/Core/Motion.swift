import AppKit
import SwiftUI

enum Motion {
    /// closed/compact → expanded
    static let open = Animation.spring(duration: 0.45, bounce: 0.22)
    /// expanded → closed/compact
    static let close = Animation.spring(duration: 0.34, bounce: 0.0)
    /// closed ↔ compact (live activity appears/disappears)
    static let morph = Animation.snappy(duration: 0.32)
    /// content insertion
    static let contentIn = Animation.smooth(duration: 0.28).delay(0.08)
    /// content removal (always faster than the shape)
    static let contentOut = Animation.smooth(duration: 0.14)
    /// idle ↔ music expanded column redistribution — one coordinated layout
    /// change, not two sequential ones
    static let layout = Animation.spring(duration: 0.40, bounce: 0.18)
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
