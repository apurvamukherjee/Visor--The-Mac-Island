import CoreGraphics
import Testing
@testable import Visor

struct IslandLayoutTests {
    /// The cutout Visor was tuned against: 15" M4 MacBook Air, measured.
    private let referenceNotch = CGSize(width: 185, height: 33)

    /// Sizes are added up from blocks and spacing tokens rather than typed
    /// in, so pinning the totals here is what stops a one-token tweak from
    /// quietly resizing every feature.
    @Test
    func layoutsAddUpToTheseSizesOnReferenceHardware() {
        #expect(
            IslandLayout.idle(IslandContent(agendaRows: 3, hasTimerPresets: true))
                .expandedSize(closed: referenceNotch) == CGSize(width: 366, height: 220)
        )
        // 548x190, against the motion reference's own 548x188 (measured on
        // its 34pt cutout, where Visor's is 33). It was 421x193 — 2.3x the
        // notch, where the reference is very nearly 3x — and the extra width
        // is what lets the header band carry page tabs to the left of the
        // camera housing and the battery to its right without either of them
        // crowding the cutout. The 2pt of height over the reference is the
        // usage screen; see `Block.musicColumn`.
        #expect(
            IslandLayout.nowPlaying(IslandContent())
                .expandedSize(closed: referenceNotch) == CGSize(width: 548, height: 190)
        )
        #expect(IslandLayout.timer.expandedSize(closed: referenceNotch) == CGSize(width: 360, height: 117))
    }

    /// The point of resolving size from content: a quiet day gets a
    /// smaller island, not the same island with black in it.
    @Test
    func anEmptyAgendaShrinksTheIdleIslandOnBothAxes() {
        let full = IslandLayout.idle(IslandContent(agendaRows: 3, hasTimerPresets: true))
        let empty = IslandLayout.idle(IslandContent(agendaRows: 0, hasTimerPresets: true))

        #expect(empty.expandedExtraHeight < full.expandedExtraHeight)
        #expect(empty.expandedExtraWidth < full.expandedExtraWidth)
    }

    @Test
    func agendaRowsCostExactlyOneRowEach() {
        func height(_ rows: Int) -> CGFloat {
            IslandLayout.idle(IslandContent(agendaRows: rows, hasTimerPresets: true)).expandedExtraHeight
        }
        // The first row is free: one event chip is shorter than the date
        // block standing beside it, so the column does not set the height.
        #expect(height(1) == height(0))
        #expect(height(3) - height(2) == IslandLayout.Block.eventRow + IslandSpacing.row)
    }

    /// "+N more" is a real row. Unreserved, the shape clips it.
    @Test
    func theOverflowRowIsReserved() {
        let plain = IslandLayout.idle(IslandContent(agendaRows: 3, hasTimerPresets: true))
        let overflowing = IslandLayout.idle(
            IslandContent(agendaRows: 3, hasAgendaOverflow: true, hasTimerPresets: true)
        )

        #expect(
            overflowing.expandedExtraHeight - plain.expandedExtraHeight
                == IslandLayout.Block.agendaOverflow + IslandSpacing.row
        )
    }

    /// The date is a fixed box in the corner, not a column that grows and
    /// shrinks: whether there is an event or not, the island is the same
    /// size. It used to resize under the player as the day changed, which
    /// moved the transport row for a reason nothing on screen explained.
    @Test
    func theDateBoxNeverResizesTheMusicIsland() {
        let sizes = [0, 1, 3].map { IslandLayout.nowPlaying(IslandContent(agendaRows: $0)) }
        #expect(Set(sizes.map(\.expandedExtraWidth)).count == 1)
        #expect(Set(sizes.map(\.expandedExtraHeight)).count == 1)
    }

    /// The bug the width floor exists for: expanding must never make the
    /// island narrower than the wing it opened from.
    @Test
    func theExpandedPlayerIsNeverNarrowerThanItsOwnCompactWing() {
        let layout = IslandLayout.nowPlaying(IslandContent())
        #expect(
            layout.expandedSize(closed: referenceNotch).width
                > layout.compactSize(closed: referenceNotch).width
        )
    }

    /// Expanding must never make the island *narrower* than the compact
    /// wing it grows out of. The player had a floor for this; the idle
    /// island did not, so an empty agenda resolved to 275pt against a 344pt
    /// wing and opening it visibly shrank the island sideways.
    @Test
    func expandingIsNeverNarrowerThanTheCompactWing() {
        let contents = [
            IslandContent(),
            IslandContent(agendaRows: 0, hasTimerPresets: true),
            IslandContent(agendaRows: 1, hasTimerPresets: true),
            IslandContent(agendaRows: 3, hasAgendaOverflow: true, hasTimerPresets: true)
        ]
        for content in contents {
            for layout in [IslandLayout.idle(content), IslandLayout.nowPlaying(content)] {
                #expect(layout.expandedExtraWidth > layout.compactExtraWidth)
            }
        }
    }

    /// The compact-only peeks never own the expanded island, so whatever
    /// is behind them is the idle one — the size has to agree with the
    /// view, which falls through to `ExpandedIdleView` for exactly these.
    @Test
    func compactOnlyPeeksAreSizedAsTheIdleIsland() {
        for kind in [ActivityKind.charging, .wave, .greeting, .lock] {
            #expect(IslandLayout.resolved(for: kind, content: .empty) == IslandLayout.idle(.empty))
        }
        #expect(IslandLayout.resolved(for: nil, content: .empty) == IslandLayout.idle(.empty))
    }

    @Test
    func compactKeepsTheNotchHeightAndOnlyGrowsSideways() {
        for layout in IslandLayout.all {
            let compact = layout.compactSize(closed: referenceNotch)
            #expect(compact.height == referenceNotch.height)
            #expect(compact.width > referenceNotch.width)
        }
    }

    /// Every layout has to clear the camera housing, which hides the top
    /// `notchHeight` points of the island's centre. A layout shorter than
    /// that plus its content padding would draw underneath the hardware.
    @Test
    func everyExpandedLayoutClearsTheCameraHousing() {
        // `.lock` is compact-only — it never expands, so it declares no
        // expanded height to clear the housing with.
        for layout in IslandLayout.all where layout != IslandLayout.lock {
            #expect(layout.expandedSize(closed: referenceNotch).height > referenceNotch.height + 40)
        }
    }

    @Test
    func theCanvasCoversEveryLayout() {
        let canvas = IslandLayout.maxExpandedSize(closed: referenceNotch)
        for layout in IslandLayout.all {
            let size = layout.expandedSize(closed: referenceNotch)
            #expect(size.width <= canvas.width)
            #expect(size.height <= canvas.height)
            #expect(layout.compactSize(closed: referenceNotch).width <= canvas.width)
        }
    }

    /// Closed is the one state that must never flare: the shoulder would be
    /// material outside the physical cutout.
    @Test
    func noLayoutGivesTheClosedStateAShoulder() {
        #expect(NotchRadii.closed.top == 0)
        for layout in IslandLayout.all {
            #expect(layout.expandedRadii.top > 0)
            #expect(layout.compactRadii.top > 0)
        }
    }
}

