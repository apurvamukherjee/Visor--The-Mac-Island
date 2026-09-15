import Foundation
import IOKit.ps

@MainActor
final class BatteryService: NotchService {
    private let store: NotchStore
    private var runLoopSource: CFRunLoopSource?
    private var wasCharging: Bool?
    private var peekTask: Task<Void, Never>?

    private static let peekDuration: TimeInterval = 2.5

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        refresh()
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in service.refresh() }
        }, context)?.takeRetainedValue() else {
            Log.battery.error("Failed to create IOKit power-source notification source.")
            return
        }
        // .commonModes, not .defaultMode: the app's run loop can sit in a
        // different mode (e.g. during tracking) while otherwise idle, and a
        // source scoped to .defaultMode alone would then wait for the next
        // user-driven event to pump the loop back before it fires — visible
        // as the charging peek only appearing once you hover the notch.
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        runLoopSource = source
    }

    func stop() {
        peekTask?.cancel()
        peekTask = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
    }

    private func refresh() {
        guard
            let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
            let source = sources.first,
            let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
            let info = BatteryInfoParser.parse(description)
        else {
            Log.battery.error("Could not read power source info.")
            return
        }
        store.battery = info
        if let wasCharging, info.isCharging, !wasCharging {
            schedulePeek()
        }
        wasCharging = info.isCharging
    }

    private func schedulePeek() {
        store.activate(.charging)
        peekTask?.cancel()
        peekTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.peekDuration), tolerance: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.store.deactivate(.charging)
        }
    }
}
