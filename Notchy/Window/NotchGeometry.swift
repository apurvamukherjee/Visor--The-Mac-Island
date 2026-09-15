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
    static let expandedSize = CGSize(width: 320, height: 120)
    static let fallbackClosedSize = CGSize(width: 200, height: 32)
    static let compactExtraWidth: CGFloat = 160

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
