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
        turn(to: store.islandPage.stepped(by: -1, in: store.availablePages))
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
        turn(to: store.islandPage.stepped(by: 1, in: store.availablePages))
    }

    /// Turn to a screen, or open the island if it is not up yet.
    ///
    /// A swipe onto a closed island only ever opens it — onto the player,
    /// like every other way of opening it. Landing straight on the screen the
    /// gesture was reaching for would mean the island opened somewhere
    /// different depending on which direction your fingers moved, and the
    /// player being where you always find it is worth more than saving the
    /// second swipe.
    func turn(to page: IslandPage) {
        guard store.state == .expanded else {
            openIslandForSwipe()
            return
        }
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
