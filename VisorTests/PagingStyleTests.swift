import Foundation
import Testing
@testable import Visor

/// §2.1 in the one place it is easiest to break: a stored *value* has no
/// `bool(forKey:)` false to ride, so the guarantee has to come from the
/// resolution instead. An unwritten key, and anything unrecognised, is
/// today's behaviour.
@Suite("Paging style")
struct PagingStyleTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "visor.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("UserDefaults suite unavailable")
        }
        return defaults
    }

    @Test("An unwritten key is today's behaviour")
    func unwrittenKeyIsCrossFade() {
        #expect(PagingStyle.current(in: makeDefaults()) == .crossFade)
    }

    @Test("A key written by a future version does not break this one")
    func unrecognisedValueIsCrossFade() {
        let defaults = makeDefaults()
        defaults.set("carousel", forKey: Preferences.pagingStyleKey)

        #expect(PagingStyle.current(in: defaults) == .crossFade)
    }

    @Test("The stack is selected only by writing it")
    func storedValueResolves() {
        let defaults = makeDefaults()
        defaults.set(PagingStyle.cardStack.rawValue, forKey: Preferences.pagingStyleKey)

        #expect(PagingStyle.current(in: defaults) == .cardStack)
    }

    @Test("Reveal delay defaults to 600ms and clamps to its range")
    func revealDelayDefaultsAndClamps() {
        let defaults = makeDefaults()
        #expect(Preferences.stackRevealDelayMilliseconds(in: defaults) == 600)

        defaults.set(9000.0, forKey: Preferences.stackRevealDelayKey)
        #expect(Preferences.stackRevealDelayMilliseconds(in: defaults) == 1500)

        defaults.set(-40.0, forKey: Preferences.stackRevealDelayKey)
        #expect(Preferences.stackRevealDelayMilliseconds(in: defaults) == 0)
    }

    /// 0 is a real choice — chins out from the moment the island opens —
    /// not a missing value. Same distinction `hoverIntentDelay` draws.
    @Test("Zero is a stored choice, not an absent one")
    func zeroIsAChoice() {
        let defaults = makeDefaults()
        defaults.set(0.0, forKey: Preferences.stackRevealDelayKey)

        #expect(Preferences.stackRevealDelayMilliseconds(in: defaults) == 0)
    }
}
