import SwiftUI

/// One continuous shape for every notch state. The top edge is flush with
/// the screen's top edge — bottom corners round normally.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    static let closedTopRadius: CGFloat = 6
    static let closedBottomRadius: CGFloat = 12
    static let expandedTopRadius: CGFloat = 16
    static let expandedBottomRadius: CGFloat = 28
    static let compactTopRadius: CGFloat = 6
    static let compactBottomRadius: CGFloat = 14

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    /// `topRadius` is tracked and animated (RESEARCH.md §2.5 wants an
    /// outward-flaring shoulder eventually) but not yet drawn: any curve
    /// that removes material at the true top corner shows background
    /// through a gap exactly where the shape should meet the bezel flush.
    /// ponytail: flush top is the correct, safe default until the flare is
    /// reshaped to add material outward instead of carving the corner away.
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let bottom = min(bottomRadius, width / 2, height)

        var path = Path()
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: width, y: 0))
        path.addLine(to: CGPoint(x: width, y: height - bottom))
        path.addArc(
            center: CGPoint(x: width - bottom, y: height - bottom),
            radius: bottom,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        path.addLine(to: CGPoint(x: bottom, y: height))
        path.addArc(
            center: CGPoint(x: bottom, y: height - bottom),
            radius: bottom,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        path.closeSubpath()
        return path.offsetBy(dx: rect.minX, dy: rect.minY)
    }
}
