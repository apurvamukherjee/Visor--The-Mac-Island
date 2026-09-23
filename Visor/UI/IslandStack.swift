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
    /// is retracting before a collapse. The chins sit at depth 0 — exactly
    /// behind the front card — when it is false.
    var isRevealed: Bool
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

    /// One peeking card. Drawn at the front card's full size and pushed
    /// down, rather than drawn as a short lip: a lip would have to know the
    /// front card's radius to meet it cleanly, and this way the geometry is
    /// the same shape every time.
    private func chinCard(page: IslandPage, depth: Int) -> some View {
        let step = CGFloat(min(depth, IslandStackMetrics.maxDepth))
        var chinRadii = radii
        chinRadii.bottom = max(0, radii.bottom - step * IslandStackMetrics.chinRadiusDrop)
        // No shoulder on a chin: the flare exists to blend the island into
        // the menu bar, and a card 9pt further down has no bezel to meet.
        chinRadii.top = 0
        let shape = NotchShape(chinRadii, isCapsule: store.isCapsule)

        return shape
            .fill(.black)
            .overlay {
                if page.usesMaterialChin {
                    shape.fill(.ultraThinMaterial).opacity(0.5)
                } else {
                    shape.fill(page.tint.opacity(0.22))
                }
            }
            .frame(
                width: max(0, size.width - step * 2 * IslandStackMetrics.chinInset),
                height: size.height
            )
            .offset(y: isRevealed ? step * IslandStackMetrics.chinOffset : 0)
    }
}
