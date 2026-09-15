import SwiftUI
import Testing
@testable import Notchy

struct NotchShapeTests {
    /// Bezier approximation of a circular arc can overshoot the true arc by
    /// a fraction of a point, so bounds are checked with a small tolerance
    /// rather than strict containment.
    private static let arcApproximationTolerance: CGFloat = 0.01

    @Test
    func pathBoundingBoxStaysWithinRect() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 32)
        let shape = NotchShape(bottomRadius: NotchShape.closedBottomRadius)

        let bounds = shape.path(in: rect).boundingRect

        #expect(rect.insetBy(dx: -Self.arcApproximationTolerance, dy: -Self.arcApproximationTolerance).contains(bounds))
    }

    @Test
    func animatableDataRoundTrips() {
        var shape = NotchShape(bottomRadius: 12)
        shape.animatableData = 28

        #expect(shape.bottomRadius == 28)
    }

    @Test
    func radiiClampSoPathStaysWithinASmallRect() {
        let rect = CGRect(x: 0, y: 0, width: 40, height: 10)
        let shape = NotchShape(bottomRadius: 100)

        let bounds = shape.path(in: rect).boundingRect

        #expect(rect.insetBy(dx: -Self.arcApproximationTolerance, dy: -Self.arcApproximationTolerance).contains(bounds))
    }

    /// Point-sampled corners, not just bounding-box extent: a corner arc
    /// that sweeps the wrong direction can stay within bounds while still
    /// looping back through the interior and punching a hole via winding
    /// cancellation (exactly what shipped in the first Phase 1 pass).
    @Test
    func topEdgeIsFlushWithNoCutoutAtTheCorners() {
        let rect = CGRect(x: 0, y: 0, width: 320, height: 120)
        let shape = NotchShape(bottomRadius: NotchShape.expandedBottomRadius)
        let path = shape.path(in: rect)

        #expect(path.contains(CGPoint(x: 0.5, y: 0.5)))
        #expect(path.contains(CGPoint(x: rect.maxX - 0.5, y: 0.5)))
        #expect(path.contains(CGPoint(x: rect.midX, y: 0.5)))
    }

    @Test
    func bottomCornersAreCleanConvexRoundsWithNoHole() {
        let rect = CGRect(x: 0, y: 0, width: 320, height: 120)
        let bottom = NotchShape.expandedBottomRadius
        let shape = NotchShape(bottomRadius: bottom)
        let path = shape.path(in: rect)

        let bottomRightCenter = CGPoint(x: rect.maxX - bottom, y: rect.maxY - bottom)
        let bottomLeftCenter = CGPoint(x: bottom, y: rect.maxY - bottom)

        // Sharp corners are clipped away.
        #expect(!path.contains(CGPoint(x: rect.maxX - 0.5, y: rect.maxY - 0.5)))
        #expect(!path.contains(CGPoint(x: 0.5, y: rect.maxY - 0.5)))

        // The arc's own center is inside the shape — a corner arc that
        // sweeps the long way around instead of the short 90° turn cancels
        // this point out via the fill rule (the regression this guards).
        #expect(path.contains(bottomRightCenter))
        #expect(path.contains(bottomLeftCenter))

        // Well inside vs. well outside the rounding radius, on the diagonal.
        #expect(path.contains(CGPoint(x: bottomRightCenter.x + 15, y: bottomRightCenter.y + 15)))
        #expect(!path.contains(CGPoint(x: bottomRightCenter.x + 25, y: bottomRightCenter.y + 25)))
    }

    @Test
    func compactRadiiStayWithinAShortWideRect() {
        let rect = CGRect(x: 0, y: 0, width: 360, height: 32)
        let shape = NotchShape(bottomRadius: NotchShape.compactBottomRadius)

        let bounds = shape.path(in: rect).boundingRect

        #expect(rect.insetBy(dx: -Self.arcApproximationTolerance, dy: -Self.arcApproximationTolerance).contains(bounds))
    }
}
