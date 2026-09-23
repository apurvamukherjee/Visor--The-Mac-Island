import AppKit
import SwiftUI

/// The vertical swipe axis: which of the island's three screens is showing.
///
/// Split from the controller for length, and it is a clean seam — nothing
/// here touches the frame, the springs or the panel. It decides a page; the
/// shape machinery in `NotchWindowController.swift` reacts to it like any
/// other layout change.
@MainActor
extension NotchWindowController {
    /// Swipe up: step back out of whatever the swipe down opened, or put the
    /// current activity away.
    ///
    /// It deliberately does **not** close the island. It used to, and that
    /// made the vertical axis mean two things at once — one swipe both
    /// changed what was on screen and shut the screen it was on, so paging
    /// between states was impossible and every gesture ended in the notch.
    /// The pointer leaving is what closes the island, as it always was; this
    /// only ever changes what is being shown.
    func handleSwipeDismiss() {
        guard NewFeatures.islandPaging.isEnabled() else {
            Haptics.shapeChange()
            store.dismissCurrentActivity()
            return
        }
        turn(to: turned(by: -1))
    }

    /// Swipe down: open the usage screen once it is asked for, otherwise
    /// bring back whatever was swiped away.
    ///
    /// The usage screen takes the gesture outright rather than sharing it,
    /// because a binding that depends on whether something happens to be
    /// dismissed is a binding nobody can predict. With the switch off this is
    /// exactly what it was.
    func handleSwipeRestore() {
        guard NewFeatures.islandPaging.isEnabled() else {
            store.restoreDismissedActivity()
            guard NewFeatures.swipeDownOpens.isEnabled() else { return }
            openIslandForSwipe()
            return
        }
        // Down is still the direction that opens, and still only when asked
        // to — paging changes which screen a swipe lands on, never whether a
        // closed island answers a gesture at all.
        guard store.state == .expanded else {
            guard NewFeatures.swipeDownOpens.isEnabled() else { return }
            openIslandForSwipe()
            return
        }
        turn(to: turned(by: 1))
    }

    /// Where a swipe of `delta` lands. The stack wraps; the cross-fade
    /// clamps. One place, so up and down cannot disagree about which.
    func turned(by delta: Int) -> IslandPage {
        store.isCardStacked
            ? store.islandPage.cycled(by: delta, in: store.availablePages)
            : store.islandPage.stepped(by: delta, in: store.availablePages)
    }

    /// Turn to a screen. Paging turns pages; it does not open the island.
    ///
    /// This used to open a closed island from either direction, which handed
    /// paging a behaviour that belongs to `swipeDownOpens` — turning paging
    /// on then made a swipe *up* open the island even with that switch off.
    /// Opening stays where it was: one direction, one switch. `.home` is
    /// still where every open lands, so nothing about where you arrive
    /// changed.
    func turn(to page: IslandPage) {
        guard store.state == .expanded else { return }
        // Already at an end. No haptic either: a buzz with nothing moving
        // reads as the gesture having failed rather than the stack having
        // run out.
        guard page != store.islandPage else { return }
        Haptics.shapeChange()
        withAnimation(Motion.resolved(Motion.morph)) {
            store.islandPage = page
        }
    }

    /// A swipe that lands on a closed island opens it; one that lands on an
    /// open island leaves it alone rather than restarting the spring.
    func openIslandForSwipe() {
        guard store.state != .expanded else { return }
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
        expand()
    }
}
