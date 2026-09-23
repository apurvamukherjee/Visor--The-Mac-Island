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

/// The deck's one load-bearing number. `chinReveal` is added to the expanded
/// height so the *window* can hold the protruding chins; the front card
/// subtracts it again (`NotchRootView.cardSize`). Get that subtraction wrong
/// and the card grows by exactly the amount the chins were meant to peek
/// out by, covering every one of them — which is what made the deck render
/// as a single slab.
@Suite("Chin reveal reserves space above the card")
struct ChinRevealTests {
    private let closed = CGSize(width: 185, height: 33)

    @Test("The reveal is the whole difference between box and card")
    func revealIsTheDifference() {
        var layout = IslandLayout.nowPlaying(.empty)
        let card = layout.expandedSize(closed: closed)
        layout.chinReveal = IslandStackMetrics.reveal(forDepths: 2)
        let box = layout.expandedSize(closed: closed)

        #expect(box.height - card.height == layout.chinReveal)
        #expect(box.width == card.width)
    }

    @Test("Two pages behind the front reveal two chins' worth")
    func revealScalesWithDepth() {
        #expect(IslandStackMetrics.reveal(forDepths: 0) == 0)
        #expect(
            IslandStackMetrics.reveal(forDepths: 2)
                == 2 * IslandStackMetrics.chinOffset
        )
        // A fourth page cannot make the island taller than the table allows.
        #expect(
            IslandStackMetrics.reveal(forDepths: 9)
                == IslandStackMetrics.reveal(forDepths: IslandStackMetrics.maxDepth)
        )
    }
}

/// Every family added later still has to leave §2.1 intact: an unwritten or
/// unrecognised key is `.charcoal`, and nothing in `allCases` may collide.
@Suite("Chin gradients")
struct ChinGradientTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "visor.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("UserDefaults suite unavailable")
        }
        return defaults
    }

    @Test("Unwritten and unrecognised keys both resolve to charcoal")
    func fallback() {
        let defaults = makeDefaults()
        #expect(ChinGradient.current(in: defaults) == .charcoal)

        defaults.set("neon", forKey: Preferences.chinGradientKey)
        #expect(ChinGradient.current(in: defaults) == .charcoal)
    }

    @Test("Every family round-trips through its stored key")
    func everyFamilyRoundTrips() {
        let defaults = makeDefaults()
        for gradient in ChinGradient.allCases {
            defaults.set(gradient.rawValue, forKey: Preferences.chinGradientKey)
            #expect(ChinGradient.current(in: defaults) == gradient)
            #expect(!gradient.title.isEmpty)
        }
    }

    /// The accent variant is the only one whose fill depends on the page, so
    /// it is the only one that can regress into "every chin the same".
    @Test("Per page gives each screen its own fill, other families do not")
    func perPageVariesByPage() {
        let pages: [IslandPage] = [.home, .agenda, .usage]
        let hues = Set(pages.map { ChinGradient.perPage.tone(for: $0).hue })
        #expect(hues.count == pages.count)

        #expect(
            ChinGradient.midnight.tone(for: .home).hue
                == ChinGradient.midnight.tone(for: .agenda).hue
        )
    }
}
