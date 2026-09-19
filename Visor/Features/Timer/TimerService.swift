import Foundation

/// Owns the countdown's lifetime. One `Task.sleep` to the deadline is the
/// only clock: the displayed figure is derived from `deadline`, and the
/// views that show it only exist while the island is on screen, so nothing
/// ticks behind a closed island.
@MainActor
final class TimerService: NotchService {
    private let store: NotchStore
    private var fireTask: Task<Void, Never>?
    private var clearTask: Task<Void, Never>?

    /// How long "Time's up" stays before the island lets go of it.
    private static let finishedLinger: TimeInterval = 8

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        store.timerCommands = NotchStore.TimerCommands(
            start: { [weak self] duration in self?.startTimer(duration) },
            togglePause: { [weak self] in self?.togglePause() },
            cancel: { [weak self] in self?.cancelTimer() }
        )
    }

    func stop() {
        fireTask?.cancel()
        fireTask = nil
        clearTask?.cancel()
        clearTask = nil
        store.timerCommands = nil
        store.timer = nil
        store.deactivate(.timer)
    }

    private func startTimer(_ duration: TimeInterval) {
        clearTask?.cancel()
        clearTask = nil
        store.timer = IslandTimer(duration: duration, deadline: .now.addingTimeInterval(duration))
        store.activate(.timer)
        scheduleFire()
    }

    private func togglePause() {
        guard var timer = store.timer, !timer.isFinished(at: .now) else { return }
        if let remaining = timer.pausedRemaining {
            timer.deadline = .now.addingTimeInterval(remaining)
            timer.pausedRemaining = nil
        } else {
            timer.pausedRemaining = timer.remaining(at: .now)
        }
        store.timer = timer
        scheduleFire()
    }

    private func cancelTimer() {
        fireTask?.cancel()
        fireTask = nil
        clearTask?.cancel()
        clearTask = nil
        store.timer = nil
        store.deactivate(.timer)
    }

    private func scheduleFire() {
        fireTask?.cancel()
        fireTask = nil
        guard let timer = store.timer, !timer.isPaused else { return }
        let delay = timer.remaining(at: .now)
        fireTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            fireTask = nil
            complete()
        }
    }

    /// The timer stays on screen reading "Time's up" rather than vanishing
    /// at the moment it matters — the island is the only notification this
    /// feature has.
    private func complete() {
        Haptics.timerFinished()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.finishedLinger), tolerance: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            clearTask = nil
            store.timer = nil
            store.deactivate(.timer)
        }
    }
}
