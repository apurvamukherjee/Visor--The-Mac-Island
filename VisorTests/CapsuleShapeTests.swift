import SwiftUI
import Testing
@testable import Visor

/// Capsule mode is the same `NotchShape` with a branch, not a second shape —
/// one silhouette morphs between every state, and two shapes could only
/// cross-fade.
struct CapsuleShapeTests {
    private let rect = CGRect(x: 0, y: 0, width: 200, height: 40)

    @Test
    func aCapsuleFillsItsRectRatherThanInsettingForShoulders() {
        let capsule = NotchShape(topRadius: 11, bottomRadius: 20, isCapsule: true)
        let bounds = capsule.path(in: rect).boundingRect
        #expect(abs(bounds.width - rect.width) < 0.01)
        #expect(abs(bounds.height - rect.height) < 0.01)
    }

    /// The notched shape insets its body by the shoulder radius; the capsule
    /// has no shoulder to make room for, so the two are genuinely different
    /// silhouettes rather than the same one renamed.
    @Test
    func capsuleAndNotchedShapesDiffer() {
        let notched = NotchShape(topRadius: 11, bottomRadius: 20, isCapsule: false)
        let capsule = NotchShape(topRadius: 11, bottomRadius: 20, isCapsule: true)
        #expect(notched.path(in: rect).description != capsule.path(in: rect).description)
    }

    /// An over-large radius must round to a pill, not fold the path inside
    /// out.
    @Test
    func anOversizedRadiusClampsToAPill() {
        let capsule = NotchShape(topRadius: 0, bottomRadius: 999, isCapsule: true)
        let bounds = capsule.path(in: rect).boundingRect
        #expect(rect.insetBy(dx: -0.01, dy: -0.01).contains(bounds))
    }

    @Test
    func capsuleModeIsNotAnimatableSoItCannotChangeMidMorph() {
        var shape = NotchShape(topRadius: 0, bottomRadius: 12, isCapsule: true)
        shape.animatableData = AnimatablePair(11, 28)
        #expect(shape.isCapsule)
    }
}
