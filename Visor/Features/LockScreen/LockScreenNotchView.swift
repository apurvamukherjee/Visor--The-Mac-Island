import SwiftUI

/// The notch mirror on the lock screen: the same silhouette the island draws,
/// wearing a padlock that latches as the screen locks and springs open as it
/// unlocks.
///
/// It reuses `NotchShape` and the `Motion` springs rather than drawing its
/// own — the whole point is that it is recognisably the same island, and one
/// shape morphing is the rule the rest of the app follows.
struct LockScreenNotchView: View {
    var store: NotchStore
    let closedSize: CGSize

    /// How much wider than the cutout the latched state runs, and how much
    /// taller. Small: this is a glyph in a notch, not a panel.
    private static let extraWidth: CGFloat = 76
    private static let extraHeight: CGFloat = 8

    private var isLatched: Bool {
        store.isLocked
    }

    private var size: CGSize {
        CGSize(
            width: closedSize.width + (isLatched ? Self.extraWidth : 0),
            height: closedSize.height + (isLatched ? Self.extraHeight : 0)
        )
    }

    var body: some View {
        NotchShape(
            topRadius: isLatched ? NotchRadii.compact.top : 0,
            bottomRadius: isLatched ? NotchRadii.compact.bottom : NotchRadii.closed.bottom,
            isCapsule: store.isCapsule
        )
        .fill(.black)
        .frame(width: size.width, height: size.height)
        .overlay {
            if isLatched {
                LockLatchGlyph(isLocked: store.isLocked)
                    .frame(width: size.width, height: size.height)
                    .transition(.island)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(Motion.resolved(isLatched ? Motion.open : Motion.close), value: isLatched)
    }
}

/// The padlock itself. A symbol transition, not a Lottie file: SF Symbols
/// already ship `lock`/`lock.open` as a matched pair with a built-in
/// `.replace` transition, and shipping an animation asset to draw a padlock
/// the system already draws would be a dependency for its own sake.
private struct LockLatchGlyph: View {
    let isLocked: Bool

    var body: some View {
        Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
            .padding(.top, 2)
    }
}
