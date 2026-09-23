import SwiftUI

/// The deck half of `NotchRootView`, split out for length the way
/// `SystemCommands+Files.swift` was — the root view was already at
/// swiftlint's type-body limit before the stack added to it.
extension NotchRootView {
    /// The card, wrapped in its deck when the stack is on. With it off this
    /// is the card and nothing else — no extra view in the hierarchy, so the
    /// cross-fade path is what it has always been.
    @ViewBuilder
    var stackedCard: some View {
        if store.isCardStacked, store.state == .expanded {
            IslandStack(
                store: store,
                size: cardSize,
                radii: radii,
                isRevealed: isStackRevealed && !store.isStackRetracting,
                gradient: ChinGradient(rawValue: chinGradient) ?? .charcoal
            ) {
                islandCard
            }
            .animation(Motion.resolved(Motion.morph), value: isStackRevealed)
            .animation(Motion.resolved(Motion.morph), value: store.isStackRetracting)
            .animation(Motion.resolved(Motion.morph), value: store.islandPage)
            .task(id: store.state) { await revealChins() }
            .onChange(of: store.isStackRetracting) { _, retracting in
                // A retraction is the start of a collapse. Drop the reveal
                // flag with it, so the re-entered collapse — which clears
                // `isStackRetracting` on its way through — cannot snap the
                // chins back out under a shrinking frame.
                if retracting {
                    isStackRevealed = false
                }
            }
        } else {
            islandCard
        }
    }

    /// The chins slide out a beat after the island settles, so opening shows
    /// one clean card and the deck then offers itself. Cancelled by the
    /// `.task(id:)` the moment the state changes, so a close mid-wait leaves
    /// nothing running — the same shape as `hoverIntentTask`.
    func revealChins() async {
        guard store.state == .expanded else {
            isStackRevealed = false
            return
        }
        try? await Task.sleep(for: Preferences.stackRevealDelay)
        guard !Task.isCancelled else { return }
        isStackRevealed = true
    }
}
