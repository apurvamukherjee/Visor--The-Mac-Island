import SwiftUI

/// The expanded island drawn as a deck: the front card exactly as it is
/// today, and one chin per other reachable page peeking below it.
///
/// **Why three `NotchShape`s and not one path.** CLAUDE.md's rule is that
/// one black shape morphs between states and two shapes are never
/// cross-faded. These never cross-fade — they translate between depths, and
/// every one of them is the same silhouette at a different offset, so there
/// is still one shape vocabulary. Growing `NotchShape.path(in:)` into
/// stacked lips was the alternative and was rejected: that file is already
/// flagged by swiftlint for size and complexity, the shape must still morph
/// to `.closed`, and a single path cannot animate its lips independently of
/// its body.
///
/// **Why depth and not a transition.** Each card reads its own depth from
/// the store and animates to it; the page change happens inside one
/// `withAnimation`, so the whole deck springs together. The outgoing front
/// card travels to the back and the chin below it rises into the front
/// position without any of that being choreographed — it is one animated
/// property, not three coordinated transitions.
struct IslandStack<Front: View>: View {
    var store: NotchStore
    var size: CGSize
    var radii: NotchRadii
    /// False until the reveal delay has passed, and again while the island
    /// is retracting before a collapse. The chins sit tucked behind the
    /// front card's lower edge when it is false.
    var isRevealed: Bool
    /// The family every chin is filled from, chosen in Settings.
    var gradient: ChinGradient
    @ViewBuilder var front: () -> Front

    /// Deepest first, so a nearer chin draws over a further one.
    private var chins: [(page: IslandPage, depth: Int)] {
        store.stackDepths
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { (page: $0.key, depth: $0.value) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ForEach(chins, id: \.page) { chin in
                chinCard(page: chin.page, depth: chin.depth)
            }
            front()
        }
    }

    /// One peeking card.
    ///
    /// Drawn only as tall as the part that shows, not at the front card's
    /// full height. A full-height chin existed to reveal 9pt of itself, so
    /// 95% of it sat hidden behind the front card and the deck rendered as
    /// one heavy slab — the reason the feature read as broken on the
    /// player's larger box. Bottom-aligned in the same frame as the front
    /// card, so its lower edge lands `chinOffset` below it per depth.
    private func chinCard(page _: IslandPage, depth: Int) -> some View {
        let step = min(depth, IslandStackMetrics.maxDepth)
        let peek = CGFloat(step) * IslandStackMetrics.chinOffset
        var chinRadii = radii
        chinRadii.bottom = max(
            0,
            radii.bottom - CGFloat(step) * IslandStackMetrics.chinRadiusDrop
        )
        // No shoulder on a chin: the flare exists to blend the island into
        // the menu bar, and a card below the front one has no bezel to meet.
        chinRadii.top = 0
        let shape = NotchShape(chinRadii, isCapsule: store.isCapsule)
        let inset = IslandStackMetrics.chinInset(depth: step, width: size.width)

        return shape
            .fill(gradient.fill(depth: step))
            .frame(
                width: max(0, size.width - 2 * inset),
                height: IslandStackMetrics.chinBodyHeight
            )
            // The chin hangs off the bottom of the front card rather than
            // sitting inside it, so the offset is measured from the card's
            // own lower edge.
            .offset(y: size.height - IslandStackMetrics.chinBodyHeight + (isRevealed ? peek : 0))
    }
}
