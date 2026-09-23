import AppKit
import SwiftUI

/// Orchestrates frame-vs-animation sequencing: grow sets the frame first
/// (invisible, transparent-into-transparent) then animates the shape;
/// shrink animates the shape first then sets the frame last. A generation
/// counter guards a stale collapse completion from yanking the frame if a
/// rapid re-hover retargets the animation mid-flight.
@MainActor
final class NotchWindowController {
    var onShowSettings: (() -> Void)?

    let store: NotchStore
    let panel: NotchPanel
    let contentView: NotchContentView
    private let canvasSize: CGSize
    var generation = 0
    var isHovering = false
    var isDisplayAsleep = false
    var hoverIntentTask: Task<Void, Never>?
    private var closeIntentTask: Task<Void, Never>?
    var squashTask: Task<Void, Never>?
    var retractTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    /// The mirror of the hover-intent delay, on the way out. Opening has
    /// always been filtered through an intent delay and closing through
    /// nothing at all, so the island was deliberate about opening and
    /// twitchy about closing — clipping its edge on the way to the scrub bar
    /// slammed it shut mid-gesture. Slightly longer than the open delay
    /// because a pointer leaving and coming back is a correction, while a
    /// pointer arriving is usually on purpose.
    private static let closeIntentDelay: Duration = .milliseconds(180)

    init?(store: NotchStore) {
        guard let screen = Self.targetScreen() else { return nil }
        self.store = store
        let closedRect = NotchGeometry.closedRect(for: screen)
        let canvasSize = NotchGeometry.expandedCanvasRect(for: screen).size
        self.canvasSize = canvasSize
        panel = NotchPanel(contentRect: closedRect)
        contentView = NotchContentView(
            store: store,
            rootView: NotchRootView(store: store, canvasSize: canvasSize),
            canvasSize: canvasSize
        )
        panel.contentView = contentView
        store.closedSize = closedRect.size
        repositionHostingView(for: closedRect.width)
        store.isCapsule = screen.isDynamicIsland
        contentView.onShowSettings = { [weak self] in self?.onShowSettings?() }
        contentView.onMouseEntered = { [weak self] in self?.handleMouseEntered() }
        contentView.onMouseExited = { [weak self] in self?.handleMouseExited() }
        contentView.onSwipeDismiss = { [weak self] in self?.handleSwipeDismiss() }
        contentView.onSwipeRestore = { [weak self] in self?.handleSwipeRestore() }
    }

