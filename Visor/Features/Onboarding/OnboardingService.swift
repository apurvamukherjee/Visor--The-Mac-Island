import Foundation

/// Shows the three-step welcome flow once, the first time the island ever
/// appears. Modelled on `GreetingService`: a settle delay, a UserDefaults
/// flag, and commands on the store rather than a second window controller —
/// the flow lives inside the same panel every other activity does, just at
/// the top of `NotchStore.layout`'s resolution instead of in the activity
/// priority ladder, since it must own the island outright rather than
/// compete for it.
@MainActor
final class OnboardingService: NotchService {
    private let store: NotchStore
    private var showTask: Task<Void, Never>?

    private static let settleDelay: Duration = .seconds(1)

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        store.onboardingCommands = NotchStore.OnboardingCommands(
            advance: { [weak self] in self?.advance() },
            finish: { [weak self] in self?.finish() },
            replay: { [weak self] in self?.replay() }
        )
        guard !UserDefaults.standard.bool(forKey: Preferences.hasSeenWelcomeKey) else { return }
        showTask = Task { [weak self] in
            try? await Task.sleep(for: Self.settleDelay, tolerance: .milliseconds(200))
            guard !Task.isCancelled, let self else { return }
            store.onboardingStep = .welcome
        }
    }

    func stop() {
        showTask?.cancel()
        showTask = nil
        store.onboardingCommands = nil
    }

    private func advance() {
        guard let step = store.onboardingStep else { return }
        Haptics.onboardingAdvance()
        if let next = step.next {
            store.onboardingStep = next
        } else {
            finish()
        }
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Preferences.hasSeenWelcomeKey)
        store.onboardingStep = nil
    }

    /// The Settings window's "Replay welcome tour" row. Does not touch the
    /// UserDefaults flag — replaying does not un-seen it for the next launch.
    private func replay() {
        showTask?.cancel()
        showTask = nil
        Haptics.onboardingAdvance()
        store.onboardingStep = .welcome
    }
}
