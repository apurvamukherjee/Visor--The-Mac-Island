import Foundation
import Testing
@testable import Visor

/// The usage screen is a *mode*, like onboarding and the palette — not one
/// more activity in the priority ladder. These pin that seam: what is playing
/// must not decide whether the screen is up, and the screen must not decide
/// what is playing.
@MainActor
struct UsagePanelModeTests {
    @Test
    func openingTheScreenDoesNotChangeWhichActivityOwnsTheIsland() {
        let store = NotchStore()
        store.activate(.nowPlaying)
        let before = store.expandedKind

        store.isUsagePanelOpen = true

        #expect(store.expandedKind == before)
        #expect(store.currentActivity?.kind == .nowPlaying)
    }

    /// The point of the whole feature: the music card keeps the size it was
    /// tuned to, and the usage screen is a different island rather than a
    /// column bolted onto it.
    @Test
    func theScreenTakesTheIslandFromMusicRatherThanWideningIt() {
        let store = NotchStore()
        store.activate(.nowPlaying)
        let music = store.layout

        store.isUsagePanelOpen = true

        #expect(store.layout != music)
        #expect(store.layout == IslandLayout.usage(rows: store.usageRows))
    }

    /// Onboarding and the palette are resolved before it, so neither can be
    /// displaced by a swipe landing during them.
    @Test
    func onboardingAndThePaletteBothOutrankIt() {
        let store = NotchStore()
        store.isUsagePanelOpen = true
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
