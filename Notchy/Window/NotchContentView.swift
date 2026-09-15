import AppKit
import SwiftUI

/// Fills the panel; bounds track the window's current (closed/expanded) size,
/// so `NSTrackingArea(.inVisibleRect)` hover detection needs no global monitor.
@MainActor
final class NotchContentView: NSView {
    let hostingView: NSHostingView<NotchRootView>
    private let store: NotchStore
    private var trackingArea: NSTrackingArea?

    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?

    override var isFlipped: Bool {
        true
    }

    init(store: NotchStore, rootView: NotchRootView, canvasSize: CGSize) {
        self.store = store
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        hostingView.frame.size = canvasSize
        addSubview(hostingView)
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with _: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with _: NSEvent) {
        onMouseExited?()
    }

    /// Click-through outside the shape's silhouette. Tested against the
    /// current state's target radii, not interpolated live geometry — an
    /// accepted approximation (ponytail: lags the visual shape during the
    /// ~300-400ms animation window; upgrade to interpolated radii if that
    /// sliver ever matters in practice). Switches over all three states
    /// (closed/compact/expanded), matching NotchRootView's radii.
    ///
    /// The mood chip bar is docked *below* the shape with a gap, so it falls
    /// outside that silhouette — without the union below, the chips would
    /// render but be unclickable.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: nil)
        let (topRadius, bottomRadius): (CGFloat, CGFloat) = switch store.state {
        case .expanded: (NotchShape.expandedTopRadius, NotchShape.expandedBottomRadius)
        case .compact: (NotchShape.compactTopRadius, NotchShape.compactBottomRadius)
        case .closed: (NotchShape.closedTopRadius, NotchShape.closedBottomRadius)
        }
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
        if shape.path(in: islandRect).contains(local) {
            return super.hitTest(point)
        }
        if chipBarIsVisible, chipBarRect.contains(local) {
            return super.hitTest(point)
        }
        return nil
    }

    /// The canvas reserves vertical room for the chip bar, so the island's
    /// own rect is the top slice of `bounds` — building the shape path
    /// against the full `bounds` would stretch the silhouette downward.
    private var islandRect: CGRect {
        CGRect(x: 0, y: 0, width: bounds.width, height: NotchGeometry.expandedSize.height)
    }

    private var chipBarIsVisible: Bool {
        store.state == .expanded && store.nowPlaying?.isPlaying == true
    }

    /// `isFlipped` is true, so local y grows downward — the chip bar sits at
    /// a *larger* y than the island. This is the opposite convention from
    /// NotchGeometry's bottom-left screen space; don't conflate them.
    private var chipBarRect: CGRect {
        CGRect(
            x: 0,
            y: NotchGeometry.expandedSize.height + NotchGeometry.chipBarGap,
            width: bounds.width,
            height: NotchGeometry.chipBarHeight
        )
    }
}
