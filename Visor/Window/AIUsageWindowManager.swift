import AppKit
import SwiftUI

/// Puts the AI usage badge in its own window beside the notch.
///
/// A second window rather than a slot inside the island, for the reason
/// `AIUsageBadgeView` gives: `IslandLayout`'s sizes are tight deltas from the
/// measured cutout, and a permanent extra element in the wings would have to
/// move numbers that are already tuned. Nothing here touches `NotchShape`,
/// `IslandLayout`, or the island's panel, so the badge cannot distort them.
///
/// Pinned at the island's own SkyLight level (`.aboveDesktop`, 100): above
/// every ordinary window, and below the lock shield — so today's token count
/// is not sitting on a locked screen.
///
/// **The visibility rule.** With nothing playing, the badge is simply up.
/// While music owns the island, it hides — the notch's own wings are busy and
/// two things competing for the same glance is the distortion this feature
/// was asked not to cause — and comes back the moment the island is expanded,
/// where there is room for both.
@MainActor
final class AIUsageWindowManager {
    private let store: NotchStore
    private var window: NSPanel?
    private var hostingView: NSHostingView<AIUsageBadgeView>?
    private var hasPinned = false
    private var isPresented = false
    private var hideTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?

    /// Gap between the island's widest compact wing and the badge, so the two
    /// never touch even when a peek is at full width.
    private static let gap: CGFloat = 12
    private static let size = CGSize(width: 150, height: 22)
    /// Long enough for the badge to fade before the window is ordered out.
    private static let hideDelay: Duration = .milliseconds(320)

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        registerObservation()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshPosition() }
        }
        sync()
    }

    func stop() {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        hideTask?.cancel()
        hideTask = nil
        isPresented = false
        release()
    }

    /// Re-armed on each change: `withObservationTracking` is one-shot.
    private func registerObservation() {
        withObservationTracking {
            _ = store.aiUsage
            _ = store.state
            _ = store.currentActivity
            _ = store.isIslandHidden
            _ = store.closedSize
        } onChange: { [weak self] in
            Task { @MainActor in self?.handleChange() }
        }
    }

    private func handleChange() {
        registerObservation()
        sync()
    }

    /// Whether the badge should be up at all right now.
    ///
    /// Music is the one activity it stands down for, and only while the
    /// island is closed — expanded, the island has moved out of the way of
    /// its own wings and both fit.
    private var shouldPresent: Bool {
        guard NewFeatures.aiUsageTracker.isEnabled(), !store.isIslandHidden else { return false }
        // Nothing used today is nothing to report; an empty badge is clutter.
        guard !store.aiUsage.isEmpty else { return false }
        let kind = store.currentActivity?.kind
        let isMusic = kind == .nowPlaying || kind == .pausedTrack
        return !isMusic || store.state == .expanded
    }

    private func sync() {
        guard shouldPresent else {
            hide()
            return
        }
        present()
    }

    private func hide() {
        guard isPresented else {
            release()
            return
        }
        isPresented = false
        hostingView?.rootView = makeRootView(isPresented: false)
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hideDelay)
            guard !Task.isCancelled, let self, !isPresented else { return }
            release()
        }
    }

    private func present() {
        guard let screen = Self.currentScreen() else { return }
        let frame = Self.badgeFrame(on: screen)
        let window = makeWindowIfNeeded(frame: frame)
        if window.frame != frame {
            window.setFrame(frame, display: true)
        }

        hideTask?.cancel()
        hideTask = nil
        let wasPresented = isPresented
        isPresented = true

        let rootView = makeRootView(isPresented: wasPresented)
        if let hostingView {
            hostingView.rootView = rootView
            hostingView.frame = CGRect(origin: .zero, size: frame.size)
        } else {
            let view = NSHostingView(rootView: rootView)
            view.frame = CGRect(origin: .zero, size: frame.size)
            view.autoresizingMask = [.width, .height]
            hostingView = view
            window.contentView = view
        }

        window.orderFrontRegardless()
        if !hasPinned {
            // After ordering front: `windowNumber` is only valid then.
            SkyLightPin.pin(window, level: .aboveDesktop)
            hasPinned = true
        }
        guard !wasPresented else { return }
        // Next turn, so the badge has a hidden state to fade out of.
        Task { @MainActor [weak self] in
            guard let self, isPresented, let hostingView else { return }
            hostingView.rootView = makeRootView(isPresented: true)
        }
    }

    private func makeRootView(isPresented: Bool) -> AIUsageBadgeView {
        AIUsageBadgeView(
            usage: store.aiUsage,
            claudeBudget: Preferences.dailyTokenBudget(for: .claude),
            codexBudget: Preferences.dailyTokenBudget(for: .codex),
            isPresented: isPresented
        )
    }

    private func release() {
        window?.orderOut(nil)
        window?.contentView = nil
        hostingView = nil
        window = nil
        hasPinned = false
    }

    private func refreshPosition() {
        guard let window, window.isVisible, let screen = Self.currentScreen() else { return }
        let frame = Self.badgeFrame(on: screen)
        window.setFrame(frame, display: true)
        hostingView?.frame = CGRect(origin: .zero, size: frame.size)
        window.orderFrontRegardless()
    }

    private func makeWindowIfNeeded(frame: CGRect) -> NSPanel {
        if let window {
            return window
        }
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.hasShadow = false
        panel.animationBehavior = .none
        // Display only. A click here would have to mean something, and the
        // badge has nothing to open that Settings does not already hold.
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window = panel
        return panel
    }

    /// Clear of the widest wing the island can ever open to, so the two never
    /// overlap, and clamped inside the screen so a narrow display pushes the
    /// badge in rather than off.
    static func badgeFrame(on screen: ScreenGeometryProviding, size: CGSize = size) -> CGRect {
        let closed = NotchGeometry.closedRect(for: screen)
        let widestWing = (closed.width + IslandLayout.maxCompactExtraWidth) / 2
        let unclamped = closed.midX + widestWing + gap
        let originX = min(unclamped, screen.frame.maxX - size.width - gap)
        return CGRect(
            x: originX,
            y: closed.minY + (closed.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func currentScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}