struct MotionPresetTests {
    /// The ladder's ordering, which is the whole point of deriving every
    /// token from one base: the relationships have to hold at every speed.
    ///
    /// Opening is now the **slowest** geometry spring, not the quickest.
    /// This test asserted the opposite until 2026-09-24, and the old
    /// assertion was backwards about the thing that matters: the expanded
    /// island travels several times further than any other move the shape
    /// makes, so giving it the shortest period made it the most hurried
    /// animation in the app. The reference's table has it at 0.48 against a
    /// 0.42 base.
    @Test
    func everySpringSitsWhereItsTravelPutsIt() {
        for preset in MotionPreset.allCases {
            // Furthest to travel, longest period.
            #expect(preset.expandResponse > preset.baseResponse)
            // Leaving is brisker than arriving.
            #expect(preset.settleResponse < preset.baseResponse)
            // Turning a page moves no geometry at all, so it is quicker again.
            #expect(preset.tabResponse < preset.settleResponse)
            // Content trails the shape and clears faster than anything.
            #expect(preset.contentResponse < preset.tabResponse)
            #expect(preset.contentOutResponse < preset.contentResponse)
            // Nothing may derive its way to zero or negative at any speed.
            #expect(preset.contentOutResponse > 0)
            #expect(preset.retractResponse > 0)
        }
    }

