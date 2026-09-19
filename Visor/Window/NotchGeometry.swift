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
    static let fallbackClosedSize = CGSize(width: 200, height: 32)
    /// Widest wings any feature asks for; the canvas must cover them all.
    static let compactExtraWidth = IslandLayout.maxCompactExtraWidth

    /// The largest layout any feature declares, against a given cutout.
    static func expandedSize(closed: CGSize) -> CGSize {
        IslandLayout.maxExpandedSize(closed: closed)
    }

    /// What the SwiftUI canvas is sized to vertically: every resting layout
    /// plus squash headroom.
    static func canvasHeight(closed: CGSize) -> CGFloat {
        expandedSize(closed: closed).height + squashAllowance
    }

    /// Headroom below the tallest layout for the collapse squash, which
    /// briefly stretches the island past every resting size. The panel is
    /// click-through outside the silhouette so unused canvas costs nothing —
    /// but a shape taller than its window gets clipped, which is the whole
    /// class of bug this pass exists to remove.
    static let squashAllowance: CGFloat = 44

    /// Hardware trim for the closed silhouette. macOS reports the auxiliary
    /// areas and safe-area inset in whole points, but the physical cutout's
    /// edges don't land exactly on them — drawn straight from those numbers
    /// the shape reads a touch wide and a touch short against the real notch,
    /// which is visible to the eye even at a point or two. All zeros = draw
    /// exactly what the OS reports.
    ///
    /// Units are points: on a 2x display 0.5 is one physical pixel, which is
    /// the finest useful adjustment. Tuned against a 15" M4 MacBook Air by
    /// eye — adjust here, nowhere else, and only against real hardware.
    ///
    /// Narrows the shape, split evenly across both sides.
    static let closedWidthInset: CGFloat = 1
    /// Extends it further down; the top edge stays welded to the screen edge.
    static let closedHeightOffset: CGFloat = 1
    /// Nudges it sideways. The reported cutout midX is already half a point
    /// off the screen's, so this one earns its place even at 0.
    static let closedHorizontalOffset: CGFloat = 0

    /// The user's own trim from Settings, on top of the hardware
    /// calibration above. Two separate numbers on purpose: the constants
    /// above are "what this hardware actually measures" and are tuned once
    /// against real machines; these are "what this person prefers", and
    /// resetting one must not lose the other.
    static func userWidthOffset() -> CGFloat {
        CGFloat(UserDefaults.standard.double(forKey: Preferences.notchWidthOffsetKey))
    }

    static func userHeightOffset() -> CGFloat {
        CGFloat(UserDefaults.standard.double(forKey: Preferences.notchHeightOffsetKey))
    }

    /// Notch bounding box from the real hardware cutout, trimmed by the
    /// calibration above *and* by the user's own trim from Settings, or a
    /// centered pill-sized fallback on non-notched screens (which has no
    /// cutout to match, so it takes no trim).
    ///
    /// This overload reads `UserDefaults`, so it is for app code only —
    /// tests call the explicit-offset form below, or they would measure
    /// whatever the developer last left the sliders on.
    static func closedRect(for screen: ScreenGeometryProviding) -> CGRect {
        closedRect(for: screen, widthOffset: userWidthOffset(), heightOffset: userHeightOffset())
    }

    /// The offsets are parameters rather than read inside, so the geometry
    /// stays testable without touching `UserDefaults`.
    static func closedRect(
        for screen: ScreenGeometryProviding,
        widthOffset: CGFloat,
        heightOffset: CGFloat
    ) -> CGRect {
        let reportedHeight = screen.safeAreaInsets.top
        guard
            reportedHeight > 0,
            let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea,
            right.minX > left.maxX
        else {
            return fallbackRect(for: screen)
        }
        // Clamped so a stored value from an older build — or one edited by
        // hand — cannot produce a zero-width island with no way back to
        // Settings, which is right-click-on-the-island only.
        let width = max(
            8,
            right.minX - left.maxX - closedWidthInset
                + clamp(widthOffset, to: Preferences.notchWidthOffsetRange)
        )
        let height = max(
            8,
            reportedHeight + closedHeightOffset
                + clamp(heightOffset, to: Preferences.notchHeightOffsetRange)
        )
        return CGRect(
            x: left.maxX + closedWidthInset / 2 + closedHorizontalOffset,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }

    private static func clamp(_ value: CGFloat, to range: ClosedRange<Double>) -> CGFloat {
        min(max(value, CGFloat(range.lowerBound)), CGFloat(range.upperBound))
    }

    /// Shares the closed rect's horizontal center and top edge, per the
    /// approved plan's "frame follows shape" design.
    static func expandedRect(for screen: ScreenGeometryProviding) -> CGRect {
        let closed = closedRect(for: screen)
        let size = expandedSize(closed: closed.size)
        return CGRect(
            x: closed.midX - size.width / 2,
            y: closed.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Wings sit symmetrically outside the real notch, at menu-bar height —
    /// no vertical growth, unlike the expanded state.
    static func compactRect(for screen: ScreenGeometryProviding, extraWidth: CGFloat = compactExtraWidth) -> CGRect {
        let closed = closedRect(for: screen)
        let width = closed.width + extraWidth
        return CGRect(x: closed.midX - width / 2, y: closed.minY, width: width, height: closed.height)
    }

    /// `expandedRect` widened to also contain `compactRect`. The panel is
    /// click-through outside the shape, so an over-wide canvas costs nothing
    /// visually — and it means collapsing out of expanded, which can grow
    /// wider before it gets shorter, never has to widen the frame
    /// mid-animation. That was the expanded→compact jitter bug.
    static func expandedCanvasRect(for screen: ScreenGeometryProviding) -> CGRect {
        let base = expandedRect(for: screen).union(compactRect(for: screen))
        // Grows downward only: the top edge stays welded to the screen edge.
        return CGRect(
            x: base.minX,
            y: base.minY - squashAllowance,
            width: base.width,
            height: base.height + squashAllowance
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
