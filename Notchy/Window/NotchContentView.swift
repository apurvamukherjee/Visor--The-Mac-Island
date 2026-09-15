import AppKit
import SwiftUI

/// Fills the panel; bounds track the window's current (closed/expanded) size,
/// so `NSTrackingArea(.inVisibleRect)` hover detection needs no global monitor.
@MainActor
final class NotchContentView: NSView {
    let hostingView: NSHostingView<NotchRootView>
    private let store: NotchStore
    private var trackingArea: NSTrackingArea?
    private var scrollOffset: CGFloat = 0

    /// Points of two-finger travel before a scroll counts as a track change.
    /// Low enough to flick, high enough that a stray scroll over the notch
    /// on the way to the menu bar doesn't skip a song.
    static let swipeThreshold: CGFloat = 40

    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onShowSettings: (() -> Void)?

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

    /// Two-finger swipe = track change. Trackpad scrolls only (`hasPrecise
    /// ScrollingDeltas`); a mouse wheel's coarse clicks would fire on the
    /// slightest nudge. Events only reach here when the cursor is inside the
    /// silhouette, since `hitTest` rejects everything else — no global
    /// monitor, nothing running while the island isn't under the pointer.
    override func scrollWheel(with event: NSEvent) {
        guard
            let commands = store.nowPlayingCommands,
            event.hasPreciseScrollingDeltas
        else {
            return super.scrollWheel(with: event)
        }
        // Normalise away the "natural scrolling" setting so the gesture
        // always follows the fingers: negative means they moved left.
        let delta = event.isDirectionInvertedFromDevice
            ? event.scrollingDeltaX
            : -event.scrollingDeltaX
        switch event.phase {
        case .began:
            scrollOffset = 0
        case .changed:
            scrollOffset += delta
        case .ended, .cancelled:
            defer { scrollOffset = 0 }
            guard abs(scrollOffset) > Self.swipeThreshold else { return }
            Haptics.selection()
            if scrollOffset < 0 {
                commands.next()
            } else {
                commands.previous()
            }
        default:
            break
        }
    }

    /// Called by `NotchPanel.sendEvent` before AppKit hands the event to the
    /// hosting view. Returns true when handled, so the panel can swallow it.
    /// Ignores anything outside the island's silhouette — the panel's frame
    /// is wider than what's drawn.
    func handleInterceptedEvent(_ event: NSEvent) -> Bool {
        guard hitTest(event.locationInWindow) != nil else { return false }
        switch event.type {
        case .smartMagnify:
            guard let commands = store.nowPlayingCommands else { return false }
            Haptics.toggle()
            commands.togglePlayPause()
            return true
        case .rightMouseUp:
            Haptics.toggle()
            onShowSettings?()
            return true
        default:
            return false
        }
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
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: nil)
        let bottomRadius: CGFloat = switch store.state {
        case .expanded: NotchShape.expandedBottomRadius
        case .compact: NotchShape.compactBottomRadius
        case .closed: NotchShape.closedBottomRadius
        }
        let shape = NotchShape(bottomRadius: bottomRadius)
        return shape.path(in: islandRect).contains(local) ? super.hitTest(point) : nil
    }

    /// The canvas is sized for the tallest expanded layout, so the silhouette
    /// is the top slice of `bounds` — and the slice shrinks with the music
    /// layout, or the strip below the shorter island would swallow clicks
    /// meant for whatever is behind it.
    private var islandRect: CGRect {
        let height = store.state == .expanded
            ? NotchGeometry.expandedSize(hasNowPlaying: store.nowPlaying != nil).height
            : NotchGeometry.expandedSize.height
        return CGRect(x: 0, y: 0, width: bounds.width, height: height)
    }
}
