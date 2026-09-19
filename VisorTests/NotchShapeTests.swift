import SwiftUI
import Testing
@testable import Visor

struct NotchShapeTests {
    /// Bezier approximation can overshoot the true curve by a fraction of a
    /// point, so bounds are checked with a small tolerance rather than
    /// strict containment.
    private static let curveApproximationTolerance: CGFloat = 0.01

    @Test
    func pathBoundingBoxStaysWithinRect() {
        let rect = CGRect(x: 0, y: 0, width: 200, height: 32)
        let shape = NotchShape(.closed)

        let bounds = shape.path(in: rect).boundingRect

        #expect(rect.insetBy(dx: -Self.curveApproximationTolerance, dy: -Self.curveApproximationTolerance)
            .contains(bounds))
    }

    @Test
    func animatableDataRoundTripsBothRadii() {
        var shape = NotchShape(topRadius: 0, bottomRadius: 12)
        shape.animatableData = AnimatablePair(11, 28)

        #expect(shape.topRadius == 11)
        #expect(shape.bottomRadius == 28)
    }

    @Test
    func radiiClampSoPathStaysWithinASmallRect() {
        let rect = CGRect(x: 0, y: 0, width: 40, height: 10)
        let shape = NotchShape(topRadius: 100, bottomRadius: 100)

        let bounds = shape.path(in: rect).boundingRect

        #expect(rect.insetBy(dx: -Self.curveApproximationTolerance, dy: -Self.curveApproximationTolerance)
            .contains(bounds))
    }

    /// Point-sampled corners, not just bounding-box extent: a corner curve
    /// that sweeps the wrong direction can stay within bounds while still
    /// looping back through the interior and punching a hole via winding
    /// cancellation (exactly what shipped in the first Phase 1 pass).
    /// The body's top edge is flush with the bezel across its whole width.
    /// Sampling the outermost pixel would test the shoulder instead, which
    /// tapers to zero thickness by design — see `shoulderFlaresOutwardFrom
    /// TheBodyEdge` for that half.
    @Test
    func topEdgeIsFlushWithNoCutoutAtTheCorners() {
        let rect = CGRect(x: 0, y: 0, width: 320, height: 120)
        let top = NotchRadii.expanded.top
        let path = NotchShape(topRadius: top, bottomRadius: NotchRadii.expanded.bottom).path(in: rect)

        #expect(path.contains(CGPoint(x: top + 1, y: 0.5)))
        #expect(path.contains(CGPoint(x: rect.maxX - top - 1, y: 0.5)))
        #expect(path.contains(CGPoint(x: rect.midX, y: 0.5)))
        // And the full rect is spanned, shoulders included.
        #expect(path.boundingRect.width == rect.width)
    }

    /// The closed state must have no shoulder at all: any material outside
    /// the physical cutout makes the closed island visible against the
    /// hardware notch, which is the Phase 1 regression guard.
    @Test
    func closedStateHasNoShoulder() {
        #expect(NotchRadii.closed.top == 0)

        let rect = CGRect(x: 0, y: 0, width: 185, height: 33)
        let shape = NotchShape(.closed)
        let path = shape.path(in: rect)

        // Straight sides all the way up: no flare, no inset.
        #expect(path.contains(CGPoint(x: 0.5, y: 0.5)))
        #expect(path.contains(CGPoint(x: 0.5, y: 16)))
        #expect(path.contains(CGPoint(x: rect.maxX - 0.5, y: 16)))
    }

    /// The shoulder adds material outward at the top rather than removing
    /// it: immediately below the top edge the shape is inset by the shoulder
    /// radius, while at the top edge itself it spans the full width.
    @Test
    func shoulderFlaresOutwardFromTheBodyEdge() {
        let rect = CGRect(x: 0, y: 0, width: 320, height: 120)
        let top = NotchRadii.expanded.top
        let path = NotchShape(topRadius: top, bottomRadius: NotchRadii.expanded.bottom).path(in: rect)

        // Material outside the body's side, hugging the top edge: the flare.
        #expect(path.contains(CGPoint(x: top * 0.75, y: 0.2)))
        #expect(path.contains(CGPoint(x: rect.maxX - top * 0.75, y: 0.2)))
        // The fillet tapers back to the body edge, so the same x is empty
        // once clear of the shoulder — it adds material, never removes it.
        #expect(!path.contains(CGPoint(x: top * 0.5, y: 3)))
        #expect(!path.contains(CGPoint(x: top * 0.5, y: top + 4)))
        #expect(path.contains(CGPoint(x: top + 1, y: top + 4)))
        // Mirrored on the trailing side.
        #expect(!path.contains(CGPoint(x: rect.maxX - top * 0.5, y: top + 4)))
        #expect(path.contains(CGPoint(x: rect.maxX - top - 1, y: top + 4)))
    }

    @Test
    func bottomCornersAreCleanConvexRoundsWithNoHole() {
        let rect = CGRect(x: 0, y: 0, width: 320, height: 120)
        let top = NotchRadii.expanded.top
        let bottom = NotchRadii.expanded.bottom
        let path = NotchShape(topRadius: top, bottomRadius: bottom).path(in: rect)

        // Sharp corners are clipped away.
        #expect(!path.contains(CGPoint(x: rect.maxX - 0.5, y: rect.maxY - 0.5)))
        #expect(!path.contains(CGPoint(x: 0.5, y: rect.maxY - 0.5)))

        // The rounding's own center is inside the shape — a corner curve that
        // sweeps the long way around instead of the short turn cancels this
        // point out via the fill rule (the regression this guards).
        #expect(path.contains(CGPoint(x: top + bottom, y: rect.maxY - bottom)))
        #expect(path.contains(CGPoint(x: rect.maxX - top - bottom, y: rect.maxY - bottom)))
    }

    @Test
    func compactRadiiStayWithinAShortWideRect() {
        let rect = CGRect(x: 0, y: 0, width: 360, height: 32)
        let shape = NotchShape(.compact)

        let bounds = shape.path(in: rect).boundingRect

        #expect(rect.insetBy(dx: -Self.curveApproximationTolerance, dy: -Self.curveApproximationTolerance)
            .contains(bounds))
    }
}
