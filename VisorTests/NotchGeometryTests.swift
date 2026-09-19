import AppKit
import Testing
@testable import Visor

struct NotchGeometryTests {
    /// The untrimmed rect. The plain `closedRect(for:)` reads the user's own
    /// width/height trim out of `UserDefaults`, so calling it here would
    /// measure whatever the sliders were last left on — which is exactly
    /// what made these fail once the trim setting existed.
    private func closedRect(for screen: ScreenGeometryProviding) -> CGRect {
        NotchGeometry.closedRect(for: screen, widthOffset: 0, heightOffset: 0)
    }

    @Test
    func closedRectUsesAuxiliaryAreasAndSafeAreaInset() {
        let screen = FakeScreen(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 656, height: 32),
            auxiliaryTopRightArea: CGRect(x: 856, y: 950, width: 656, height: 32)
        )

        let rect = closedRect(for: screen)

        // Reported cutout is 200x32 at x 656; the hardware trim narrows and
        // lengthens it, keeping it centred on the same midpoint.
        #expect(rect.width == 200 - NotchGeometry.closedWidthInset)
        #expect(rect.height == 32 + NotchGeometry.closedHeightOffset)
        #expect(rect.midX == 756 + NotchGeometry.closedHorizontalOffset)
        #expect(rect.maxY == 982)
    }

    @Test
    func closedRectFallsBackWhenNoNotchIsReported() {
        let screen = FakeScreen(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            safeAreaInsets: NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )

        let rect = closedRect(for: screen)

        #expect(rect.size == NotchGeometry.fallbackClosedSize)
        #expect(rect.midX == screen.frame.midX)
        #expect(rect.maxY == screen.frame.maxY)
    }

    @Test
    func expandedRectSharesClosedRectHorizontalCenterAndTopEdge() {
        let screen = FakeScreen(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 656, height: 32),
            auxiliaryTopRightArea: CGRect(x: 856, y: 950, width: 656, height: 32)
        )

        // Trimmed, to match what `expandedRect` resolves internally.
        let closed = NotchGeometry.closedRect(for: screen)
        let expanded = NotchGeometry.expandedRect(for: screen)

        #expect(expanded.midX == closed.midX)
        #expect(expanded.maxY == closed.maxY)
        #expect(expanded.size == NotchGeometry.expandedSize(closed: closed.size))
    }

    @Test
    func compactRectSharesClosedRectTopEdgeAndCenterAndAddsWingWidth() {
        let screen = FakeScreen(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 656, height: 32),
            auxiliaryTopRightArea: CGRect(x: 856, y: 950, width: 656, height: 32)
        )

        let closed = NotchGeometry.closedRect(for: screen)
        let compact = NotchGeometry.compactRect(for: screen)

        #expect(compact.midX == closed.midX)
        #expect(compact.minY == closed.minY)
        #expect(compact.height == closed.height)
        #expect(compact.width == closed.width + NotchGeometry.compactExtraWidth)
    }

    @Test
    func expandedCanvasContainsBothExpandedAndCompact() {
        let screen = FakeScreen(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 656, height: 32),
            auxiliaryTopRightArea: CGRect(x: 856, y: 950, width: 656, height: 32)
        )

        let expanded = NotchGeometry.expandedRect(for: screen)
        let canvas = NotchGeometry.expandedCanvasRect(for: screen)

        // Canvas must contain both, so no state change ever grows the frame
        // mid-animation, plus headroom below for the collapse squash, which
        // briefly stretches the island past every resting layout. A shape
        // taller than its window gets clipped.
        #expect(canvas.width >= expanded.width)
        #expect(canvas.width >= NotchGeometry.compactRect(for: screen).width)
        // Compared with a tolerance, not exactly: the canvas is built by
        // unioning two rects and so goes through a subtract-then-re-add of
        // the screen's maxY, which a fractional notch trim makes lossy by a
        // few ULPs. The geometry is right; the last bit of the mantissa is
        // not worth asserting on.
        #expect(abs(canvas.height - (expanded.height + NotchGeometry.squashAllowance)) < 0.0001)
        #expect(canvas.minY < expanded.minY)
        // Trimmed, to match the rects above, which resolve it themselves.
        let closed = NotchGeometry.closedRect(for: screen).size
        #expect(expanded.height == IslandLayout.maxExpandedSize(closed: closed).height)
        // Every declared layout fits the canvas, so no feature can force a
        // window resize mid-hover.
        for layout in IslandLayout.all {
            #expect(layout.expandedSize(closed: closed).width <= canvas.width)
            #expect(layout.expandedSize(closed: closed).height <= NotchGeometry.expandedSize(closed: closed).height)
            #expect(layout.compactSize(closed: closed).width <= canvas.width)
        }
        #expect(canvas.maxY == expanded.maxY)
    }
}

private struct FakeScreen: ScreenGeometryProviding {
    var frame: CGRect
    var safeAreaInsets: NSEdgeInsets
    var auxiliaryTopLeftArea: CGRect?
    var auxiliaryTopRightArea: CGRect?
}
