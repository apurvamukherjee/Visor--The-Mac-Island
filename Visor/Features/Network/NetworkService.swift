import Foundation
import Network

/// Watches reachability with `NWPathMonitor`, which is callback-driven: the
/// system wakes us on a path change and nothing runs in between.
///
/// The alert stays up for as long as the machine is actually offline rather
/// than peeking and vanishing — it is a condition, not an event — but the
/// user can dismiss it, and a later path change re-arms it.
@MainActor
final class NetworkService: NotchService {
    private let store: NotchStore
    private var monitor: NWPathMonitor?
    private var isDismissed = false
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
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
        store.networkCommands = nil
        store.isOffline = false
        store.deactivate(.network)
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
