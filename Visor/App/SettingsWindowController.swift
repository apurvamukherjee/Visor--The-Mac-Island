import AppKit
import SwiftUI

/// Owns the settings window directly instead of relying on SwiftUI's
/// `Settings` scene. That scene is reached through the `showSettingsWindow:`
/// action, which needs a responder chain an accessory app with no menu bar
/// doesn't reliably have — this always opens.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show(store: NotchStore) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 500),
            // Resizable now that there is a sidebar: a split view with a
            // fixed frame cannot give the detail pane back the width the
            // source list takes.
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Visor Settings"
        window.toolbarStyle = .unified
        window.contentView = NSHostingView(rootView: SettingsView(store: store))
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
}