    func start() {
        panel.orderFrontRegardless()
        // After ordering front: `windowNumber` isn't valid until then.
        SkyLightPin.pin(panel)
        registerDropObservation()
        registerActivityObservation()
        registerOnboardingObservation()
        registerNotchSizeObservation()
        registerPaletteObservation()
        registerHiddenObservation()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleScreenChange() }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleSpaceChange() }
        }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleDisplaySleep() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleDisplayWake() }
        }
    }

    func stop() {
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
        cancelCloseIntent()
        cancelChinRetraction()
        squashTask?.cancel()
        squashTask = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        // These three come from the workspace centre, not the default one —
        // removing them from the wrong centre leaked them.
        for observer in [spaceObserver, sleepObserver, wakeObserver].compactMap(\.self) {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        screenObserver = nil
        spaceObserver = nil
        sleepObserver = nil
        wakeObserver = nil
        panel.orderOut(nil)
    }

    private func handleMouseEntered() {
        isHovering = true
        // Coming back cancels a pending close, which is the whole point of
        // there being one — and it has to happen now, not when the hover
        // intent fires, or a re-entry inside the close window still closes.
        cancelCloseIntent()
        scheduleExpand()
    }

    private func handleMouseExited() {
        isHovering = false
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
        guard NewFeatures.closeIntentDelay.isEnabled() else {
            collapseFromExpanded()
            return
        }
        closeIntentTask?.cancel()
        closeIntentTask = Task { [weak self] in
            try? await Task.sleep(for: Self.closeIntentDelay, tolerance: .milliseconds(30))
            guard !Task.isCancelled, let self, !isHovering else { return }
            closeIntentTask = nil
            collapseFromExpanded()
        }
    }

    private func cancelCloseIntent() {
        closeIntentTask?.cancel()
        closeIntentTask = nil
    }

    private func scheduleExpand() {
        hoverIntentTask?.cancel()
        hoverIntentTask = Task { [weak self] in
            // Read per hover rather than cached: Settings can move it while
            // the island is alive, and a hover is not a hot path.
            try? await Task.sleep(for: Preferences.hoverIntentDelay)
            guard !Task.isCancelled else { return }
            self?.expand()
        }
    }

    func expand() {
        // Every route in here — hover, a drag arriving, onboarding, a swipe
        // down — wants no close still pending behind it. Cancelled once
        // here rather than at each of the four call sites, because the one
        // that forgot would collapse the island ~180ms after opening it.
        cancelCloseIntent()
        cancelChinRetraction()
        // Already open: nothing to do, and re-running would buzz a second
        // haptic and restart the open spring mid-flight. Rebuilding the
        // tracking area re-delivers `mouseEntered` under a stationary
        // cursor, so this is reached routinely, not just on a fast re-hover.
        guard store.state != .expanded else { return }
        guard let screen = Self.targetScreen() else { return }
        // Every open starts on the player. Set while the island is still
        // closed, so there is nothing on screen to morph — the island simply
        // grows into the right screen rather than arriving on the last one
        // and correcting itself.
        store.islandPage = .home
        // The style can only be changed from Settings, which means the island
        // was closed while it happened — re-reading it here is therefore never
        // stale, and is one read per open rather than an observer.
        store.pagingStyle = PagingStyle.current()
        generation += 1
        // Widened to expandedCanvasRect (not just expandedRect) so that
        // collapsing back out — which can grow wider before it gets
        // shorter, since compact may exceed expandedSize's width — never
        // needs to widen the frame mid-animation. See collapseFromExpanded.
        clearSquash()
        let canvasRect = NotchGeometry.expandedCanvasRect(for: screen)
        panel.setFrame(canvasRect, display: true)
        repositionHostingView(for: canvasRect.width)
        // Only on the way open: the hover-intent delay has already filtered
        // out cursors merely passing over the notch, and buzzing on every
        // collapse as well would make the gesture feel chattery.
        Haptics.shapeChange()
        withAnimation(Motion.resolved(Motion.open)) {
            store.state = .expanded
        }
    }

    func finishShrink(to target: NotchState) {
        guard let screen = Self.targetScreen() else { return }
        let rect = target == .compact
            ? NotchGeometry.compactRect(for: screen, extraWidth: store.layout.compactExtraWidth)
            : NotchGeometry.closedRect(for: screen)
        panel.setFrame(rect, display: true)
        if target == .closed {
            store.closedSize = rect.size
        }
        repositionHostingView(for: rect.width)
    }

    func enterCompact() {
        guard let screen = Self.targetScreen() else { return }
        generation += 1
        let rect = NotchGeometry.compactRect(for: screen, extraWidth: store.layout.compactExtraWidth)
        panel.setFrame(rect, display: true)
        repositionHostingView(for: rect.width)
        withAnimation(Motion.resolved(Motion.morph)) {
            store.state = .compact
        }
    }

    func exitCompact() {
        generation += 1
        let gen = generation
        withAnimation(
            Motion.resolved(Motion.morph),
            completionCriteria: .removed
        ) {
            store.state = .closed
        } completion: { [weak self] in
            guard let self, gen == generation else { return }
            finishShrink(to: .closed)
        }
    }

    /// pending hover intent, snap closed with no animation, resync geometry.
    /// Shared by screen-parameter changes, sleep, and wake: cancel any
    /// pending hover intent, snap closed with no animation, resync geometry.
    func handleScreenChange() {
        isHovering = false
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
        cancelCloseIntent()
        cancelChinRetraction()
        clearSquash()
        generation += 1
        store.state = .closed
        guard let screen = Self.targetScreen() else { return }
        store.isCapsule = screen.isDynamicIsland
        let closedRect = NotchGeometry.closedRect(for: screen)
        panel.setFrame(closedRect, display: true)
        store.closedSize = closedRect.size
        repositionHostingView(for: closedRect.width)
    }

    /// A Space switch can leave the panel behind the new Space's windows or
    /// at a stale frame. Re-assert both for whatever state we're in — unlike
    /// `handleScreenChange`, this keeps the current state, so a live compact
    /// activity survives the switch instead of snapping closed.
    private func handleSpaceChange() {
        guard let screen = Self.targetScreen() else { return }
        store.isCapsule = screen.isDynamicIsland
        // A full-screen space is somebody watching or presenting something;
        // the island sitting over it is exactly what they did not ask for.
        // Checked here because a Space switch is the only way in or out.
        if Preferences.hidesInFullscreen, SkyLightPin.isFullscreenSpaceActive(on: screen) {
            panel.orderOut(nil)
            return
        }
        panel.orderFrontRegardless()
        let rect = switch store.state {
        case .expanded: NotchGeometry.expandedCanvasRect(for: screen)
        case .compact: NotchGeometry.compactRect(for: screen, extraWidth: store.layout.compactExtraWidth)
        case .closed: NotchGeometry.closedRect(for: screen)
        }
        panel.setFrame(rect, display: true)
        repositionHostingView(for: rect.width)
    }

    private func handleDisplaySleep() {
        isDisplayAsleep = true
        handleScreenChange()
    }

    private func handleDisplayWake() {
        isDisplayAsleep = false
        handleScreenChange()
        handleActivityChange()
    }

    func repositionHostingView(for frameWidth: CGFloat) {
        contentView.hostingView.frame.origin = CGPoint(
            x: (frameWidth - canvasSize.width) / 2,
            y: 0
        )
    }

    /// Which screen the island lives on, honouring the Settings choice and
    /// falling back the way it always did — a notched screen, then whatever
    /// is main.
    static func targetScreen() -> NSScreen? {
        switch NotchScreenChoice.current {
        case .automatic:
            NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }) ?? NSScreen.main
        case .builtIn:
            NSScreen.screens.first(where: \.isBuiltInDisplay) ?? NSScreen.main
        case .main:
            NSScreen.main
        }
    }
}