    /// The expanded card waits longer for its shape than a wing does, at
    /// every speed — the card's shape has further to come.
    @Test
    func contentWaitsLongerForTheCardThanForAWing() {
        for preset in MotionPreset.allCases {
            #expect(preset.expandedContentDelay > preset.compactContentDelay)
            #expect(preset.compactContentDelay > 0)
        }
    }

    @Test
    func theLadderIsMonotonic() {
        let ordered: [MotionPreset] = [.snappy, .fast, .balanced, .slow, .relaxed]
        for (faster, slower) in zip(ordered, ordered.dropFirst()) {
            #expect(faster.baseResponse < slower.baseResponse)
            #expect(faster.hideShowDelay < slower.hideShowDelay)
        }
    }

    /// `.balanced` *is* the motion reference's table, not an approximation.
    @Test
    func balancedMatchesTheReferenceTable() {
        let balanced = MotionPreset.balanced
        #expect(abs(balanced.expandResponse - 0.48) < 0.001)
        #expect(abs(balanced.baseResponse - 0.42) < 0.001)
        #expect(abs(balanced.settleResponse - 0.38) < 0.001)
        #expect(abs(balanced.tabResponse - 0.34) < 0.001)
        #expect(abs(balanced.contentResponse - 0.30) < 0.001)
        #expect(abs(balanced.contentOutResponse - 0.14) < 0.001)
    }
}

/// The rule that has to hold whatever anyone tunes: **any move that ends
/// smaller is critically damped.**
///
/// Pinned by simulating the spring rather than by asserting a constant,
/// because the constant is not the requirement — "never goes past its
/// target on the way down" is. A future preset, or a future token, that
/// breaks the requirement fails here even if it never touches
/// `settleBounce`.
struct SettleDampingTests {
    /// SwiftUI's spring model: unit mass, `k = (2π/duration)²`,
    /// `c = 4πζ/duration`, with `ζ = 1 - bounce`.
    private func overshoot(from: Double, to: Double, duration: Double, bounce: Double) -> Double {
        let zeta = 1 - bounce
        let k = pow(2 * .pi / duration, 2)
        let c = 4 * .pi * zeta / duration
        var x = from, v = 0.0, worst = 0.0
        let step = 1.0 / 120.0 / 16.0
        for _ in 0 ..< (120 * 16 * 2) {
            v += (-k * (x - to) - c * v) * step
            x += v * step
            // Positive means it has gone past the target, whichever way it
            // was travelling.
            worst = max(worst, to < from ? to - x : x - to)
        }
        return worst
    }

    @Test
    func aShrinkNeverGoesPastItsTargetAtAnySpeed() {
        for preset in MotionPreset.allCases {
            let past = overshoot(
                from: 345, to: 185,
                duration: preset.settleResponse,
                bounce: MotionPreset.settleBounce
            )
            #expect(past < 0.01, "\(preset) overshoots a shrink by \(past)pt")
        }
    }

    /// The bug this whole rule came from: `exitCompact()` used `morph`,
    /// which carries bounce, so compact → closed rebounded. Left here as the
    /// counter-example, so the simulation is demonstrably capable of
    /// catching an overshoot rather than passing vacuously.
    ///
    /// Two different numbers have been measured here and they are worth
    /// keeping straight. The spring that actually shipped — the old ladder's
    /// 0.47 at bounce 0.175 — overshot this shrink by **1.56pt** and took
    /// 0.617s to settle. The retuned grow spring below (0.42 at bounce 0.14)
    /// overshoots by **0.75pt**. Smaller, and still the wrong shape for a
    /// dismissal: the rule is zero, not "not much".
    @Test
    func theGrowSpringWouldHaveOvershotThatSameShrink() {
        let past = overshoot(
            from: 345, to: 185,
            duration: MotionPreset.balanced.baseResponse,
            bounce: MotionPreset.growBounce
        )
        #expect(past > 0.5, "the grow spring should visibly overshoot, measured \(past)pt")
    }
}
