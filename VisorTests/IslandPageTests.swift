import CoreGraphics
import Foundation
import Testing
@testable import Visor

/// The three screens are a *position*, not a mode: paging must not disturb
/// the activity ladder, the compact wings, or each other. These pin that.
@MainActor
struct IslandPageTests {
    @Test
    func turningPagesDoesNotChangeWhichActivityOwnsTheIsland() {
        let store = NotchStore()
        store.activate(.nowPlaying)
        let before = store.expandedKind

        store.islandPage = .usage

        #expect(store.expandedKind == before)
        #expect(store.currentActivity?.kind == .nowPlaying)
    }

    /// The bug this guards: swipe up used to dismiss the current activity, so
    /// two swipes up threw the player away with no gesture left to bring it
    /// back — the island reached the agenda and the music was simply gone.
    /// Paging must never deactivate anything.
    @Test
    func pagingAwayAndBackAlwaysFindsThePlayerAgain() {
        let store = NotchStore()
        store.activate(.nowPlaying)

        for page in [IslandPage.agenda, .home, .usage, .home] {
            store.islandPage = page
        }

        #expect(store.islandPage == .home)
        #expect(store.currentActivity?.kind == .nowPlaying)
        #expect(store.layout == IslandLayout.resolved(for: .nowPlaying, content: store.islandContent))
    }

    /// The ends hold. Stepping past either one stays put rather than wrapping
    /// round, so a run of swipes in one direction settles instead of cycling.
    @Test
    func theStackClampsAtBothEnds() {
        #expect(IslandPage.agenda.above == .agenda)
        #expect(IslandPage.usage.below == .usage)
        #expect(IslandPage.home.above == .agenda)
        #expect(IslandPage.home.below == .usage)
        // And the player is reachable from either end in one step.
        #expect(IslandPage.agenda.below == .home)
        #expect(IslandPage.usage.above == .home)
    }

    /// Paging is an expanded-only idea. The wings are what the island looks
    /// like at rest and belong to the activity — a screen you swiped to must
    /// not still be sizing them once it has closed, which is what made the
    /// island collapse to one width and then jump to another.
    @Test
    func theCompactWingsAlwaysBelongToTheActivityNotThePage() {
        let store = NotchStore()
        store.activate(.pausedTrack)
        let wing = store.layout.compactExtraWidth

        for page in IslandPage.allCases {
            store.islandPage = page
            #expect(store.layout.compactExtraWidth == wing)
        }
    }

    /// Each screen is sized for itself, so each collapses from its own
    /// footprint rather than morphing to a neighbour's first.
    @Test
    func everyScreenResolvesToItsOwnExpandedSize() {
        let store = NotchStore()
        store.activate(.nowPlaying)

        var sizes: [CGSize] = []
        for page in IslandPage.allCases {
            store.islandPage = page
            sizes.append(store.layout.expandedSize(closed: CGSize(width: 185, height: 33)))
        }
        #expect(Set(sizes.map(\.height)).count == sizes.count)
    }

    /// Onboarding and the palette are resolved before the pages, so a swipe
    /// landing during either cannot displace them.
    @Test
    func onboardingAndThePaletteBothOutrankEveryPage() {
        let store = NotchStore()
        store.islandPage = .usage
        store.isPaletteOpen = true
        #expect(store.layout == IslandLayout.palette(rows: 0))

        store.onboardingStep = .welcome
        #expect(store.layout == IslandLayout.onboarding(.welcome))
    }

    /// Codex has never run on a machine whose `threads` table is empty, so
    /// its row is absent rather than zeroed — and the island is shorter for
    /// it, the way an empty agenda shrinks the idle island.
    @Test
    func codexOnlyEarnsARowOnceItHasRun() {
        let store = NotchStore()
        store.aiUsage = AIUsageSnapshot(claudeTokens: 1000)
        #expect(store.usageRows == 1)

        store.aiUsage = AIUsageSnapshot(claudeTokens: 1000, codexTokens: 5)
        #expect(store.usageRows == 2)

        let one = IslandLayout.usage(rows: 1)
        let two = IslandLayout.usage(rows: 2)
        #expect(two.expandedExtraHeight > one.expandedExtraHeight)
        #expect(two.expandedExtraWidth == one.expandedExtraWidth)
    }

