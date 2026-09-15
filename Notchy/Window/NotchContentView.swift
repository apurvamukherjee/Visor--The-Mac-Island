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

    init(store: NotchStore, rootView: NotchRootView) {
        self.store = store
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        hostingView.frame.size = NotchGeometry.expandedSize
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
    /// sliver ever matters in practice). Now switches over all three
    /// states (closed/compact/expanded), matching NotchRootView's radii.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: nil)
        let (topRadius, bottomRadius): (CGFloat, CGFloat) = switch store.state {
        case .expanded: (NotchShape.expandedTopRadius, NotchShape.expandedBottomRadius)
        case .compact: (NotchShape.compactTopRadius, NotchShape.compactBottomRadius)
        case .closed: (NotchShape.closedTopRadius, NotchShape.closedBottomRadius)
        }
        let shape = NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
        guard shape.path(in: bounds).contains(local) else { return nil }
        return super.hitTest(point)
    }
}
