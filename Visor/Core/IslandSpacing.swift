import CoreGraphics

/// One interior spacing scale for every expanded layout.
///
/// Features never see each other, so left to themselves they drifted to
/// their own numbers — 3, 6, 8, 10, 12 and 14 were all in use for the same
/// job — and the island read differently depending on which feature owned
/// it. Same reason every animation comes from `Motion`.
enum IslandSpacing {
    /// Island edge to content, left and right. Has to clear the bottom
    /// corners' own curvature, which cuts in by the expanded radius — and
    /// then some, or the content reads as edge-to-edge even when it is
    /// technically inside the shape. 26 still read flush on hardware:
    /// the artwork's halo and the date's digits are the widest things in
    /// the row and both sit at the extremes, so the eye measures from the
    /// glow, not the frame.
    static let gutter: CGFloat = 34
    /// Island bottom edge to content. Deliberately more than the gutter's
    /// old value for the same reason the gutter grew: the bottom corners
    /// are the roundest part of the shape, so content level with them needs
    /// more clearance to look evenly inset.
    static let bottom: CGFloat = 22
    /// Below the camera housing. Everything clears the cutout here rather
    /// than per column.
    static let cameraClearance: CGFloat = 10
    /// Between side-by-side columns.
    static let column: CGFloat = 12
    /// Between stacked blocks within a column.
    static let block: CGFloat = 10
    /// Between rows of a list.
    static let row: CGFloat = 5
    /// Between thumbnails on the shelf.
    static let tile: CGFloat = 10
}
