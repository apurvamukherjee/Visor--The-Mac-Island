import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Fills the panel; bounds track the window's current (closed/expanded) size,
/// so `NSTrackingArea(.inVisibleRect)` hover detection needs no global monitor.
@MainActor
final class NotchContentView: NSView {
    let hostingView: NSHostingView<NotchRootView>
    private let store: NotchStore
    private var trackingArea: NSTrackingArea?
    private var scrollOffset: CGFloat = 0
    private var verticalOffset: CGFloat = 0
    private var axis = SwipeAxis.undetermined

    /// Points of two-finger travel before a scroll counts as a track change.
    /// Low enough to flick, high enough that a stray scroll over the notch
    /// on the way to the menu bar doesn't skip a song.
    static let swipeThreshold: CGFloat = 40
    /// Vertical travel before a swipe counts as dismiss or restore. Higher
    /// than the horizontal one: an up-flick is also how you leave the notch,
    /// so it has to be deliberate.
    static let verticalSwipeThreshold: CGFloat = 60

    /// Which way a two-finger swipe is going. Locked once one axis leads the
    /// other by `axisDominance`, so a diagonal flick can skip a track *or*
    /// dismiss the island but never both — which is what happened when each
    /// axis was tested on its own.
    enum SwipeAxis {
        case undetermined
        case horizontal
        case vertical
    }

    /// How far one axis must lead before the gesture locks to it, and the
    /// travel below which neither leads yet.
    private static let axisDominance: CGFloat = 1.25
    private static let axisLockTravel: CGFloat = 2

    /// Pure, so the lock can be tested without a trackpad.
    static func resolveAxis(horizontal: CGFloat, vertical: CGFloat) -> SwipeAxis {
        let absH = abs(horizontal)
        let absV = abs(vertical)
        guard max(absH, absV) >= axisLockTravel else { return .undetermined }
        if absH > absV * axisDominance {
            return .horizontal
        }
        if absV > absH * axisDominance {
            return .vertical
        }
        return .undetermined
    }

    var onMouseEntered: (() -> Void)?
    var onMouseExited: (() -> Void)?
    var onShowSettings: (() -> Void)?
    /// Swipe up on the island: dismiss whatever it is showing.
    var onSwipeDismiss: (() -> Void)?
    /// Swipe down on a dismissed island: bring it back.
    var onSwipeRestore: (() -> Void)?

    override var isFlipped: Bool {
        true
    }

    init(store: NotchStore, rootView: NotchRootView, canvasSize: CGSize) {
        self.store = store
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        hostingView.frame.size = canvasSize
        addSubview(hostingView)
        observeIslandSize()
    }

