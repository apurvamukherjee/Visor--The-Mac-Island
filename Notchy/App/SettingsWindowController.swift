import AppKit
import SwiftUI

/// Owns the settings window directly instead of relying on SwiftUI's
/// `Settings` scene. That scene is reached through the `showSettingsWindow:`
/// action, which needs a responder chain an accessory app with no menu bar
/// doesn't reliably have — this always opens.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Notchy"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.isReleasedWhenClosed = false
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
}
