import CoreGraphics
import Foundation

/// A screenshot the system just wrote, held only long enough to offer it.
struct ScreenshotCatch: Equatable, Sendable {
    let url: URL
    let thumbnail: CGImage?
    let caughtAt: Date

    /// `CGImage` has no useful equality, and two catches of the same file at
    /// the same instant are the same catch.
    static func == (lhs: ScreenshotCatch, rhs: ScreenshotCatch) -> Bool {
        lhs.url == rhs.url && lhs.caughtAt == rhs.caughtAt
    }
}
