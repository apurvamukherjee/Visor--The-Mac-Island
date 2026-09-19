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
                .expandedSize(closed: referenceNotch) == CGSize(width: 338, height: 212)
        )
        #expect(
            IslandLayout.nowPlaying(IslandContent(agendaRows: 1))
                .expandedSize(closed: referenceNotch) == CGSize(width: 395, height: 197)
        )
        #expect(IslandLayout.timer.expandedSize(closed: referenceNotch) == CGSize(width: 360, height: 109))
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

    @Test
    func musicNarrowsWhenThereIsNothingToPeekAt() {
        #expect(
            IslandLayout.nowPlaying(IslandContent(agendaRows: 0)).expandedExtraWidth
                < IslandLayout.nowPlaying(IslandContent(agendaRows: 1)).expandedExtraWidth
        )
    }

    /// The compact-only peeks never own the expanded island, so whatever
    /// is behind them is the idle one — the size has to agree with the
    /// view, which falls through to `ExpandedIdleView` for exactly these.
    @Test
    func compactOnlyPeeksAreSizedAsTheIdleIsland() {
        for kind in [ActivityKind.charging, .wave, .greeting] {
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
        for layout in IslandLayout.all {
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
    /// The relationships are the point of the ladder: opening is quicker
    /// than the base period, closing slower, at every speed.
    @Test
    func openIsAlwaysQuickerThanCloseAtEverySpeed() {
        for preset in MotionPreset.allCases {
            #expect(preset.expandResponse < preset.baseResponse)
            #expect(preset.closeResponse < preset.baseResponse)
            #expect(preset.expandResponse > 0)
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

    /// Content must still be mounted while the shape is closing over it.
    @Test
    func contentOutlivesTheClose() {
        for preset in MotionPreset.allCases {
            #expect(preset.unmountDelay > preset.closeResponse)
        }
    }

    @Test
    func swipeCompressionIsClamped() {
        #expect(Motion.SwipeFeedback.compression(for: 10) == Motion.SwipeFeedback.minimumWidth)
        #expect(Motion.SwipeFeedback.compression(for: 10000) == Motion.SwipeFeedback.maximumWidth)
        #expect(Motion.SwipeFeedback.compression(for: 200) == 200 * Motion.SwipeFeedback.widthFactor)
    }
}
