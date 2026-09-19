import CoreGraphics
import Testing
@testable import Visor

/// The direction lock is the whole reason the vertical gesture can coexist
/// with the horizontal one — without it a diagonal flick both skipped a
/// track and dismissed the island.
@MainActor
struct SwipeAxisTests {
    @Test
    func aClearlySidewaysSwipeLocksHorizontal() {
        #expect(NotchContentView.resolveAxis(horizontal: 20, vertical: 3) == .horizontal)
        #expect(NotchContentView.resolveAxis(horizontal: -20, vertical: 3) == .horizontal)
    }

    @Test
    func aClearlyVerticalSwipeLocksVertical() {
        #expect(NotchContentView.resolveAxis(horizontal: 2, vertical: 20) == .vertical)
        #expect(NotchContentView.resolveAxis(horizontal: 2, vertical: -20) == .vertical)
    }

    /// A true diagonal belongs to neither, and stays unlocked until one axis
    /// pulls ahead — which is what stops one flick doing two things.
    @Test
    func aDiagonalStaysUndetermined() {
        #expect(NotchContentView.resolveAxis(horizontal: 20, vertical: 20) == .undetermined)
        #expect(NotchContentView.resolveAxis(horizontal: 20, vertical: 18) == .undetermined)
    }

    /// The first pixel or two of any gesture is noise.
    @Test
    func tinyMovementsDoNotLockAnything() {
        #expect(NotchContentView.resolveAxis(horizontal: 1, vertical: 0) == .undetermined)
        #expect(NotchContentView.resolveAxis(horizontal: 0, vertical: 0) == .undetermined)
    }
}
