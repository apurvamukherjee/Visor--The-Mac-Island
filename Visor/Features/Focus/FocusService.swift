import Foundation

/// Peeks when Focus turns on or off.
///
/// On/off only, and no mode name. Naming the active mode — "Work", "Sleep",
/// a custom one with its own icon and colour — means Full Disk Access plus
/// parsing the undocumented JSON under `~/Library/DoNotDisturb/DB/`, which
/// is the same wall that killed notification mirroring, and which the
/// reference's own code notes became unreliable on macOS 26. The
/// `_NSDoNotDisturb*` distributed notifications need no permission and are
/// right about the one thing they report.
@MainActor
final class FocusService: NotchService {
    private let store: NotchStore
    private var observers: [NSObjectProtocol] = []
    private var peekTask: Task<Void, Never>?

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observers = [
            center.addObserver(
                forName: Notification.Name("_NSDoNotDisturbEnabledNotification"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.apply(isOn: true) }
            },
            center.addObserver(
                forName: Notification.Name("_NSDoNotDisturbDisabledNotification"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.apply(isOn: false) }
            }
        ]
    }

    func stop() {
        peekTask?.cancel()
        peekTask = nil
        let center = DistributedNotificationCenter.default()
        observers.forEach(center.removeObserver)
        observers.removeAll()
        store.isFocusOn = false
        store.focusPeek = nil
        store.deactivate(.focus)
    }

    private func apply(isOn: Bool) {
        guard isOn != store.isFocusOn else { return }
        store.isFocusOn = isOn
        store.focusPeek = isOn
        store.activate(.focus)
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: Dwell.focus, tolerance: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.store.focusPeek = nil
            self?.store.deactivate(.focus)
        }
    }
}
