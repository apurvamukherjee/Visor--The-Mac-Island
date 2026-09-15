import AppKit

/// Mirrors the system's Reduce Transparency setting into the store so views
/// can read it as observable state. Reduce *Motion* needs no equivalent —
/// `Motion.resolved(_:)` reads it at call time, when an animation is built.
@MainActor
final class AccessibilityObserver {
    private let store: NotchStore
    private var observer: NSObjectProtocol?

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        sync()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
    }

    func stop() {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }

    private func sync() {
        store.setReduceTransparency(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    }
}
