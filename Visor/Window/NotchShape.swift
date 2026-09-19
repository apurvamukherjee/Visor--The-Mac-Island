import SwiftUI

/// One continuous shape for every notch state. Two curvatures, both chosen:
///
/// * The bottom corners are *continuous* (squircle) rather than circular
///   arcs — the corner Apple draws everywhere in iOS and macOS. Measured
///   against the arc this replaced: at r=28 the curve starts 43pt along the
///   bottom edge instead of 28pt, which is plainly visible at island size.
/// * The top corners flare *outward* into the menu bar — the shoulder
///   RESEARCH.md §2.5 asked for. It adds material instead of removing it, so
///   it is a concave fillet, not a corner radius. `topRadius` is 0 in the
///   closed state and only there: any material outside the physical cutout
///   would break closed-island invisibility.
/// On a screen with no physical cutout there is no hardware to hide the top
/// edge behind, so the same shape resolves symmetric corners instead of
/// shoulders and reads as a free-floating capsule — iPhone's Dynamic Island.
/// A branch here rather than a second `Shape` type: one silhouette morphs
/// between every state, and two shapes could only cross-fade.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// Not animatable, and deliberately so: it follows which screen the
    /// island is on, which never changes mid-animation.
    var isCapsule = false

    init(topRadius: CGFloat, bottomRadius: CGFloat, isCapsule: Bool = false) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
        self.isCapsule = isCapsule
    }

    init(_ radii: NotchRadii, isCapsule: Bool = false) {
        self.init(topRadius: radii.top, bottomRadius: radii.bottom, isCapsule: isCapsule)
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        if isCapsule {
            // Both ends equally round, capped at a true pill. The bottom
            // radius drives it: it is the one the layouts already tune, and
            // the shoulder has no meaning without a cutout to flare out of.
            let radius = min(max(bottomRadius, 0), rect.height / 2, rect.width / 2)
            return RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect)
        }
        let top = max(0, min(topRadius, rect.width / 4, rect.height))
        // The body is inset by the shoulder on both sides; the shoulders then
        // add that material back at the very top only, so the silhouette is
        // full width where it meets the bezel and narrower below.
        let body = rect.insetBy(dx: top, dy: 0)
        let bottom = max(0, min(bottomRadius, body.width / 2, body.height))

        var path = UnevenRoundedRectangle(
            bottomLeadingRadius: bottom,
            bottomTrailingRadius: bottom,
            style: .continuous
        ).path(in: body)

        // Closed: no shoulder, and no boolean op to pay for in the state
        // the island spends all its time in.
        guard top > 0 else { return path }
        // Unioned rather than appended. Appended, these stayed three separate
        // closed subpaths meeting along x = body.minX/maxX — and two
        // antialiased edges that merely *abut* composite to about 75%
        // coverage, not 100%, so a pale hairline ran down the join. That line
        // is what made the shoulders read as pieces stuck onto the island
        // instead of part of it, and it was worst mid-morph, when the seam
        // sits off the pixel grid. One region has no interior edge to seam.
        return path
            .union(shoulder(outerX: rect.minX, bodyX: body.minX, topY: rect.minY, radius: top))
            .union(shoulder(outerX: rect.maxX, bodyX: body.maxX, topY: rect.minY, radius: top))
    }

    /// The concave fillet blending one top corner outward into the menu bar:
    /// the material between the straight top edge and the body's side. Its
    /// own subpath, unioned into the body by `path(in:)` — see the note
    /// there for why appending it was not enough.
    private func shoulder(outerX: CGFloat, bodyX: CGFloat, topY: CGFloat, radius: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: outerX, y: topY))
        path.addQuadCurve(
            to: CGPoint(x: bodyX, y: topY + radius),
            control: CGPoint(x: bodyX, y: topY)
        )
        path.addLine(to: CGPoint(x: bodyX, y: topY))
        path.closeSubpath()
        return path
    }
}
