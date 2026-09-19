import Foundation
import IOKit

/// Charge for a Bluetooth accessory, read straight from the IORegistry —
/// no permission, no Bluetooth framework, no daemon.
///
/// It peeks on **connection only**. macOS posts nothing when an accessory's
/// charge moves, so a live reading would mean a poll, and the power rules
/// rule that out. Connecting is the moment the number is worth seeing
/// anyway, which is the same bargain `BatteryService` makes with the
/// charging peek.
///
/// Inert on a machine with nothing connected: the registry keys simply are
/// not there, `DeviceBatteryReader` returns nil, and no activity is raised.
@MainActor
final class DeviceBatteryService: NotchService {
    private let store: NotchStore
    private var notifyPort: IONotificationPortRef?
    private var iterator: io_iterator_t = 0
    private var peekTask: Task<Void, Never>?

    private static let peekDuration: TimeInterval = 2.5
    private static let serviceClass = "AppleDeviceManagementHIDEventService"

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        guard notifyPort == nil, let port = IONotificationPortCreate(kIOMainPortDefault) else {
            Log.deviceBattery.error("Could not create an IOKit notification port.")
            return
        }
        notifyPort = port
        // .commonModes for the same reason `BatteryService` uses it: a
        // source scoped to the default mode alone waits for the next user
        // event whenever the run loop is sitting in tracking mode.
        if let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = IOServiceAddMatchingNotification(
            port,
            kIOFirstMatchNotification,
            IOServiceMatching(Self.serviceClass),
            { context, iterator in
                guard let context else { return }
                let service = Unmanaged<DeviceBatteryService>.fromOpaque(context).takeUnretainedValue()
                // Drained here, on the callback's own thread: the iterator
                // must be emptied or the notification never fires again,
                // and only the parsed value crosses to the main actor.
                let found = DeviceBatteryService.drain(iterator)
                Task { @MainActor in service.announce(found) }
            },
            context,
            &iterator
        )
        guard status == KERN_SUCCESS else {
            Log.deviceBattery.error("Could not observe accessory connections: \(status)")
            return
        }
        // Arms the notification, and hands back whatever is already
        // connected — which is not a connection event, so it peeks for
        // nothing. Same suppression as the charging peek's first read.
        _ = Self.drain(iterator)
    }

    func stop() {
        peekTask?.cancel()
        peekTask = nil
        if iterator != 0 {
            IOObjectRelease(iterator)
            iterator = 0
        }
        if let notifyPort {
            if let source = IONotificationPortGetRunLoopSource(notifyPort)?.takeUnretainedValue() {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
            IONotificationPortDestroy(notifyPort)
        }
        notifyPort = nil
        store.deviceBattery = nil
        store.deactivate(.deviceBattery)
    }

    private func announce(_ batteries: [DeviceBattery]) {
        // Two accessories can wake together; the emptier one is the one
        // worth saying out loud.
        guard let battery = batteries.min(by: { $0.percentage < $1.percentage }) else { return }
        store.deviceBattery = battery
        store.activate(.deviceBattery)
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.peekDuration), tolerance: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            peekTask = nil
            store.deactivate(.deviceBattery)
        }
    }

    /// Empties the iterator, reading each entry as it goes. Entries with no
    /// battery keys — the built-in keyboard and trackpad both match this
    /// service class — read as nil and drop out here.
    private nonisolated static func drain(_ iterator: io_iterator_t) -> [DeviceBattery] {
        var found: [DeviceBattery] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            if let battery = read(entry) {
                found.append(battery)
            }
            IOObjectRelease(entry)
        }
        return found
    }

    private nonisolated static func read(_ entry: io_registry_entry_t) -> DeviceBattery? {
        guard let percentage = DeviceBatteryReader.percentage(
            combined: number(entry, "BatteryPercentCombined"),
            left: number(entry, "BatteryPercentLeft"),
            right: number(entry, "BatteryPercentRight"),
            single: number(entry, "BatteryPercent")
        ) else { return nil }
        let product = string(entry, "Product") ?? string(entry, "DeviceName") ?? "Accessory"
        return DeviceBattery(product: product, percentage: percentage)
    }

    private nonisolated static func number(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        property(entry, key) as? Int
    }

    private nonisolated static func string(_ entry: io_registry_entry_t, _ key: String) -> String? {
        property(entry, key) as? String
    }

    private nonisolated static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}
