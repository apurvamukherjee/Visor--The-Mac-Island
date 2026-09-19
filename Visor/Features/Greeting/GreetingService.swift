import AppKit
import Foundation

/// A once-a-day peek: "Good morning, Apurva" the first time the island is
/// idle after login or after the Mac wakes from sleep on a new day. Modelled
/// on `BatteryService`'s charging peek — a timed `.greeting` activity, not a
/// new window-controller mechanism.
@MainActor
final class GreetingService: NotchService {
    private let store: NotchStore
    private let name: String
    private var wakeObserver: NSObjectProtocol?
    private var showTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?

    private static let settleDelay: Duration = .seconds(1)
    private static let peekDuration: TimeInterval = 3.5
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    init(store: NotchStore, name: String) {
        self.store = store
        self.name = name
    }

    func start() {
        scheduleIfDue()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleIfDue() }
        }
    }

    func stop() {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        showTask?.cancel()
        showTask = nil
        dismissTask?.cancel()
        dismissTask = nil
    }

    /// Only into a genuinely empty island — a greeting popping up over a
    /// screenshot catch or mid-playback would read as an interruption, not a
    /// welcome.
    private func scheduleIfDue() {
        guard isDueToday, store.currentActivity == nil, !store.isOnboardingActive else { return }
        showTask?.cancel()
        showTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay, tolerance: .milliseconds(200))
            guard !Task.isCancelled, let self, store.currentActivity == nil else { return }
            show()
        }
    }

    private var isDueToday: Bool {
        Self.dayFormatter.string(from: .now) != UserDefaults.standard.string(forKey: Preferences.lastGreetingDayKey)
    }

    private func show() {
        UserDefaults.standard.set(Self.dayFormatter.string(from: .now), forKey: Preferences.lastGreetingDayKey)
        store.greetingText = GreetingBuilder.greeting(for: .now, name: name)
        Haptics.greeting()
        store.activate(.greeting)
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.peekDuration), tolerance: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.store.deactivate(.greeting)
        }
    }
}
