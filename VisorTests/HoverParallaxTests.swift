import CoreGraphics
import Testing
@testable import Visor

@MainActor
struct HoverParallaxTests {
    private let rect = CGRect(x: 0, y: 0, width: 400, height: 168)

    @Test func centreIsZero() {
        let point = NotchContentView.normalized(CGPoint(x: 200, y: 84), in: rect)
        #expect(point.x == 0)
        #expect(point.y == 0)
    }

    @Test func cornersReachTheExtremes() {
        let topLeft = NotchContentView.normalized(CGPoint(x: 0, y: 0), in: rect)
        #expect(topLeft.x == -1)
        #expect(topLeft.y == -1)

        let bottomRight = NotchContentView.normalized(CGPoint(x: 400, y: 168), in: rect)
        #expect(bottomRight.x == 1)
        #expect(bottomRight.y == 1)
    }

    /// The panel's canvas is wider than the island, so the cursor genuinely
    /// can sit outside the rect the tilt is measured against — it must clamp
    /// rather than tilt the card past its limit.
    @Test func outsideThePanelClamps() {
        let far = NotchContentView.normalized(CGPoint(x: 9000, y: -9000), in: rect)
        #expect(far.x == 1)
        #expect(far.y == -1)
    }

    @Test func emptyRectIsZeroNotInfinite() {
        let point = NotchContentView.normalized(CGPoint(x: 5, y: 5), in: .zero)
        #expect(point.x == 0)
        #expect(point.y == 0)
    }
}

/// The tilt is a ±12° effect across the whole card, so sub-step cursor moves
/// are invisible — but each one used to cost a full view-graph pass.
@MainActor
struct HoverQuantisationTests {
    @Test func firstMoveAlwaysCounts() {
        #expect(NotchContentView.isSignificantMove(from: nil, to: CGPoint(x: 0, y: 0)))
    }

    @Test func tinyMovesAreDropped() {
        let old = CGPoint(x: 0.500, y: 0.500)
        #expect(!NotchContentView.isSignificantMove(from: old, to: CGPoint(x: 0.505, y: 0.505)))
    }

    @Test func movesPastTheStepCount() {
        let old = CGPoint(x: 0.5, y: 0.5)
        #expect(NotchContentView.isSignificantMove(from: old, to: CGPoint(x: 0.53, y: 0.5)))
        #expect(NotchContentView.isSignificantMove(from: old, to: CGPoint(x: 0.5, y: 0.53)))
    }
}
