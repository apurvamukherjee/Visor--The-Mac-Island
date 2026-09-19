import Foundation
import Network
import SystemConfiguration

/// Watches reachability with `NWPathMonitor`, which is callback-driven: the
/// system wakes us on a path change and nothing runs in between.
///
/// The alert stays up for as long as the machine is actually offline rather
/// than peeking and vanishing — it is a condition, not an event — but the
/// user can dismiss it, and a later path change re-arms it.
///
/// It also owns the VPN indicator, for the same reason the battery service
/// owns both the charging peek and the low/full alerts: it is one condition
/// of the same subsystem. The VPN gate is `SCDynamicStore`, not the path's
/// interface list — see `VPNStatus` for why that distinction matters.
@MainActor
final class NetworkService: NotchService {
    private let store: NotchStore
    private var monitor: NWPathMonitor?
    private var isDismissed = false
    private var dynamicStore: SCDynamicStore?
    private var runLoopSource: CFRunLoopSource?
    private let queue = DispatchQueue(label: "com.apurvamukherjee.visor.network", qos: .utility)

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        guard monitor == nil else { return }
        let monitor = NWPathMonitor()
        // Only the Bool crosses the actor boundary; `NWPath` stays on the
        // monitor's own queue.
        monitor.pathUpdateHandler = { [weak self] path in
            let isOffline = path.status != .satisfied
            Task { @MainActor [weak self] in self?.apply(isOffline: isOffline) }
        }
        monitor.start(queue: queue)
        self.monitor = monitor
        store.networkCommands = NotchStore.NetworkCommands(
            dismiss: { [weak self] in self?.dismiss() }
        )
        startVPNWatch()
        refreshVPN()
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        stopVPNWatch()
        store.networkCommands = nil
        store.isOffline = false
        store.vpnName = nil
        store.deactivate(.network)
    }

    /// `SCDynamicStoreSetNotificationKeys` + a run-loop source: the system
    /// wakes us when a watched key appears or vanishes, which is exactly a
    /// VPN connecting or dropping. No polling, and no `scutil --nc list`
    /// subprocess — which is what the reference shelled out to.
    private func startVPNWatch() {
        guard dynamicStore == nil else { return }
        var context = SCDynamicStoreContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            let service = Unmanaged<NetworkService>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in service.refreshVPN() }
        }
        guard
            let dynamicStore = SCDynamicStoreCreate(
                nil,
                "com.apurvamukherjee.visor.network" as CFString,
                callback,
                &context
            ),
            SCDynamicStoreSetNotificationKeys(
                dynamicStore,
                nil,
                VPNStatus.statePatterns as CFArray
            ),
            let source = SCDynamicStoreCreateRunLoopSource(nil, dynamicStore, 0)
        else {
            Log.app.notice("VPN watch unavailable; the indicator stays off")
            return
        }
        // `.common`, not `.default`: a run-loop source on the default mode
        // stops being serviced while a menu or a resize is tracking, which
        // is the same bug the charging peek had.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.dynamicStore = dynamicStore
        runLoopSource = source
    }

    private func stopVPNWatch() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        dynamicStore = nil
    }

    private func refreshVPN() {
        let name = VPNStatus.current()
        guard name != store.vpnName else { return }
        store.vpnName = name
    }

    private func apply(isOffline: Bool) {
        guard isOffline != store.isOffline else { return }
        store.isOffline = isOffline
        // A path change is new information, so an earlier dismissal no longer
        // applies — otherwise dismissing once would silence every future drop.
        isDismissed = false
        if isOffline {
            store.activate(.network)
        } else {
            store.deactivate(.network)
        }
    }

    /// The alert's OK button. Clears the island without pretending the
    /// machine is back online.
    private func dismiss() {
        guard !isDismissed else { return }
        isDismissed = true
        store.deactivate(.network)
    }
}
