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
    /// idle-expanded signature glow — repeats only while its view exists
    /// (expanded + no now-playing activity), so it never ticks off-screen.
    static let pulse = Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true)
    /// idle ↔ music expanded column redistribution — one coordinated layout
    /// change, not two sequential ones
    static let layout = Animation.spring(duration: 0.40, bounce: 0.18)
    /// album art crossfade + scale-pop on track change
    static let artSwap = Animation.spring(duration: 0.30, bounce: 0.20)
    /// title/artist crossfade — opacity only, text never transforms
    static let textSwap = Animation.easeInOut(duration: 0.15)
    /// chip bar entrance, staggered to arrive after the play-state settles
    static let chipBarIn = Animation.spring(duration: 0.40, bounce: 0.22).delay(0.12)
    /// chip bar exit — a reverse of the entrance, never a plain fade-out
    static let chipBarOut = Animation.spring(duration: 0.28, bounce: 0.0)

    static func resolved(_ animation: Animation) -> Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? .easeOut(duration: 0.15)
            : animation
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
