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
    /// Measured on a 15" M4 MacBook Air: screen 1710x1107pt, menu bar and
    /// `safeAreaInsets.top` both 33pt, cutout 185x33pt at x 763...948 (its
    /// midX is 855.5 against a screen midX of 855.0 — the island follows the
    /// cutout, not the screen, which is why every rect here centres on
    /// `closedRect.midX`).
    ///
    /// The cutout is *missing pixels*, not black ones: anything drawn in the
    /// top `closedRect.height` of the island's centre 185pt is hidden behind
    /// the camera housing. Rather than thread that dead band through every
    /// column, all expanded content starts below it — see NotchRootView.
    ///
    /// Heights are that clearance (33 + 6) plus the tallest column each
    /// layout measures plus 10pt of bottom padding. Idle's is the date block
    /// (46) + two event chips (80) + spacing; music's peek is one chip, so it
    /// comes out shorter — the island visibly compacts when playback starts.
    /// The panel frame uses `expandedSize` (the taller of the two) so the
    /// height change is a SwiftUI shape morph, never a window resize
    /// mid-hover.
    ///
    /// 400 wide is roughly 2.2x the cutout, matching the proportion asked for
    /// — it splits into a ~150pt agenda column and ~220pt of music column,
    /// which is the least the transport row fits in at full 38x34 targets.
    static let expandedIdleSize = CGSize(width: 400, height: 186)
    static let expandedMusicSize = CGSize(width: 400, height: 168)
    static let expandedSize = CGSize(
        width: max(expandedIdleSize.width, expandedMusicSize.width),
        height: max(expandedIdleSize.height, expandedMusicSize.height)
    )
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

    /// `expandedRect` widened to also contain `compactRect`. The panel is
    /// click-through outside the shape, so an over-wide canvas costs nothing
    /// visually — and it means collapsing out of expanded, which can grow
    /// wider before it gets shorter, never has to widen the frame
    /// mid-animation. That was the expanded→compact jitter bug.
    static func expandedCanvasRect(for screen: ScreenGeometryProviding) -> CGRect {
        expandedRect(for: screen).union(compactRect(for: screen))
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
