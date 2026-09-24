import AppKit
import SwiftUI

/// Draws the island's padlock wing *above* the lock shield.
///
/// This exists because the island's own panel deliberately cannot: it is
/// pinned below the shield (`SkyLightPin.Level.aboveDesktop`, 100) so it can
/// never paint over a locked screen, which means it is also invisible while
/// locked. That is correct for the island and wrong for the padlock, so the
/// padlock gets its own window at `CGShieldingWindowLevel() + 1`, exactly as
/// the reference's `LockScreenLiveActivityWindowManager` does.
///
/// It is display-only: no mouse events, no hit testing. A panel that could
/// take a click on a locked screen is not something to ship.
@MainActor
final class LockScreenNotchWindowManager {
    private let store: NotchStore
    private var window: NSPanel?
    private var hostingView: NSHostingView<LockScreenNotchOverlayView>?
    private var hasPinned = false
    private var isPresented = false
    private var hideTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?

    /// Long enough for the wing to collapse before the window disappears.
    /// Without it the padlock vanishes mid-morph instead of closing.
    private static let hideDelay: Duration = .milliseconds(260)

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
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
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
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        screenObserver = nil
        spaceObserver = nil
        hideTask?.cancel()
        hideTask = nil
        isPresented = false
        release()
    }

    /// Re-armed on each change: `withObservationTracking` is one-shot.
    private func registerObservation() {
        withObservationTracking {
            _ = store.isLockPresenting
            _ = store.isLocked
            _ = store.closedSize
        } onChange: { [weak self] in
            Task { @MainActor in self?.handleChange() }
        }
    }

    private func handleChange() {
        registerObservation()
        sync()
    }

    private func sync() {
        guard LockScreenSettings.isLiveActivityEnabled(), store.isLockPresenting else {
            hide()
            return
        }
        present()
    }

    /// Collapses the wing, then orders the window out once the shape has
    /// had time to close — the same reason the media panel waits.
    private func hide() {
        guard isPresented else {
            release()
            return
        }
        isPresented = false
        hostingView?.rootView = LockScreenNotchOverlayView(
            isLocked: store.isLocked,
            closedSize: store.closedSize,
            style: LockScreenSettings.style(),
            isPresented: false
        )
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hideDelay)
            guard !Task.isCancelled, let self, !isPresented else { return }
            release()
        }
    }

    private func present() {
        guard let screen = Self.currentScreen() else { return }
        let frame = Self.overlayFrame(on: screen)
        let window = makeWindowIfNeeded(frame: frame)
        if window.frame != frame {
            window.setFrame(frame, display: true)
        }

        hideTask?.cancel()
        hideTask = nil
        let wasPresented = isPresented
        isPresented = true
        let rootView = LockScreenNotchOverlayView(
            isLocked: store.isLocked,
            closedSize: store.closedSize,
            style: LockScreenSettings.style(),
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
            window.contentView = view
        }

        window.orderFrontRegardless()
        if !hasPinned {
            // After ordering front: `windowNumber` is only valid then.
            // The window level alone is not enough — the real lock shield
            // sits at CGShieldingWindowLevel() too and is ordered above us,
            // so only a SkyLight space well clear of 300 actually paints
            // over it — 401, matching the reference. The space itself is
            // created at launch by `SkyLightPin.prepare()`: one made while
            // the shield is already up does not reliably become visible.
            SkyLightPin.pin(window, level: .aboveLockShieldNotch)
            hasPinned = true
        }
        guard !wasPresented else { return }
        // Next turn, so the wing has a closed frame to grow out of.
        Task { @MainActor [weak self] in
            guard let self, isPresented, let hostingView else { return }
            hostingView.rootView = LockScreenNotchOverlayView(
                isLocked: store.isLocked,
                closedSize: store.closedSize,
                style: LockScreenSettings.style(),
                isPresented: true
            )
        }
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
        let frame = Self.overlayFrame(on: screen)
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
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window = panel
        return panel
    }

    /// Anchored to the top of the screen, wide enough for the widest wing.
    /// The view centres the island inside it, the way the main panel's canvas
    /// does.
    private static func overlayFrame(on screen: NSScreen) -> CGRect {
        let closed = NotchGeometry.closedRect(for: screen)
        let width = closed.width + IslandLayout.maxCompactExtraWidth
        return CGRect(
            x: closed.midX - width / 2,
            y: closed.minY,
            width: width,
            height: closed.height
        )
    }

    private static func currentScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil })
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }
}

/// The padlock island as it appears over the lock shield: the same
/// `NotchShape` the island itself draws, wearing `LockScreenNotchView`.
struct LockScreenNotchOverlayView: View {
    let isLocked: Bool
    let closedSize: CGSize
    let style: LockScreenStyle
    /// False for one frame on the way in and for the fade on the way out, so
    /// the wing grows out of the closed notch and collapses back into it
    /// rather than appearing and vanishing at full width.
    var isPresented = true

    /// The reference's own compact width for this content (`baseWidth + 55`),
    /// and the wider one its `.enlarged` style asks for.
    private var extraWidth: CGFloat {
        style == .enlarged ? 150 : 55
    }

    private var size: CGSize {
        CGSize(
            width: closedSize.width + (isPresented ? extraWidth : 0),
            height: closedSize.height
        )
    }

    var body: some View {
        NotchShape(isPresented ? .compact : .closed)
            .fill(.black)
            .frame(width: size.width, height: size.height)
            .overlay {
                if isPresented {
                    LockScreenNotchView(isLocked: isLocked, style: style)
                        .frame(width: size.width, height: size.height)
                        .transition(.island)
                }
            }
            // The latch dissolves — fades, blurs and eases back — *before*
            // the wing collapses under it, so unlocking hands over to the
            // island's own music wing rather than cutting to it. The shape
            // still leads and the content still follows; this is the content
            // half of that, running on the way out.
            .modifier(Materialize(progress: isPresented ? 0 : 1))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(Motion.resolved(Motion.morph), value: isLocked)
            .animation(Motion.resolved(isPresented ? Motion.open : Motion.settle), value: isPresented)
    }
}
