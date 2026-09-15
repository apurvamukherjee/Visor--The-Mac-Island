import SwiftUI

/// One continuous shape for every notch state. The top edge is flush with
/// the screen's top edge — bottom corners round normally.
struct NotchShape: Shape {
    var bottomRadius: CGFloat

    static let closedBottomRadius: CGFloat = 12
    static let expandedBottomRadius: CGFloat = 28
    static let compactBottomRadius: CGFloat = 14

    var animatableData: CGFloat {
        get { bottomRadius }
        set { bottomRadius = newValue }
    }

    /// The top edge is flush, with no radius at all: any curve that removes
    /// material at the true top corner shows background through a gap exactly
    /// where the shape should meet the bezel. RESEARCH.md §2.5 wants an
    /// outward-flaring shoulder eventually — that has to *add* material
    /// outward, so it will not be a corner radius when it arrives.
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
