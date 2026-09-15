import AppKit
import CoreGraphics

protocol ScreenGeometryProviding {
    var frame: CGRect { get }
    var safeAreaInsets: NSEdgeInsets { get }
    var auxiliaryTopLeftArea: CGRect? { get }
    var auxiliaryTopRightArea: CGRect? { get }
}

extension NSScreen: ScreenGeometryProviding {}

enum NotchGeometry {
    /// Sized to what the content actually measures, with a little slack: the
    /// music column comes to ~134pt (art 54 + title/artist 34 + controls 24 +
    /// spacing + bottom padding) and the idle view's right column to ~144pt
    /// (camera-housing clearance 32 + two event chips + the signature).
    /// Too tall leaves a dead band; too short and the content spills past the
    /// shape's bottom edge onto the desktop, which is what 180pt did.
    static let expandedSize = CGSize(width: 560, height: 168)
    static let fallbackClosedSize = CGSize(width: 200, height: 32)
    static let compactExtraWidth: CGFloat = 160
    static let chipBarHeight: CGFloat = 36
    static let chipBarGap: CGFloat = 8

    /// Notch bounding box from the real hardware cutout, or a centered
    /// pill-sized fallback on non-notched screens.
    static func closedRect(for screen: ScreenGeometryProviding) -> CGRect {
        let height = screen.safeAreaInsets.top
        guard
            height > 0,
            let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea,
            right.minX > left.maxX
        else {
            return fallbackRect(for: screen)
        }
        let width = right.minX - left.maxX
        return CGRect(x: left.maxX, y: screen.frame.maxY - height, width: width, height: height)
    }

    /// Shares the closed rect's horizontal center and top edge, per the
    /// approved plan's "frame follows shape" design.
    static func expandedRect(for screen: ScreenGeometryProviding) -> CGRect {
        let closed = closedRect(for: screen)
        return CGRect(
            x: closed.midX - expandedSize.width / 2,
            y: closed.maxY - expandedSize.height,
            width: expandedSize.width,
            height: expandedSize.height
        )
    }

    /// Wings sit symmetrically outside the real notch, at menu-bar height —
    /// no vertical growth, unlike the expanded state.
    static func compactRect(for screen: ScreenGeometryProviding) -> CGRect {
        let closed = closedRect(for: screen)
        let width = closed.width + compactExtraWidth
        return CGRect(x: closed.midX - width / 2, y: closed.minY, width: width, height: closed.height)
    }

    /// `expandedRect` widened to also contain `compactRect`, then extended
    /// downward to reserve the mood chip bar's strip. The panel is
    /// click-through outside the shape, so an over-tall canvas costs nothing
    /// visually — and it means neither collapsing out of expanded nor the
    /// chip bar animating in ever has to grow the frame mid-animation, which
    /// is what caused the expanded→compact jitter bug.
    static func expandedCanvasRect(for screen: ScreenGeometryProviding) -> CGRect {
        let union = expandedRect(for: screen).union(compactRect(for: screen))
        return CGRect(
            x: union.minX,
            y: union.minY - chipBarGap - chipBarHeight,
            width: union.width,
            height: union.height + chipBarGap + chipBarHeight
        )
    }

    private static func fallbackRect(for screen: ScreenGeometryProviding) -> CGRect {
        let size = fallbackClosedSize
        return CGRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
