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

    private let store: NotchStore
    private let panel: NotchPanel
    private let contentView: NotchContentView
    private let canvasSize: CGSize
    private var generation = 0
    private var isHovering = false
    private var isDisplayAsleep = false
    private var hoverIntentTask: Task<Void, Never>?
    private var closeIntentTask: Task<Void, Never>?
    private var squashTask: Task<Void, Never>?
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

    /// Swipe up: step back out of whatever the swipe down opened, or put the
    /// current activity away.
    ///
    /// It deliberately does **not** close the island. It used to, and that
    /// made the vertical axis mean two things at once — one swipe both
    /// changed what was on screen and shut the screen it was on, so paging
    /// between states was impossible and every gesture ended in the notch.
    /// The pointer leaving is what closes the island, as it always was; this
    /// only ever changes what is being shown.
    private func handleSwipeDismiss() {
        guard NewFeatures.islandPaging.isEnabled() else {
            Haptics.shapeChange()
            store.dismissCurrentActivity()
            return
        }
        turn(to: store.islandPage.above)
    }

    /// Swipe down: open the usage screen once it is asked for, otherwise
    /// bring back whatever was swiped away.
    ///
    /// The usage screen takes the gesture outright rather than sharing it,
    /// because a binding that depends on whether something happens to be
    /// dismissed is a binding nobody can predict. With the switch off this is
    /// exactly what it was.
    private func handleSwipeRestore() {
        guard NewFeatures.islandPaging.isEnabled() else {
            store.restoreDismissedActivity()
            guard NewFeatures.swipeDownOpens.isEnabled() else { return }
            openIslandForSwipe()
            return
        }
        turn(to: store.islandPage.below)
    }

    /// Turn to a screen, or open the island if it is not up yet.
    ///
    /// A swipe onto a closed island only ever opens it — onto the player,
    /// like every other way of opening it. Landing straight on the screen the
    /// gesture was reaching for would mean the island opened somewhere
    /// different depending on which direction your fingers moved, and the
    /// player being where you always find it is worth more than saving the
    /// second swipe.
    private func turn(to page: IslandPage) {
        guard store.state == .expanded else {
            openIslandForSwipe()
            return
        }
        // Already at an end. No haptic either: a buzz with nothing moving
        // reads as the gesture having failed rather than the stack having
        // run out.
        guard page != store.islandPage else { return }
        Haptics.shapeChange()
        withAnimation(Motion.resolved(Motion.morph)) {
            store.islandPage = page
        }
    }

    /// A swipe that lands on a closed island opens it; one that lands on an
    /// open island leaves it alone rather than restarting the spring.
    private func openIslandForSwipe() {
        guard store.state != .expanded else { return }
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
        expand()
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

    private func expand() {
        // Every route in here — hover, a drag arriving, onboarding, a swipe
        // down — wants no close still pending behind it. Cancelled once
        // here rather than at each of the four call sites, because the one
        // that forgot would collapse the island ~180ms after opening it.
        cancelCloseIntent()
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

    private func finishShrink(to target: NotchState) {
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

    private func enterCompact() {
        guard let screen = Self.targetScreen() else { return }
        generation += 1
        let rect = NotchGeometry.compactRect(for: screen, extraWidth: store.layout.compactExtraWidth)
        panel.setFrame(rect, display: true)
        repositionHostingView(for: rect.width)
        withAnimation(Motion.resolved(Motion.morph)) {
            store.state = .compact
        }
    }

    private func exitCompact() {
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

    private func registerActivityObservation() {
        withObservationTracking {
            _ = store.currentActivity
        } onChange: { [weak self] in
            Task { @MainActor in self?.handleActivityChange() }
        }
    }

    /// The welcome flow force-opens the island itself rather than waiting
    /// for a hover, and holds it open until it finishes — see
    /// `collapseFromExpanded`'s guard below.
    private func registerOnboardingObservation() {
        withObservationTracking {
            _ = store.isOnboardingActive
        } onChange: { [weak self] in
            Task { @MainActor in self?.handleOnboardingChange() }
        }
    }

    private func handleOnboardingChange() {
        registerOnboardingObservation()
        if store.isOnboardingActive {
            hoverIntentTask?.cancel()
            hoverIntentTask = nil
            guard store.state != .expanded else { return }
            expand()
        } else if !isHovering {
            collapseFromExpanded()
        }
    }

    /// The palette is the only thing in Visor that wants the keyboard, so
    /// the panel's `canBecomeKey` follows it exactly rather than being on
    /// all the time.
    private func registerPaletteObservation() {
        withObservationTracking {
            _ = store.isPaletteOpen
        } onChange: { [weak self] in
            Task { @MainActor in self?.handlePaletteChange() }
        }
    }

    /// Settings moving a size trim re-measures the island in place, so the
    /// sliders can be dialled in against the real notch.
    private func registerNotchSizeObservation() {
        withObservationTracking {
            _ = store.notchSizeTick
        } onChange: { [weak self] in
            Task { @MainActor in self?.handleNotchSizeChange() }
        }
    }

    private func handleNotchSizeChange() {
        registerNotchSizeObservation()
        guard let screen = Self.targetScreen() else { return }
        let closedRect = NotchGeometry.closedRect(for: screen)
        store.closedSize = closedRect.size
        // Only the resting frame is re-asserted; the state is left alone, so
        // a peek showing while the slider moves is not snapped shut.
        guard store.state == .closed else { return }
        panel.setFrame(closedRect, display: true)
        repositionHostingView(for: closedRect.width)
    }

    /// A drag heading for the notch should be met, not waited out — the
    /// island opens the moment it becomes a drop target and closes again when
    /// the drag leaves or lands.
    private func registerDropObservation() {
        withObservationTracking {
            _ = store.isDropTargeted
        } onChange: { [weak self] in
            Task { @MainActor in self?.handleDropTargetChange() }
        }
    }

    private func handleDropTargetChange() {
        registerDropObservation()
        guard !isDisplayAsleep else { return }
        if store.isDropTargeted {
            hoverIntentTask?.cancel()
            hoverIntentTask = nil
            guard store.state != .expanded else { return }
            expand()
        } else if !isHovering, store.state == .expanded {
            collapseFromExpanded()
        }
    }

    private func handleActivityChange() {
        registerActivityObservation()
        guard !isHovering, !isDisplayAsleep, store.state != .expanded else { return }
        switch (store.state, store.currentActivity != nil) {
        case (.closed, true): enterCompact()
        case (.compact, false): exitCompact()
        default: break
        }
    }

    /// Shared by screen-parameter changes, sleep, and wake: cancel any
    /// pending hover intent, snap closed with no animation, resync geometry.
    private func handleScreenChange() {
        isHovering = false
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
        cancelCloseIntent()
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

    private func repositionHostingView(for frameWidth: CGFloat) {
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

// MARK: - Palette and hiding

/// Both are *modes* rather than activities, and both need the panel
/// itself to change — key status for one, window ordering for the other —
/// which is why they live with the controller and not in a service.
@MainActor
private extension NotchWindowController {
    /// Hiding orders the panel away; the palette's hot key is global, so
    /// ⌃⌥K is still the way back — which is the only reason hiding the
    /// island is not a trap.
    func registerHiddenObservation() {
        withObservationTracking {
            _ = store.isIslandHidden
        } onChange: { [weak self] in
            Task { @MainActor in self?.handleHiddenChange() }
        }
    }

    func handleHiddenChange() {
        registerHiddenObservation()
        guard store.isIslandHidden else {
            panel.orderFrontRegardless()
            SkyLightPin.pin(panel)
            return
        }
        guard !store.isPaletteOpen else { return }
        panel.orderOut(nil)
    }

    func handlePaletteChange() {
        registerPaletteObservation()
        guard store.isPaletteOpen else {
            panel.acceptsKeyboard = false
            // Hands the keyboard back to whatever the user was typing in.
            // The frontmost app never changed — measured on a probe — so
            // this is giving up key status, not switching apps.
            NSApp.deactivate()
            if !isHovering {
                collapseFromExpanded()
            }
            // Closing the palette on a hidden island puts it away again,
            // rather than leaving the thing the user hid on screen.
            if store.isIslandHidden {
                panel.orderOut(nil)
            }
            return
        }
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
        // The palette has to be visible even when the island is hidden —
        // otherwise the only way back from hiding it would be to relaunch.
        panel.orderFrontRegardless()
        SkyLightPin.pin(panel)
        panel.acceptsKeyboard = true
        expand()
        panel.makeKey()
        panel.makeFirstResponder(contentView)
    }
}

// MARK: - Collapse squash

@MainActor
extension NotchWindowController {
    /// Squash, hold a beat, then close. The impulse is additive and rides its
    /// own spring, so the two axes read as squash-and-stretch rather than a
    /// uniform scale — SwiftUI folds a scoped `.animation(_:value:)` into the
    /// ambient transaction, so giving the frame's axes different curves
    /// directly does not work (measured).
    func collapseFromExpanded() {
        // The welcome flow holds the island open until the user finishes it
        // or replays it from Settings — a mouse-out mid-explanation should
        // not yank the island shut under an unread sentence. The palette
        // holds it open for the same reason: it was opened by a keystroke,
        // so the pointer's whereabouts are not what should close it.
        guard !store.isOnboardingActive, !store.isPaletteOpen else { return }
        // The page is deliberately *not* reset here. Clearing it first
        // re-resolved the layout while the island was still open, so
        // collapsing from the agent screen morphed out to the player's larger
        // card and only then closed. It is reset on the way in instead — see
        // `expand()` — which leaves every screen collapsing from its own size.
        generation += 1
        let gen = generation
        let target: NotchState = store.currentActivity != nil ? .compact : .closed
        squashTask?.cancel()
        squashTask = nil

        guard !Motion.reduceMotion else {
            clearSquash()
            runCollapse(to: target, generation: gen)
            return
        }

        let resting = store.layout.expandedSize(closed: store.closedSize)
        withAnimation(Motion.squash) {
            store.squashWidth = -resting.width * Motion.squashWidthFraction
            store.squashHeight = resting.height * Motion.squashHeightFraction
        }
        squashTask = Task { [weak self] in
            try? await Task.sleep(for: Motion.squashHold)
            guard !Task.isCancelled, let self, gen == generation else { return }
            squashTask = nil
            withAnimation(Motion.squash) {
                store.squashWidth = 0
                store.squashHeight = 0
            }
            runCollapse(to: target, generation: gen)
        }
    }

    /// `.removed`, not `.logicallyComplete`. Measured on this exact spring:
    /// `logicallyComplete` fires at t=0.355s with the shape still 3.7pt wider
    /// and 2.6pt taller than its target, which it does not reach until
    /// t=0.472s. Resizing the panel at the earlier mark clipped the only part
    /// of the shape still sticking out — the bottom corners — so the island
    /// snapped to a hard-edged rectangle and then visibly re-rounded.
    func runCollapse(to target: NotchState, generation gen: Int) {
        withAnimation(
            Motion.resolved(Motion.close),
            completionCriteria: .removed
        ) {
            store.state = target
        } completion: { [weak self] in
            guard let self, gen == generation else { return }
            finishShrink(to: target)
        }
    }

    func clearSquash() {
        squashTask?.cancel()
        squashTask = nil
        store.squashWidth = 0
        store.squashHeight = 0
    }
}
