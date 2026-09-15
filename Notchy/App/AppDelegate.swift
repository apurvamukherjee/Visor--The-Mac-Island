import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = NotchStore()
    private var windowController: NotchWindowController?

    func applicationDidFinishLaunching(_: Notification) {
        guard let controller = NotchWindowController(store: store) else {
            Log.app.error("No screen available; Notchy cannot display the island.")
            NSApp.terminate(nil)
            return
        }
        windowController = controller
        controller.start()
    }

    func applicationWillTerminate(_: Notification) {
        windowController?.stop()
    }
}
