import CoreGraphics

/// One interior spacing scale for every expanded layout.
///
/// Features never see each other, so left to themselves they drifted to
/// their own numbers — 3, 6, 8, 10, 12 and 14 were all in use for the same
/// job — and the island read differently depending on which feature owned
/// it. Same reason every animation comes from `Motion`.
enum IslandSpacing {
    /// Island edge to content, left and right. Has to clear the bottom
    /// corners' own curvature, which cuts in by the expanded radius.
    static let gutter: CGFloat = 20
    /// Island bottom edge to content.
    static let bottom: CGFloat = 14
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
