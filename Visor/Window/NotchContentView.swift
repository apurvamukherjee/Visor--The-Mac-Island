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
        // `.mouseMoved` is still event-driven — AppKit delivers it only while
        // the cursor is inside this view, so nothing runs when the pointer is
        // elsewhere on screen. This is not the global monitor §5.2.2 bans.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
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
        // Two-finger double tap (`smartMagnify`) needs "Smart zoom" enabled in
        // Trackpad settings, so a plain double-click is accepted too — same
        // gesture for anyone who has that turned off, or is using a mouse.
        case .smartMagnify, .leftMouseUp:
            // A double-click that landed on a control belongs to that control.
            // Swallowing it here turned a double-tap on the transport buttons
            // or the screenshot chip's dismiss badge into a play/pause.
            guard event.type == .smartMagnify || !isOverInteractiveContent(event) else { return false }
            // `nowPlayingCommands` is set for the app's whole lifetime, so
            // this is the only signal for "is there actually something to
            // play or pause" — otherwise the double-click is a no-op on an
            // idle island, which the wave easter egg takes over instead.
            guard store.nowPlaying != nil, let commands = store.nowPlayingCommands else {
                store.triggerWave()
                return true
            }
            commands.togglePlayPause()
            return true
        case .rightMouseUp:
            onShowSettings?()
            return true
        default:
            return false
        }
    }

    /// True when the hosting view has a control under the point. SwiftUI
    /// buttons land as their own subviews inside the hosting view, so anything
    /// deeper than the hosting view itself is content that wants the click.
    private func isOverInteractiveContent(_ event: NSEvent) -> Bool {
        let local = hostingView.convert(event.locationInWindow, from: nil)
        guard let hit = hostingView.hitTest(local) else { return false }
        return hit !== hostingView
    }

    override func mouseEntered(with _: NSEvent) {
        onMouseEntered?()
    }

    override func mouseExited(with _: NSEvent) {
        store.hoverPoint = nil
        onMouseExited?()
    }

    /// Only meaningful while the expanded music card is on screen, so the
    /// store write is skipped entirely otherwise — the cursor crossing the
    /// closed island, the idle agenda or a screenshot chip would otherwise
    /// re-render the island on every mouse move for a value nothing reads.
    ///
    /// Quantised to `hoverStep`: a tilt is a ±12° effect across the whole
    /// card, so sub-percent cursor movements are invisible but each one was
    /// costing a full view-graph pass at the mouse's event rate.
    override func mouseMoved(with event: NSEvent) {
        guard
            store.state == .expanded,
            store.nowPlaying != nil,
            store.screenshot == nil,
            !Motion.reduceMotion
        else {
            return
        }
        let local = convert(event.locationInWindow, from: nil)
        let point = Self.normalized(local, in: islandRect)
        guard Self.isSignificantMove(from: store.hoverPoint, to: point) else { return }
        store.hoverPoint = point
    }

    /// Smallest cursor move worth re-rendering for, in normalised units.
    private static let hoverStep: CGFloat = 0.02

    static func isSignificantMove(from old: CGPoint?, to new: CGPoint) -> Bool {
        guard let old else { return true }
        return abs(old.x - new.x) >= hoverStep || abs(old.y - new.y) >= hoverStep
    }

    /// Cursor position as (-1...1) on both axes, centre-origin. Pure so the
    /// clamping is testable without a window.
    static func normalized(_ point: CGPoint, in rect: CGRect) -> CGPoint {
        guard rect.width > 0, rect.height > 0 else { return .zero }
        let offsetX = (point.x - rect.midX) / (rect.width / 2)
        let offsetY = (point.y - rect.midY) / (rect.height / 2)
        return CGPoint(x: min(max(offsetX, -1), 1), y: min(max(offsetY, -1), 1))
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
