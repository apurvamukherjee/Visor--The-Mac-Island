import Foundation

/// Peeks when a Bluetooth device connects or disconnects.
///
/// `IOBluetoothDeviceConnectedNotification` /
/// `...DisconnectedNotification` on the distributed centre: macOS posts them,
/// nothing here asks. The reference kept a 3s polling timer behind these as a
/// backstop; that is the polling loop the power rules forbid, and it existed
/// to keep a *battery* figure fresh rather than to catch connections.
///
/// Nothing in here touches `IOBluetooth`. That was tried first and it aborts
/// the process: `IOBluetoothDevice.pairedDevices()` is privacy-gated, so
/// reading it demands an `NSBluetoothAlwaysUsageDescription` and a permission
/// prompt — for a device name macOS is already handing us in the
/// notification's own payload. The notification alone is the whole feature.
@MainActor
final class BluetoothService: NotchService {
    private let store: NotchStore
    private var observers: [NSObjectProtocol] = []
    private var peekTask: Task<Void, Never>?

    private static let peekDuration: Duration = .seconds(3)

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observers = [
            (Notification.Name("IOBluetoothDeviceConnectedNotification"), BluetoothAlert.Kind.connected),
            (Notification.Name("IOBluetoothDeviceDisconnectedNotification"), BluetoothAlert.Kind.disconnected)
        ].map { name, kind in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let deviceName = Self.deviceName(from: notification)
                Task { @MainActor in self?.present(kind: kind, deviceName: deviceName) }
            }
        }
    }

    func stop() {
        peekTask?.cancel()
        peekTask = nil
        let center = DistributedNotificationCenter.default()
        observers.forEach(center.removeObserver)
        observers.removeAll()
        store.bluetoothAlert = nil
        store.deactivate(.bluetooth)
    }

    /// The payload's shape is not documented and has moved between releases,
    /// so several plausible keys are tried before falling back to a generic
    /// label. A wrong-but-present name is worse than a plain one, which is
    /// why nothing here guesses from the address.
    nonisolated static func deviceName(from notification: Notification) -> String {
        let candidates = ["Name", "name", "kBluetoothDeviceNameKey", "DeviceName"]
        if let info = notification.userInfo {
            for key in candidates {
                if let name = info[key] as? String, !name.isEmpty {
                    return name
                }
            }
        }
        if let object = notification.object as? String, !object.isEmpty {
            return object
        }
        return "Bluetooth device"
    }

    private func present(kind: BluetoothAlert.Kind, deviceName: String) {
        store.bluetoothAlert = BluetoothAlert(
            kind: kind,
            deviceName: deviceName,
            // Whatever `DeviceBatteryService` already knows from the
            // IORegistry, which needs no permission. Nothing is fetched here.
            percentage: kind == .connected ? store.deviceBattery?.percentage : nil
        )
        store.activate(.bluetooth)
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: Self.peekDuration, tolerance: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.store.bluetoothAlert = nil
            self?.store.deactivate(.bluetooth)
        }
    }
}
