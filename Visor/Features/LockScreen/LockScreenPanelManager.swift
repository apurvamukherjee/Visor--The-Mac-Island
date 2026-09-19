import AppKit
import SwiftUI

/// Owns the lock-screen media panel. Ported from the reference's
/// `LockScreenPanelManager`.
///
/// Three things here are load-bearing and were wrong in a first pass at this:
///
/// * The window is the **whole screen** (`screen.frame`), not a small frame
///   under the notch. The card positions itself inside that canvas, which is
///   why `LockScreenNowPlayingPanelView` works in offsets from the centre.
/// * It only appears **when a track is loaded**. No track, no panel — there
///   is no calendar or clock fallback, because the reference's panel is the
///   media panel and nothing else.
/// * The last track is **cached**, so a track that ends behind the lock
///   screen does not blank the panel mid-look. A *paused* track hides the
///   panel outright, matching the island's own pause collapse.
@MainActor
final class LockScreenPanelManager {
    private let store: NotchStore
    private var panel: NSPanel?
    private var hostingView: NSHostingView<LockScreenNowPlayingPanelView>?
    private var hasPinned = false
    private var isPresented = false
    private var hideTask: Task<Void, Never>?

    /// How long the fade-out is given before the window is ordered out. The
    /// view animates `isPresented`, so tearing the window down on the same
    /// turn means the animation never runs — which is what made locking and
    /// unlocking snap rather than fade. The reference waits the same beat.
    private static let hideDelay: Duration = .milliseconds(220)
    private var screenObserver: NSObjectProtocol?
    private var cachedInfo: NowPlayingInfo?
    private var cachedArtwork: CGImage?

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
        release()
    }

    /// One tracker over everything the panel's presence and contents depend
    /// on, re-armed on each change — `withObservationTracking` is one-shot.
    private func registerObservation() {
        withObservationTracking {
            _ = store.isLockPresenting
            _ = store.nowPlaying
            _ = store.nowPlayingArtwork
            _ = store.nowPlayingProgress
        } onChange: { [weak self] in
            Task { @MainActor in self?.handleChange() }
        }
    }

    private func handleChange() {
        registerObservation()
        sync()
    }

    private func sync() {
        // A live track refreshes the cache; losing one while unlocked clears
        // it. Losing one *while locked* keeps it, so a track that ends behind
        // the lock screen does not blank the panel mid-look.
        if let info = store.nowPlaying {
            cachedInfo = info
            cachedArtwork = store.nowPlayingArtwork
        } else if !store.isLockPresenting {
            cachedInfo = nil
            cachedArtwork = nil
        }

        guard LockScreenSettings.isMediaPanelEnabled() else {
            hide()
            return
        }
        guard store.isLockPresenting, let info = store.nowPlaying ?? cachedInfo else {
            hide()
            return
        }
        // Paused hides the panel, the same way a paused track collapses the
        // island — see `NowPlayingService.syncPresence`. Gated on the live
        // track rather than the cache so that locking while already paused
        // shows nothing, instead of showing a player for silence.
        guard info.isPlaying else {
            hide()
            return
        }
        show(info: info, artwork: store.nowPlayingArtwork ?? cachedArtwork)
    }

    private func show(info: NowPlayingInfo, artwork: CGImage?) {
        guard let screen = Self.currentScreen() else { return }
        let frame = screen.frame
        let panel = makePanelIfNeeded(frame: frame)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }

        hideTask?.cancel()
        hideTask = nil
        // Mounted hidden on the first frame, then flipped on the next turn,
        // so the view's own `isPresented` animation has two states to move
        // between. Set true immediately and it is already at its final value
        // by the time SwiftUI first draws, and the fade-in never happens.
        let wasPresented = isPresented
        isPresented = true
        let rootView = LockScreenNowPlayingPanelView(
            store: store,
            info: info,
            artwork: artwork,
            isPresented: wasPresented
        )
        if let hostingView {
            hostingView.rootView = rootView
            hostingView.frame = CGRect(origin: .zero, size: frame.size)
        } else {
            let view = NSHostingView(rootView: rootView)
            view.frame = CGRect(origin: .zero, size: frame.size)
            view.autoresizingMask = [.width, .height]
            hostingView = view
            panel.contentView = view
        }

        panel.orderFrontRegardless()
        // The transport buttons are live on the lock screen, and a panel the
        // shield never hands key status to draws its controls inactive. The
        // reference's `OverlayPanelWindow` forces the same thing.
        panel.makeKey()
        if !hasPinned {
            // After ordering front: `windowNumber` is only valid then.
            // The window level alone is not enough — the real lock shield
            // sits at CGShieldingWindowLevel() too and is ordered above us,
            // so only a SkyLight space well clear of 300 actually paints
            // over it — 400, matching the reference. The space itself is
            // created at launch by `SkyLightPin.prepare()`: one made while
            // the shield is already up does not reliably become visible.
            SkyLightPin.pin(panel, level: .aboveLockShield)
            hasPinned = true
        }
    }

    /// Fades the card out, then orders the window away once the animation
    /// has had time to run. Releasing immediately is what made unlocking
    /// look like the panel was cut off rather than dismissed.
    private func hide() {
        guard isPresented || panel != nil else { return }
        guard isPresented, let hostingView, let info = store.nowPlaying ?? cachedInfo else {
            hideTask?.cancel()
            hideTask = nil
            isPresented = false
            release()
            return
        }
        isPresented = false
        hostingView.rootView = LockScreenNowPlayingPanelView(
            store: store,
            info: info,
            artwork: store.nowPlayingArtwork ?? cachedArtwork,
            isPresented: false
        )
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hideDelay)
            guard !Task.isCancelled, let self, !isPresented else { return }
            release()
        }
    }

    private func release() {
        panel?.orderOut(nil)
        panel?.contentView = nil
        hostingView = nil
        panel = nil
        hasPinned = false
    }

    private func refreshPosition() {
        guard let panel, panel.isVisible, let screen = Self.currentScreen() else { return }
        panel.setFrame(screen.frame, display: true)
        hostingView?.frame = CGRect(origin: .zero, size: screen.frame.size)
    }

    private func makePanelIfNeeded(frame: CGRect) -> NSPanel {
        if let panel {
            return panel
        }
        let panel = LockScreenOverlayPanel(
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
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.acceptsMouseMovedEvents = true
        self.panel = panel
        return panel
    }

    private static func currentScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

/// Reports itself key and main whatever the window server thinks. While the
/// lock shield is up nothing else will hand a panel key status, and without
/// it SwiftUI draws every control in its inactive state. Copied in behaviour
/// from the reference's `OverlayPanelWindow`.
final class LockScreenOverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override var isKeyWindow: Bool {
        true
    }

    override var isMainWindow: Bool {
        true
    }
}
