import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = NotchStore()
    private var windowController: NotchWindowController?
    private let settingsWindow = SettingsWindowController()
    private var batteryService: BatteryService?
    private var nowPlayingService: NowPlayingService?
    private var calendarService: CalendarService?

    func applicationDidFinishLaunching(_: Notification) {
        guard let controller = NotchWindowController(store: store) else {
            Log.app.error("No screen available; Notchy cannot display the island.")
            NSApp.terminate(nil)
            return
        }
        controller.onShowSettings = { [weak self] in self?.settingsWindow.show() }
        windowController = controller
        controller.start()

        let battery = BatteryService(store: store)
        battery.start()
        batteryService = battery

        let nowPlaying = NowPlayingService(store: store)
        nowPlaying.start()
        nowPlayingService = nowPlaying

        let calendar = CalendarService(store: store)
        calendar.start()
        calendarService = calendar
    }

    func applicationWillTerminate(_: Notification) {
        windowController?.stop()
        batteryService?.stop()
        nowPlayingService?.stop()
        calendarService?.stop()
    }
}
