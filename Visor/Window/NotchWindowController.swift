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
    private var squashTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    private static let hoverIntentDelay: Duration = .milliseconds(120)

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
        contentView.onSwipeRestore = { [weak self] in self?.store.restoreDismissedActivity() }
    }

    func start() {
        panel.orderFrontRegardless()
        // After ordering front: `windowNumber` isn't valid until then.
        SkyLightPin.pin(panel)
        registerDropObservation()
        registerActivityObservation()
        registerOnboardingObservation()
        registerNotchSizeObservation()
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

    /// Swipe up on the island: put the current activity away and collapse
    /// out of whatever it was showing, so the gesture reads as pushing the
    /// island back into the notch rather than merely changing its contents.
    private func handleSwipeDismiss() {
        store.dismissCurrentActivity()
        Haptics.shapeChange()
        if store.state == .expanded {
            isHovering = false
            collapseFromExpanded()
        }
    }

    private func handleMouseEntered() {
        isHovering = true
        scheduleExpand()
    }

    private func handleMouseExited() {
        isHovering = false
        hoverIntentTask?.cancel()
        hoverIntentTask = nil
        collapseFromExpanded()
    }

    private func scheduleExpand() {
        hoverIntentTask?.cancel()
        hoverIntentTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hoverIntentDelay)
            guard !Task.isCancelled else { return }
            self?.expand()
        }
    }

    private func expand() {
        guard let screen = Self.targetScreen() else { return }
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
        // not yank the island shut under an unread sentence.
        guard !store.isOnboardingActive else { return }
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
