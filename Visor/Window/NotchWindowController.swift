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
            rootView: NotchRootView(store: store, canvasWidth: canvasSize.width),
            canvasSize: canvasSize
        )
        panel.contentView = contentView
        store.closedSize = closedRect.size
        repositionHostingView(for: closedRect.width)
        contentView.onShowSettings = { [weak self] in self?.onShowSettings?() }
        contentView.onMouseEntered = { [weak self] in self?.handleMouseEntered() }
        contentView.onMouseExited = { [weak self] in self?.handleMouseExited() }
    }

    func start() {
        panel.orderFrontRegardless()
        // After ordering front: `windowNumber` isn't valid until then.
        SkyLightPin.pin(panel)
        registerDropObservation()
        registerActivityObservation()
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

    private func collapseFromExpanded() {
        generation += 1
        let gen = generation
        let target: NotchState = store.currentActivity != nil ? .compact : .closed
        withAnimation(
            Motion.resolved(Motion.close),
            completionCriteria: .logicallyComplete
        ) {
            store.state = target
        } completion: { [weak self] in
            guard let self, gen == generation else { return }
            finishShrink(to: target)
        }
    }

    private func finishShrink(to target: NotchState) {
        guard let screen = Self.targetScreen() else { return }
        let rect = target == .compact ? NotchGeometry.compactRect(for: screen) : NotchGeometry.closedRect(for: screen)
        panel.setFrame(rect, display: true)
        if target == .closed {
            store.closedSize = rect.size
        }
        repositionHostingView(for: rect.width)
    }

    private func enterCompact() {
        guard let screen = Self.targetScreen() else { return }
        generation += 1
        let rect = NotchGeometry.compactRect(for: screen)
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
            completionCriteria: .logicallyComplete
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
        generation += 1
        store.state = .closed
        guard let screen = Self.targetScreen() else { return }
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
        let rect = switch store.state {
        case .expanded: NotchGeometry.expandedCanvasRect(for: screen)
        case .compact: NotchGeometry.compactRect(for: screen)
        case .closed: NotchGeometry.closedRect(for: screen)
        }
        panel.setFrame(rect, display: true)
        repositionHostingView(for: rect.width)
        panel.orderFrontRegardless()
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

    private static func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }) ?? NSScreen.main
    }
}
