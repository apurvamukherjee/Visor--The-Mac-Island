import SwiftUI

@main
struct VisorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        // SettingsWindowController owns the real one; this scene only exists
        // because an App needs a body. Pointing it at SettingsView too would
        // open a second, separate window.
        Settings {
            EmptyView()
        }
    }
}
