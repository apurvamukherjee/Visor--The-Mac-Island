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
        // Compared on the wings, not the whole layout: `store.layout` reads
        // the *user's* paging style out of the real defaults, so with the
        // card stack selected it carries a `chinReveal` this assertion was
        // never about. Same leak as `NotchGeometry.closedRect` reading the
        // developer's own notch trim into the geometry suite.
        let expected = IslandLayout.resolved(for: .nowPlaying, content: store.islandContent)
        #expect(store.layout.compactExtraWidth == expected.compactExtraWidth)
        #expect(store.layout.expandedRadii == expected.expandedRadii)
    }

    /// The ends hold. Stepping past either one stays put rather than wrapping
    /// round, so a run of swipes in one direction settles instead of cycling.
    @Test
    func theStackClampsAtBothEnds() {
        let full = IslandPage.allCases
        #expect(IslandPage.agenda.stepped(by: -1, in: full) == .agenda)
        #expect(IslandPage.usage.stepped(by: 1, in: full) == .usage)
        #expect(IslandPage.home.stepped(by: -1, in: full) == .agenda)
        #expect(IslandPage.home.stepped(by: 1, in: full) == .usage)
        // And the player is reachable from either end in one step.
        #expect(IslandPage.agenda.stepped(by: 1, in: full) == .home)
        #expect(IslandPage.usage.stepped(by: -1, in: full) == .home)
    }

    /// With nothing owning the expanded island, `.home` already draws the
    /// agenda — so `.agenda` leaves the stack and a swipe up from the player
    /// is a true no-op rather than a buzz that changes nothing visible.
    @Test
    func theAgendaLeavesTheStackWhenThePlayerScreenIsAlreadyTheAgenda() {
        let store = NotchStore()
        #expect(store.expandedKind == nil)
        #expect(store.availablePages == [.home, .usage])
        #expect(IslandPage.home.stepped(by: -1, in: store.availablePages) == .home)
        // Down still works: the agent screen is genuinely different.
        #expect(IslandPage.home.stepped(by: 1, in: store.availablePages) == .usage)

        store.activate(.nowPlaying)
        #expect(store.availablePages == IslandPage.allCases)
        #expect(IslandPage.home.stepped(by: -1, in: store.availablePages) == .agenda)
    }

    /// A page that drops out from under you — the track ends while the agenda
    /// is showing — steps home rather than getting stuck on itself.
    @Test
    func aPageThatLeavesTheStackStepsHome() {
        #expect(IslandPage.agenda.stepped(by: 1, in: [.home, .usage]) == .home)
        #expect(IslandPage.agenda.stepped(by: -1, in: [.home, .usage]) == .home)
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

    /// Every screen draws inside one box, so a swipe cross-fades content
    /// inside a shape that does not move. Each page used to resolve its own
    /// size, which made the notch grow and shrink under a gesture that only
    /// ever meant "show me the next thing".
    ///
    /// Driven through `covering` rather than the store, because the store
    /// reads the paging switch out of `UserDefaults.standard` — a suite this
    /// test has no business writing to, and whose value on a developer's own
    /// machine would decide whether the test passed.
    @Test
    func everyScreenSharesOneBox() {
        let closed = CGSize(width: 185, height: 33)
        let player = IslandLayout.nowPlaying(IslandContent())
        let pages = [
            player,
            IslandLayout.idle(IslandContent(
                agendaRows: IslandLayout.maxPagedEventRows,
                hasAgendaOverflow: true
            )),
            IslandLayout.usage(rows: IslandLayout.maxUsageRows)
        ]

        let box = pages.reduce(player) { $0.covering($1) }

        for page in pages {
            #expect(box.expandedExtraWidth >= page.expandedExtraWidth)
            #expect(box.expandedExtraHeight >= page.expandedExtraHeight)
        }
        // And the player is what the box measures: it is the biggest of the
        // three on both axes, so the card the island opens on never grows a
        // band of black to make room for a neighbour.
        #expect(box.expandedSize(closed: closed) == player.expandedSize(closed: closed))
    }

    /// The trade that buys the line above, and the reason the page's row cap
    /// is a smaller number than the home screen's: the agenda fits the
    /// player's box at two rows and does not fit it at three. Either of the
    /// two cuts put back — the third row, or the timer presets — makes the
    /// island taller than the card it opens on.
    @Test
    func theAgendaPageFitsThePlayerAndAFullerOneWouldNot() {
        let player = IslandLayout.nowPlaying(IslandContent())
        let paged = IslandContent(
            agendaRows: IslandLayout.maxPagedEventRows,
            hasAgendaOverflow: true
        )
        var withHomesRows = paged
        withHomesRows.agendaRows = IslandLayout.maxEventRows
        var withPresets = paged
        withPresets.hasTimerPresets = true

        #expect(IslandLayout.idle(paged).expandedExtraHeight <= player.expandedExtraHeight)
        #expect(IslandLayout.idle(withHomesRows).expandedExtraHeight > player.expandedExtraHeight)
        #expect(IslandLayout.idle(withPresets).expandedExtraHeight > player.expandedExtraHeight)
        #expect(IslandLayout.maxPagedEventRows < IslandLayout.maxEventRows)
    }

    /// The store's own page content must agree with the cap the view draws
    /// to, or the island is sized for one agenda and filled with another.
    @Test
    func theStoreSizesTheAgendaPageToTheRowsTheViewDraws() {
        let store = NotchStore()
        store.calendarEvents = (0 ..< 5).map { index in
            CalendarEvent(
                id: "event-\(index)",
                title: "Event \(index)",
                start: .now.addingTimeInterval(600 * Double(index + 1)),
                end: .now.addingTimeInterval(600 * Double(index + 2)),
                isAllDay: false,
                color: nil
            )
        }

        let content = store.agendaPageContent
        #expect(content.agendaRows == IslandLayout.maxPagedEventRows)
        #expect(content.hasAgendaOverflow)
        #expect(content.hasTimerPresets == false)
    }

    /// `covering` grows the box and nothing else: the wings and the radii
    /// stay the activity's, because they are what the island looks like at
    /// rest and a screen you swiped to must not still be deciding them once
    /// it has closed.
    @Test
    func theBoxKeepsTheActivitysWingsAndRadii() {
        let player = IslandLayout.nowPlaying(IslandContent())
        let box = player.covering(IslandLayout.timer)

        #expect(box.compactExtraWidth == player.compactExtraWidth)
        #expect(box.expandedRadii == player.expandedRadii)
        #expect(box.compactRadii == player.compactRadii)
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
