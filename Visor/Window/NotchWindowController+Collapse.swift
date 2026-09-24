import AppKit
import SwiftUI

/// The collapse sequence, split from the controller for length — the file
/// crossed swiftlint's 400-line limit when the chin retraction landed. It was
/// already a marked seam: nothing here touches hover, observers or screens.
@MainActor
extension NotchWindowController {
    /// Squash, hold a beat, then close. The impulse is additive and rides its
    /// own spring, so the two axes read as squash-and-stretch rather than a
    /// uniform scale — SwiftUI folds a scoped `.animation(_:value:)` into the
    /// ambient transaction, so giving the frame's axes different curves
    /// directly does not work (measured).
    func collapseFromExpanded() {
        // The welcome flow holds the island open until the user finishes it
        // or replays it from Settings — a mouse-out mid-explanation should
        // not yank the island shut under an unread sentence. The palette
        // holds it open for the same reason: it was opened by a keystroke,
        // so the pointer's whereabouts are not what should close it.
        guard !store.isOnboardingActive, !store.isPaletteOpen else { return }
        // The chins retract *before* the frame shrinks, and the order is
        // load-bearing rather than stylistic. The 2026-09-19 motion pass
        // found `setFrame` firing while geometry was still protruding and
        // clipping the still-moving corners — `.logicallyComplete` landing
        // 117ms before the spring did. Chins are that failure at a larger
        // scale: 18pt of card below the frame, cut off in a hard line. The
        // frame must never be smaller than what is drawn.
        if store.isCardStacked, store.state == .expanded, !store.isStackRetracting {
            retractChinsThenCollapse()
            return
        }
        // The retraction flag is deliberately *not* cleared here. It was,
        // and clearing it on the re-entered call sent the chins back out at
        // the exact moment the squash began — they slid out, then dissolved
        // as the frame shrank past them. They stay tucked for the whole
        // collapse and are released by `finishShrink`'s state change, which
        // has already taken the deck to `.closed`.
        //
        // The page is deliberately *not* reset here. Clearing it first
        // re-resolved the layout while the island was still open, so
        // collapsing from the agent screen morphed out to the player's larger
        // card and only then closed. It is reset on the way in instead — see
        // `expand()` — which leaves every screen collapsing from its own size.
        generation += 1
        let gen = generation
        let target: NotchState = store.currentActivity != nil ? .compact : .closed
        squashTask?.cancel()
        squashTask = nil

        guard !Motion.reduceMotion else {
            clearSquash()
            runCollapse(to: target, generation: gen)
            return
        }

        let resting = store.layout.expandedSize(closed: store.closedSize)
        withAnimation(Motion.squash) {
            store.squashWidth = -resting.width * Motion.squashWidthFraction
            store.squashHeight = resting.height * Motion.squashHeightFraction
        }
        squashTask = Task { [weak self] in
            try? await Task.sleep(for: Motion.squashHold)
            guard !Task.isCancelled, let self, gen == generation else { return }
            squashTask = nil
            withAnimation(Motion.squash) {
                store.squashWidth = 0
                store.squashHeight = 0
            }
            runCollapse(to: target, generation: gen)
        }
    }

    /// `.removed`, not `.logicallyComplete`. Measured on this exact spring:
    /// `logicallyComplete` fires at t=0.355s with the shape still 3.7pt wider
    /// and 2.6pt taller than its target, which it does not reach until
    /// t=0.472s. Resizing the panel at the earlier mark clipped the only part
    /// of the shape still sticking out — the bottom corners — so the island
    /// snapped to a hard-edged rectangle and then visibly re-rounded.
    func runCollapse(to target: NotchState, generation gen: Int) {
        withAnimation(
            Motion.resolved(Motion.settle),
            completionCriteria: .removed
        ) {
            store.state = target
        } completion: { [weak self] in
            guard let self, gen == generation else { return }
            finishShrink(to: target)
        }
    }

    /// Pull the chins back behind the front card, then collapse for real.
    /// Re-entered through `collapseFromExpanded`, which the retraction flag
    /// then lets straight through.
    func retractChinsThenCollapse() {
        withAnimation(Motion.resolved(Motion.retract)) {
            store.isStackRetracting = true
        }
        retractTask?.cancel()
        retractTask = Task { [weak self] in
            try? await Task.sleep(for: Dwell.stackRetract)
            guard !Task.isCancelled, let self else { return }
            retractTask = nil
            collapseFromExpanded()
        }
    }

    /// Cancels a retraction in flight and puts the chins back where they
    /// were. An expand arriving mid-retract must not be followed by the
    /// collapse it was racing.
    func cancelChinRetraction() {
        retractTask?.cancel()
        retractTask = nil
        store.isStackRetracting = false
    }

    func clearSquash() {
        squashTask?.cancel()
        squashTask = nil
        store.squashWidth = 0
        store.squashHeight = 0
    }
}
