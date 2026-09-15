import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = NotchStore()
    private var windowController: NotchWindowController?
    private let settingsWindow = SettingsWindowController()
    private var services: [any NotchService] = []

    func applicationDidFinishLaunching(_: Notification) {
        guard let controller = NotchWindowController(store: store) else {
            Log.app.error("No screen available; Notchy cannot display the island.")
            NSApp.terminate(nil)
            return
        }
        controller.onShowSettings = { [weak self] in self?.settingsWindow.show() }
        windowController = controller
        controller.start()

        services = [
            BatteryService(store: store),
            NowPlayingService(store: store),
            CalendarService(store: store),
        ]
        services.forEach { $0.start() }
    }

    func applicationWillTerminate(_: Notification) {
        windowController?.stop()
        services.forEach { $0.stop() }
    }
}
