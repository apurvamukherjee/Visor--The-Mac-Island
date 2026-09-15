import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = NotchStore()
    private var windowController: NotchWindowController?
    private var batteryService: BatteryService?
    private var nowPlayingService: NowPlayingService?

    func applicationDidFinishLaunching(_: Notification) {
        guard let controller = NotchWindowController(store: store) else {
            Log.app.error("No screen available; Notchy cannot display the island.")
            NSApp.terminate(nil)
            return
        }
        windowController = controller
        controller.start()

        let battery = BatteryService(store: store)
        battery.start()
        batteryService = battery

        let nowPlaying = NowPlayingService(store: store)
        nowPlaying.start()
        nowPlayingService = nowPlaying
    }

    func applicationWillTerminate(_: Notification) {
        windowController?.stop()
        batteryService?.stop()
        nowPlayingService?.stop()
    }
}
