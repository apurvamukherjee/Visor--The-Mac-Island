import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = NotchStore()
    private var windowController: NotchWindowController?
    private var batteryService: BatteryService?
    private var nowPlayingService: NowPlayingService?
    private var calendarService: CalendarService?
    private var accessibilityObserver: AccessibilityObserver?

    func applicationDidFinishLaunching(_: Notification) {
        guard let controller = NotchWindowController(store: store) else {
            Log.app.error("No screen available; Notchy cannot display the island.")
            NSApp.terminate(nil)
            return
        }
        windowController = controller
        controller.start()

        let accessibility = AccessibilityObserver(store: store)
        accessibility.start()
        accessibilityObserver = accessibility

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
        accessibilityObserver?.stop()
    }
}
