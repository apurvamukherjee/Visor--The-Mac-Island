import AppKit
import Combine

/// Tracks whether the screen is locked.
///
/// Two signals, because neither alone is enough. `com.apple.screenIsLocked` /
/// `...IsUnlocked` on the distributed centre are the authoritative edges but
/// arrive only once the shield is already up. `NSWorkspace`'s
/// session-resign/become pair fires earlier — on the fast-user-switch edge —
/// which is what lets the overlay be on screen before the shield rather than
/// appearing a beat after it.
///
/// Combine inside, a plain store write out: the two sources merge into one
/// stream here, and the only thing that leaves is `isLocked` /
/// `isLockTransitioning` on `NotchStore`. Views never see a publisher.
@MainActor
final class LockScreenService: NotchService {
    private let store: NotchStore
    private let lockSubject = PassthroughSubject<Bool, Never>()
    private var cancellables: Set<AnyCancellable> = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var settleTask: Task<Void, Never>?

    /// How long the overlay outlives an unlock. The lock animation has to be
    /// allowed to play backwards; yanking the panel on the unlock edge cut
    /// it off mid-morph. Same figure the reference settled on.
    private static let unlockCollapseDelay: Duration = .milliseconds(820)

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        guard cancellables.isEmpty else { return }
        // Dropping repeats here rather than at each call site: the session
        // notifications and the distributed ones overlap on a real lock, and
        // both would otherwise restart the settle task.
        lockSubject
            .removeDuplicates()
            .sink { [weak self] isLocked in self?.apply(isLocked: isLocked) }
            .store(in: &cancellables)

        let distributed = DistributedNotificationCenter.default()
        distributedObservers = [
            (Notification.Name("com.apple.screenIsLocked"), true),
            (Notification.Name("com.apple.screenIsUnlocked"), false)
        ].map { name, locked in
            distributed.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.lockSubject.send(locked) }
            }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspace.addObserver(
                forName: NSWorkspace.sessionDidResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.handleSessionResigned() }
            },
            workspace.addObserver(
                forName: NSWorkspace.sessionDidBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.lockSubject.send(false) }
            }
        ]
    }

    func stop() {
        settleTask?.cancel()
        settleTask = nil
        cancellables.removeAll()
        let distributed = DistributedNotificationCenter.default()
        distributedObservers.forEach(distributed.removeObserver)
        distributedObservers.removeAll()
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach(workspace.removeObserver)
        workspaceObservers.removeAll()
        store.isLocked = false
        store.isPreparingLock = false
        store.isLockTransitioning = false
        store.deactivate(.lock)
    }

    /// The session going inactive means a lock is *probably* coming — a fast
    /// user switch does it too. The wing starts transitioning so it is
    /// already there when the shield lands; if no lock follows, the next
    /// session-active notification clears it.
    private func handleSessionResigned() {
        guard !store.isLocked else { return }
        store.isPreparingLock = true
        store.activate(.lock)
    }

    private func apply(isLocked: Bool) {
        settleTask?.cancel()
        settleTask = nil
        store.isLocked = isLocked
        // Resolved either way, so the "a lock is probably coming" guess is
        // over. Clearing it here is what takes the media panel off the
        // screen on the unlock edge rather than a beat later.
        store.isPreparingLock = false
        // The padlock is a compact activity in the island itself, the way the
        // reference has it — `LockScreenNotchContent` with its own priority.
        store.activate(.lock)
        if isLocked {
            store.isLockTransitioning = true
            return
        }
        // Unlocking: the open padlock is held in the island — over the
        // desktop, not the lock screen — for the reference's own
        // `unlockCollapseDelay`, so the latch reads as opening rather than
        // simply vanishing.
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.unlockCollapseDelay, tolerance: .milliseconds(80))
            guard !Task.isCancelled else { return }
            self?.store.isLockTransitioning = false
            self?.store.deactivate(.lock)
        }
    }
}
