import AppKit
import SwiftUI

/// The two panels that make up the lock-screen presentation.
///
/// They are *not* the island's own panel. That one is pinned below the lock
/// shield on purpose — an island that can paint over a locked screen is a
/// security hole, and `SkyLightPin.Level.aboveDesktop` exists to guarantee it
/// cannot. These are separate windows that exist only while locked, pinned
/// above the shield instead.
///
/// Two panels rather than one because they sit at different levels and move
/// independently: the notch mirror is welded to the cutout, the widget floats
/// below it and slides in.
@MainActor
final class LockScreenWindowController {
    private let store: NotchStore
    private var notchPanel: NSPanel?
    private var widgetPanel: NSPanel?
    private var isPresenting = false

    /// How far below the notch the widget card sits, and how big it is.
    private static let widgetSize = CGSize(width: 340, height: 150)
    private static let widgetTopGap: CGFloat = 18

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        registerLockObservation()
        syncPresentation()
    }

    func stop() {
        tearDownPanels()
    }

    private func registerLockObservation() {
        withObservationTracking {
            _ = store.isLockPresenting
        } onChange: { [weak self] in
            Task { @MainActor in self?.handleLockChange() }
        }
    }

    private func handleLockChange() {
        registerLockObservation()
        syncPresentation()
    }

    private func syncPresentation() {
        let shouldPresent = store.isLockPresenting && LockScreenSettings.isWidgetEnabled
        guard shouldPresent != isPresenting else { return }
        isPresenting = shouldPresent
        if shouldPresent {
            presentPanels()
        } else {
            tearDownPanels()
        }
    }

    private func presentPanels() {
        guard let screen = NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }) ?? NSScreen.main else {
            return
        }
        let closedRect = NotchGeometry.closedRect(for: screen)

        let notch = Self.makePanel(
            contentRect: CGRect(
                x: closedRect.midX - Self.widgetSize.width / 2,
                y: closedRect.maxY - closedRect.height - 40,
                width: Self.widgetSize.width,
                height: closedRect.height + 40
            ),
            level: .init(rawValue: Int(CGShieldingWindowLevel()) + 1)
        )
        notch.contentView = NSHostingView(
            rootView: LockScreenNotchView(store: store, closedSize: closedRect.size)
        )

        let widget = Self.makePanel(
            contentRect: CGRect(
                x: closedRect.midX - Self.widgetSize.width / 2,
                y: closedRect.minY - Self.widgetTopGap - Self.widgetSize.height,
                width: Self.widgetSize.width,
                height: Self.widgetSize.height
            ),
            level: .init(rawValue: Int(CGShieldingWindowLevel()))
        )
        widget.contentView = NSHostingView(rootView: LockScreenWidgetView(store: store))

        // Widget first, notch second: the notch mirror has to end up on top.
        for (panel, pinLevel) in [
            (widget, SkyLightPin.Level.aboveLockShield),
            (notch, SkyLightPin.Level.aboveLockShieldNotch)
        ] {
            panel.orderFrontRegardless()
            // After ordering front — `windowNumber` is only valid then.
            SkyLightPin.pin(panel, level: pinLevel)
        }
        widgetPanel = widget
        notchPanel = notch
    }

    private func tearDownPanels() {
        notchPanel?.orderOut(nil)
        widgetPanel?.orderOut(nil)
        notchPanel = nil
        widgetPanel = nil
    }

    /// Same construction as `NotchPanel`, minus the event interception: the
    /// lock overlay is display-only, and a panel that could take a click on
    /// a locked screen is not something to ship.
    private static func makePanel(contentRect: CGRect, level: NSWindow.Level) -> NSPanel {
        let panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }
}
