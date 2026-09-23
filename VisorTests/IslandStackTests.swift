import CoreGraphics
import Foundation
import Testing
@testable import Visor

/// The deck's arithmetic. Depth is distance from the front along the swipe
/// axis, and it is what every card's offset, inset and radius derive from —
/// so these assertions are the geometry, not a proxy for it.
@MainActor
@Suite("Island stack")
struct IslandStackTests {
    /// A catch must not cost you the player. `.screenshot` outranked
    /// `.nowPlaying` in `expandedPriority`, so the moment a screenshot
    /// landed the expanded island became the shelf — and the shelf was the
    /// home page's content, not a page, so no swipe brought the card back.
    @Test("A screenshot does not displace the music card")
    func aCatchDoesNotReplaceThePlayer() {
        let kind = resolveExpandedKind([
            .screenshot: Activity(kind: .screenshot),
            .nowPlaying: Activity(kind: .nowPlaying)
        ])
        #expect(kind == .nowPlaying, "a caught file took the expanded island from the player")
    }

    /// With nothing playing the shelf still owns the expanded island — the
    /// demotion is about losing to music, not about never winning.
    @Test("A screenshot still owns the expanded island when nothing is playing")
    func aCatchStillWinsWhenNothingPlays() {
        #expect(resolveExpandedKind([.screenshot: Activity(kind: .screenshot)]) == .screenshot)
    }

