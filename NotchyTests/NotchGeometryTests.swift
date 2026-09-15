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

        #expect(rect.width == 200)
        #expect(rect.height == 32)
        #expect(rect.minX == 656)
        #expect(rect.minY == 950)
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
}

private struct FakeScreen: ScreenGeometryProviding {
    var frame: CGRect
    var safeAreaInsets: NSEdgeInsets
    var auxiliaryTopLeftArea: CGRect?
    var auxiliaryTopRightArea: CGRect?
}
