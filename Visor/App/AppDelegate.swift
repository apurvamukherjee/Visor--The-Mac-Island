import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = NotchStore()
    private var windowController: NotchWindowController?
    private var lockScreenController: LockScreenPanelManager?
    private var lockNotchController: LockScreenNotchWindowManager?
    private let settingsWindow = SettingsWindowController()
    private var services: [any NotchService] = []

    func applicationDidFinishLaunching(_: Notification) {
        Motion.startObservingAccessibility()
        guard let controller = NotchWindowController(store: store) else {
            Log.app.error("No screen available; Visor cannot display the island.")
            NSApp.terminate(nil)
            return
        }
        controller.onShowSettings = { [weak self] in
            guard let self else { return }
            settingsWindow.show(store: store)
        }
        windowController = controller
        controller.start()

        // Its own controller, not the island's: the lock overlay lives in
        // separate panels above the lock shield, while the island's panel
        // stays pinned below it. See `LockScreenWindowController`.
        let lockController = LockScreenPanelManager(store: store)
        lockScreenController = lockController
        lockController.start()

        // The padlock needs a window of its own *above* the shield: the
        // island's panel is pinned below it and is therefore invisible while
        // locked, which is why the notch did not appear.
        let lockNotch = LockScreenNotchWindowManager(store: store)
        lockNotchController = lockNotch
        lockNotch.start()

        services = [
            OnboardingService(store: store),
            BatteryService(store: store),
            NowPlayingService(store: store),
            CalendarService(store: store),
            NetworkService(store: store),
            TimerService(store: store),
            VolumeService(store: store),
            DeviceBatteryService(store: store),
            ScreenshotService(store: store),
            DownloadService(store: store),
            AirDropService(store: store),
            ScreenRecordingService(store: store),
            BluetoothService(store: store),
            FocusService(store: store),
            LockScreenService(store: store),
            GreetingService(store: store, name: "Apurva")
        ]
        services.forEach { $0.start() }
    }

    func applicationWillTerminate(_: Notification) {
        windowController?.stop()
        lockScreenController?.stop()
        lockNotchController?.stop()
        services.forEach { $0.stop() }
    }
}