    /// The collapse must not begin before the chins have finished tucking.
    /// This shipped broken in the other direction — a flat 120ms wait against
    /// a retraction spring running at `baseResponse` — so the frame started
    /// shrinking with the chins roughly a quarter of the way home. Pinned
    /// across every preset, because the wait and the spring are derived from
    /// the same number and a future edit could move one without the other.
    @Test("The retract wait covers the retract animation, on every preset")
    func retractWaitCoversItsAnimation() {
        let previous = Motion.preset
        defer { Motion.preset = previous }
        for preset in MotionPreset.allCases {
            Motion.preset = preset
            let animation = preset.retractResponse
            #expect(animation > 0, "\(preset) retracts in no time at all")
            guard !Motion.reduceMotion else { continue }
            let wait = Double(Dwell.stackRetract.components.seconds)
                + Double(Dwell.stackRetract.components.attoseconds) / 1e18
            #expect(
                wait >= animation,
                "\(preset): collapse fires at \(wait)s into a \(animation)s retraction"
            )
        }
    }

    /// `isCardStacked` also reads the paging switch from the standard
    /// defaults, so the store cases pin it rather than inheriting whatever
    /// this machine happens to have set.
    private func withPagingEnabled(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: NewFeatures.islandPaging.key)
        defaults.set(true, forKey: NewFeatures.islandPaging.key)
        defer {
            if let previous {
                defaults.set(previous, forKey: NewFeatures.islandPaging.key)
            } else {
                defaults.removeObject(forKey: NewFeatures.islandPaging.key)
            }
        }
        body()
    }

    private func makeStore(style: PagingStyle) -> NotchStore {
        let store = NotchStore()
        store.pagingStyle = style
        return store
    }

    @Test("The front page is depth 0 and the rest recede")
    func depthsCountFromTheFront() {
        let depths = IslandStackMetrics.depths(front: .home, in: [.agenda, .home, .usage])

        #expect(depths[.home] == 0)
        #expect(depths[.usage] == 1)
        #expect(depths[.agenda] == 2)
    }

    /// Depth follows the cycle, so the page "before" the front is at the
    /// back rather than at a negative depth. A card at -1 would draw above
    /// the front one and hide it.
    @Test("Depth wraps with the stack, never going negative")
    func depthsWrap() {
        let depths = IslandStackMetrics.depths(front: .usage, in: [.agenda, .home, .usage])

        #expect(depths[.usage] == 0)
        #expect(depths[.agenda] == 1)
        #expect(depths[.home] == 2)
    }

    @Test("Two pages make one chin")
    func twoPagesOneChin() {
        let depths = IslandStackMetrics.depths(front: .home, in: [.home, .usage])

        #expect(depths[.home] == 0)
        #expect(depths[.usage] == 1)
        #expect(IslandStackMetrics.reveal(forDepths: depths.values.max() ?? 0) == 9)
    }

    @Test("Reveal is the deepest chin's offset")
    func revealFollowsDeepestChin() {
        #expect(IslandStackMetrics.reveal(forDepths: 0) == 0)
        #expect(IslandStackMetrics.reveal(forDepths: 1) == 9)
        #expect(IslandStackMetrics.reveal(forDepths: 2) == 18)
    }

    @Test("A stack of one is just the island")
    func singlePageHasNoReveal() {
        let depths = IslandStackMetrics.depths(front: .home, in: [.home])

        #expect(depths[.home] == 0)
        #expect(IslandStackMetrics.reveal(forDepths: depths.values.max() ?? 0) == 0)
    }

    @Test("Cross-fade adds no height at all")
    func crossFadeAddsNothing() {
        withPagingEnabled {
            let store = makeStore(style: .crossFade)
            store.activate(.nowPlaying)

            #expect(store.isCardStacked == false)
            #expect(store.layout.chinReveal == 0)
        }
    }

    /// The load-bearing one for §2.1: with the style unselected the resolved
    /// box must be the number today's build produces, not merely a small one.
    @Test("Selecting the stack changes the box by exactly the reveal")
    func stackGrowsBoxByReveal() {
        withPagingEnabled {
            let flat = makeStore(style: .crossFade)
            flat.activate(.nowPlaying)
            let stacked = makeStore(style: .cardStack)
            stacked.activate(.nowPlaying)

            let closed = CGSize(width: 185, height: 33)
            let grew = stacked.layout.expandedSize(closed: closed).height
                - flat.layout.expandedSize(closed: closed).height
            #expect(grew == stacked.layout.chinReveal)
            #expect(stacked.layout.chinReveal > 0)
            // The front card itself is untouched: only the deck below it is new.
            #expect(stacked.layout.expandedExtraHeight == flat.layout.expandedExtraHeight)
        }
    }

    /// The paging switch gates the style, not the other way round: the stack
    /// is how pages are shown, not a second way to reach them.
    @Test("With paging off the stack is unreachable")
    func pagingOffDisablesTheStack() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: NewFeatures.islandPaging.key)
        defaults.removeObject(forKey: NewFeatures.islandPaging.key)
        defer {
            if let previous {
                defaults.set(previous, forKey: NewFeatures.islandPaging.key)
            }
        }

        let store = makeStore(style: .cardStack)
        store.activate(.nowPlaying)

        #expect(store.isCardStacked == false)
        #expect(store.layout.chinReveal == 0)
    }

    /// The affordance has to point at the gesture that uses it: the chin you
    /// can see is at depth 1, so that is the card a swipe up must bring
    /// forward. Pinned because the sign lives in `turned(by:)` and nothing
    /// else would catch it flipping back.
    @Test("The visible chin is the one a swipe up reaches")
    func visibleChinIsOneStepUp() {
        let pages: [IslandPage] = [.agenda, .home, .usage]
        let depths = IslandStackMetrics.depths(front: .home, in: pages)
        let afterSwipeUp = IslandPage.home.cycled(by: 1, in: pages)

        #expect(depths[afterSwipeUp] == 1)
    }

    /// The inset is a fraction of the box, not a constant. A flat 11pt was
    /// 2.6% of the player's 421pt box — below the width at which an edge
    /// reads as a separate card at all.
    @Test("Chin inset scales with the box")
    func chinInsetScalesWithWidth() {
        let narrow = IslandStackMetrics.chinInset(depth: 1, width: 230)
        let wide = IslandStackMetrics.chinInset(depth: 1, width: 421)

        #expect(wide > narrow)
        #expect(wide / 421 == IslandStackMetrics.chinInsetFraction)
        // Depth 2 is twice depth 1, on any width.
        #expect(IslandStackMetrics.chinInset(depth: 2, width: 421) == 2 * wide)
    }

    /// A narrow island must not inset its chins into nothing.
    @Test("Inset has a floor")
    func chinInsetHasAFloor() {
        #expect(IslandStackMetrics.chinInset(depth: 1, width: 100) == IslandStackMetrics.minimumChinInset)
    }

    /// An unwritten key is today's behaviour, same guarantee as PagingStyle.
    @Test("Chin gradient defaults to charcoal")
    func gradientDefaults() {
        let suite = "visor.tests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return }

        #expect(ChinGradient.current(in: defaults) == .charcoal)
        defaults.set("neon", forKey: Preferences.chinGradientKey)
        #expect(ChinGradient.current(in: defaults) == .charcoal)
        defaults.set(ChinGradient.ember.rawValue, forKey: Preferences.chinGradientKey)
        #expect(ChinGradient.current(in: defaults) == .ember)
    }

    /// **One card, whatever is playing.** `covering` alone made the box the
    /// max of what was *reachable*, so it tracked the current activity —
    /// 421x193 with a track loaded and 366x190 without, a 55pt jump the
    /// moment music started. Every page is now measured against the player.
    ///
    /// The *card* is what must not move. Total island height still differs by
    /// one chin, because a quiet island genuinely has one fewer page to stack
    /// (`availablePages` drops `.agenda` when nothing owns the island), and a
    /// chin that is not there cannot protrude.
    @Test("The card is the same size whether or not music is playing")
    func cardDoesNotTrackTheActivity() {
        withPagingEnabled {
            let playing = makeStore(style: .cardStack)
            playing.activate(.nowPlaying)
            let quiet = makeStore(style: .cardStack)

            #expect(playing.layout.expandedExtraWidth == quiet.layout.expandedExtraWidth)
            #expect(playing.layout.expandedExtraHeight == quiet.layout.expandedExtraHeight)
        }
    }

    /// And the same on every page, not just the one it opens on.
    @Test("Turning a page does not resize the island")
    func pagingDoesNotResize() {
        withPagingEnabled {
            let store = makeStore(style: .cardStack)
            store.activate(.nowPlaying)
            let closed = CGSize(width: 185, height: 33)

            // `availablePages`, not `allCases`: the shelf screen only exists
            // while something is on it, and the box is built by reducing
            // `covering` over exactly the pages a swipe can reach. Iterating
            // `allCases` asks the island to hold a box for a page that is not
            // in the stack, which is the opposite of what this rule says.
            let sizes = store.availablePages.map { page -> CGSize in
                store.islandPage = page
                return store.layout.expandedSize(closed: closed)
            }

            #expect(Set(sizes.map(\.width)).count == 1)
            #expect(Set(sizes.map(\.height)).count == 1)
        }
    }

    /// The case the demotion created: a catch and a track at once. The shelf
    /// is a *page* now rather than something that takes the expanded island
    /// from the player, so it joins the stack — and "one box for every page"
    /// has to keep holding with it there. This is the configuration the rule
    /// is most likely to break in, because the shelf is the one page whose
    /// own layout was never in the box before.
    @Test("One box still covers every page once the shelf joins the stack")
    func theBoxCoversTheShelfPage() {
        withPagingEnabled {
            let store = makeStore(style: .cardStack)
            store.activate(.nowPlaying)
            store.activate(.screenshot)
            let closed = CGSize(width: 185, height: 33)

            #expect(store.availablePages.contains(.shelf), "a catch did not add its page")
            #expect(store.expandedKind == .nowPlaying, "the catch took the island from the player")

            let sizes = store.availablePages.map { page -> CGSize in
                store.islandPage = page
                return store.layout.expandedSize(closed: closed)
            }
            #expect(Set(sizes.map(\.width)).count == 1)
            #expect(Set(sizes.map(\.height)).count == 1)
        }
    }
}
