import AppKit
import Testing
@testable import Notchy

struct NotchGeometryTests {
    @Test
    func closedRectUsesAuxiliaryAreasAndSafeAreaInset() {
        let screen = FakeScreen(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 656, height: 32),
            auxiliaryTopRightArea: CGRect(x: 856, y: 950, width: 656, height: 32)
        )

        let rect = NotchGeometry.closedRect(for: screen)

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

        let rect = NotchGeometry.closedRect(for: screen)

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

        let closed = NotchGeometry.closedRect(for: screen)
        let expanded = NotchGeometry.expandedRect(for: screen)

        #expect(expanded.midX == closed.midX)
        #expect(expanded.maxY == closed.maxY)
        #expect(expanded.size == NotchGeometry.expandedSize)
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
        // mid-animation, and it must not exceed the island's height.
        #expect(canvas.width >= expanded.width)
        #expect(canvas.width >= NotchGeometry.compactRect(for: screen).width)
        #expect(canvas.height == expanded.height)
        #expect(expanded.height == NotchGeometry.expandedSize(hasNowPlaying: false).height)
        #expect(NotchGeometry.expandedSize(hasNowPlaying: true).height < expanded.height)
        #expect(canvas.maxY == expanded.maxY)
    }
}

private struct FakeScreen: ScreenGeometryProviding {
    var frame: CGRect
    var safeAreaInsets: NSEdgeInsets
    var auxiliaryTopLeftArea: CGRect?
    var auxiliaryTopRightArea: CGRect?
}