    /// The tracking area is the island's own rect rather than `bounds`, so
    /// it no longer rides `.inVisibleRect` and has to be rebuilt whenever
    /// that rect changes. One-shot, so it re-arms itself.
    private func observeIslandSize() {
        withObservationTracking {
            _ = store.state
            _ = store.closedSize
            _ = store.layout
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeIslandSize()
                self?.updateTrackingAreas()
            }
        }
    }

    required init?(coder _: NSCoder) {
        nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Rebuilt only when the rect actually moved. Replacing a tracking
        // area makes AppKit re-evaluate the cursor against it, which
        // re-delivers `mouseEntered` even though the pointer never moved —
        // and that read as the island opening twice, with two haptics. The
        // island resizes on every state change, so this is the difference
        // between one rebuild and one per open.
        let rect = islandRect
        if let trackingArea {
            guard trackingArea.rect != rect else { return }
            removeTrackingArea(trackingArea)
        }
        // `.mouseMoved` is still event-driven — AppKit delivers it only while
        // the cursor is inside this view, so nothing runs when the pointer is
        // elsewhere on screen. This is not the global monitor §5.2.2 bans.
        //
        // The rect is the island's own resting size, not `bounds`. The canvas
        // is sized for the tallest layout any feature declares, so tracking
        // `bounds` armed hover across a block of screen far below the closed
        // notch — the cursor entered the island without ever touching it.
        // `.inVisibleRect` is dropped with it: that option pins the area to
        // `bounds` and would undo this.
        let area = NSTrackingArea(
            rect: rect,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
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
        guard event.hasPreciseScrollingDeltas else {
            return super.scrollWheel(with: event)
        }
        // Normalise away the "natural scrolling" setting on both axes so the
        // gesture always follows the fingers: negative x means they moved
        // left, negative y means they moved up.
        let inverted = event.isDirectionInvertedFromDevice
        switch event.phase {
        case .began:
            beginSwipe()
        case .changed:
            continueSwipe(
                deltaX: inverted ? event.scrollingDeltaX : -event.scrollingDeltaX,
                deltaY: inverted ? event.scrollingDeltaY : -event.scrollingDeltaY
            )
        case .ended, .cancelled:
            endSwipe()
        default:
            break
        }
    }

    private func beginSwipe() {
        scrollOffset = 0
        verticalOffset = 0
        axis = .undetermined
    }

    /// Accumulates travel and locks the axis. Nothing is drawn while the
    /// gesture is live: the island used to squeeze in proportion to it, and
    /// that read as the notch being dragged about rather than a track
    /// changing. The result of the swipe is the whole feedback.
    private func continueSwipe(deltaX: CGFloat, deltaY: CGFloat) {
        scrollOffset += deltaX
        verticalOffset += deltaY
        guard axis == .undetermined else { return }
        axis = Self.resolveAxis(horizontal: scrollOffset, vertical: verticalOffset)
    }

    private func endSwipe() {
        let settledAxis = axis
        let horizontal = scrollOffset
        let vertical = verticalOffset
        scrollOffset = 0
        verticalOffset = 0
        axis = .undetermined

        switch settledAxis {
        case .horizontal:
            guard let commands = store.nowPlayingCommands, abs(horizontal) > Self.swipeThreshold else { return }
            // Swiping *right* advances, the way flicking a card off the top
            // of a deck does — the previous track comes back from the left.
            // This is the inverse of what shipped first, which followed the
            // fingers instead of the content.
            if horizontal < 0 {
                commands.previous()
            } else {
                commands.next()
            }
        case .vertical:
            guard abs(vertical) > Self.verticalSwipeThreshold else { return }
            // Negative is upward, which is the dismiss direction — the
            // island slides back into the notch it came from.
            if vertical < 0 {
                onSwipeDismiss?()
            } else {
                onSwipeRestore?()
            }
        case .undetermined:
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

    /// Only while the palette is open. The island is not a text field the
    /// rest of the time, and a view that always accepted first responder
    /// would be one more thing competing for the keyboard.
    override var acceptsFirstResponder: Bool {
        store.isPaletteOpen
    }

    /// The palette's whole input path. Typing goes to the store rather than
    /// a `TextField`, so there is no SwiftUI focus to manage inside a
    /// non-activating panel.
    override func keyDown(with event: NSEvent) {
        guard store.isPaletteOpen else {
            return super.keyDown(with: event)
        }
        switch Int(event.keyCode) {
        case kVK_Escape:
            store.closePalette()
        case kVK_Return, kVK_ANSI_KeypadEnter:
            store.runPaletteSelection()
        case kVK_DownArrow:
            store.movePaletteSelection(by: 1)
        case kVK_UpArrow:
            store.movePaletteSelection(by: -1)
        case kVK_Delete:
            store.updatePaletteQuery(String(store.paletteQuery.dropLast()))
        default:
            // ⌘-anything belongs to the system, and control characters are
            // the arrow and function keys arriving as text.
            guard
                !event.modifierFlags.contains(.command),
                let typed = event.charactersIgnoringModifiers,
                !typed.isEmpty,
                typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
            else {
                return
            }
            store.updatePaletteQuery(store.paletteQuery + typed)
        }
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
            store.shelf.isEmpty,
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
        let radii: NotchRadii = switch store.state {
        case .expanded: store.layout.expandedRadii
        case .compact: store.layout.compactRadii
        case .closed: .closed
        }
        let shape = NotchShape(radii)
        return shape.path(in: islandRect).contains(local) ? super.hitTest(point) : nil
    }

    /// The canvas is sized for the tallest expanded layout, so the silhouette
    /// is the top slice of `bounds`.
    ///
    /// Every state now measures its *own* resting size. It used to fall back
    /// to `NotchGeometry.expandedSize` whenever the island was not expanded,
    /// which made the closed island's hover target the full height of the
    /// tallest layout — a ~220pt block of screen under the notch that
    /// swallowed the cursor and expanded the island on the way past. The
    /// closed target is now the cutout itself, which is the only thing
    /// actually drawn there.
    private var islandRect: CGRect {
        let resting = store.restingSize(for: store.state)
        // Centred, because every rect the geometry produces shares the
        // cutout's midX while the canvas is wider than all of them. Measured
        // against `bounds`, not the frame, so it holds mid-animation too.
        let width = min(resting.width, bounds.width)
        return CGRect(
            x: (bounds.width - width) / 2,
            y: 0,
            width: width,
            height: resting.height
        )
    }
}