    /// Row counts arrive from a snapshot, so nonsense must clamp rather than
    /// produce a negative island.
    @Test
    func rowCountsAreClamped() {
        #expect(IslandLayout.usage(rows: 0) == IslandLayout.usage(rows: 1))
        #expect(IslandLayout.usage(rows: 99) == IslandLayout.usage(rows: IslandLayout.maxUsageRows))
    }
}

/// The window figure and its denominator. Both are read rather than assumed,
/// and an unrecognised model gets no bar at all — the same rule the daily
/// budget follows, which is that a percentage without a real denominator is
/// a fabrication.
struct AIUsageContextTests {
    @Test
    func theWindowFollowsTheModel() {
        #expect(AIUsageContext(tokens: 1, model: "claude-opus-5").window == 200_000)
        #expect(AIUsageContext(tokens: 1, model: "claude-sonnet-5[1m]").window == 1_000_000)
    }

    /// Codex's model names, a future Claude one this build has never heard
    /// of, an empty string: all of them draw the absence rather than 200k.
    @Test
    func anUnknownModelHasNoWindowAndThereforeNoBar() {
        #expect(AIUsageContext(tokens: 1, model: "gpt-5.4-codex").window == nil)
        #expect(AIUsageContext(tokens: 1, model: "").window == nil)
        #expect(AIUsageContext(tokens: 150_000, model: "gpt-5.4-codex").percentage == nil)
    }

    @Test
    func thePercentageIsAgainstTheRealWindow() {
        #expect(AIUsageContext(tokens: 100_000, model: "claude-opus-5").percentage == 50)
        #expect(AIUsageContext(tokens: 196_157, model: "claude-opus-5").percentage == 98)
    }
}

/// Context is the mirror image of the daily total: cache reads are the bulk
/// of a long session's window and are excluded from the day's work, so the
/// two figures must not be computed the same way. This is the seam that lives
/// on, pinned against the shape of a real transcript line.
struct ClaudeContextParsingTests {
    private let calendar = Calendar(identifier: .gregorian)

    /// Read verbatim off a live session before it was written down.
    private let realUsage: [String: Any] = [
        "input_tokens": 2,
        "cache_creation_input_tokens": 2906,
        "cache_read_input_tokens": 193_249,
        "output_tokens": 510
    ]

    @Test
    func cacheReadsCountTowardsTheWindowAndOutputDoesNot() {
        #expect(ClaudeUsageReader.contextTokens(inUsage: realUsage) == 196_157)
        // The same line, measured the other way: the day's work excludes the
        // cache reads and includes the output.
        #expect(ClaudeUsageReader.tokens(inUsage: realUsage) == 3418)
    }

    @Test
    func missingFieldsAreZeroRatherThanACrash() {
        #expect(ClaudeUsageReader.contextTokens(inUsage: [:]) == 0)
    }

    /// The window as it stands *now*, so the last complete line of the chunk
    /// wins — an earlier turn's smaller context must not be what is shown.
    @Test
    func theLastLineOfTheChunkIsTheCurrentWindow() {
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_789_000_000))
        let stamp = ISO8601DateFormatter.visorTest.string(from: today.addingTimeInterval(60))

        func line(cacheRead: Int, model: String) -> String {
            let entry: [String: Any] = [
                "type": "assistant",
                "timestamp": stamp,
                "message": ["model": model, "usage": ["cache_read_input_tokens": cacheRead]]
            ]
            let data = try? JSONSerialization.data(withJSONObject: entry)
            return String(data: data ?? Data(), encoding: .utf8) ?? ""
        }

        let text = [
            line(cacheRead: 10000, model: "claude-opus-5"),
            line(cacheRead: 90000, model: "claude-opus-5")
        ].joined(separator: "\n")

        let parsed = ClaudeUsageReader.parse(
            appended: Data(text.utf8), today: today, calendar: calendar
        )
        #expect(parsed.context == AIUsageContext(tokens: 90000, model: "claude-opus-5"))
    }

    /// A chunk with nothing readable in it leaves the previous context
    /// standing rather than blanking the bar.
    @Test
    func aChunkWithNoAssistantLineReportsNoContext() {
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_789_000_000))
        let parsed = ClaudeUsageReader.parse(
            appended: Data("not json\n{}\n".utf8), today: today, calendar: calendar
        )
        #expect(parsed.context == nil)
        #expect(parsed.tokens == 0)
    }
}
