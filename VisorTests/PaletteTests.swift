import Testing
@testable import Visor

/// The matching is what a palette is judged on: typing four letters has to
/// put the obvious command first, not merely somewhere in the list.
@Suite("Command palette")
struct PaletteTests {
    private func titles(_ query: String, in commands: [PaletteCommand] = PaletteCommand.all) -> [String] {
        PaletteMatch.filter(commands, query: query).map(\.title)
    }

    @Test("An empty query leaves the list alone")
    func emptyQueryKeepsOrder() {
        #expect(titles("") == PaletteCommand.all.map(\.title))
        #expect(titles("   ") == PaletteCommand.all.map(\.title))
    }

    /// Both titles contain n-e-x-t and p-r-e-v in order somewhere; the point
    /// is which one wins.
    @Test("The obvious command ranks first")
    func obviousCommandRanksFirst() {
        #expect(titles("next").first == "Next Track")
        #expect(titles("prev").first == "Previous Track")
        #expect(titles("quit").first == "Quit Visor")
        #expect(titles("settings").first == "Open Settings")
    }

    @Test("Keywords match what the title does not say")
    func keywordsMatch() {
        #expect(titles("skip").first == "Next Track")
        #expect(titles("prefs").first == "Open Settings")
        #expect(titles("exit").first == "Quit Visor")
    }

    /// Word starts score, which is what makes initials work.
    @Test("Initials find their command")
    func initialsMatch() {
        #expect(titles("os").first == "Open Settings")
        #expect(titles("qv").first == "Quit Visor")
    }

    @Test("A query that matches nothing returns nothing")
    func noMatches() {
        #expect(titles("zzzz").isEmpty)
    }

    @Test("Letters must appear in order")
    func subsequenceIsOrdered() {
        #expect(PaletteMatch.score("Next Track", query: "txen") == nil)
        #expect(PaletteMatch.score("Next Track", query: "next") != nil)
    }

    /// A palette listing "Next Track" with nothing playing offers a row that
    /// does nothing, which this codebase already decided is worse than an
    /// absent one.
    @Test("Commands that cannot act are not offered")
    func availabilityGates() {
        let quiet = PaletteCommand.available(
            PaletteCommand.all, hasTrack: false, hasVolume: false, hasMicrophone: false
        )
        #expect(!quiet.contains { $0.id == .playPause })
        #expect(!quiet.contains { $0.id == .nextTrack })
        #expect(!quiet.contains { $0.id == .toggleMute })
        #expect(!quiet.contains { $0.id == .copyTrack })
        #expect(!quiet.contains { $0.id == .toggleMicrophone })
        // The ones that work on a machine playing nothing, with no mutable
        // input device, still have to be there — that is the common case.
        #expect(quiet.contains { $0.id == .openSettings })
        #expect(quiet.contains { $0.id == .quit })
        #expect(quiet.contains { $0.id == .keepAwake })
        #expect(quiet.contains { $0.id == .lockScreen })
        #expect(quiet.contains { $0.id == .toggleDarkMode })
        #expect(quiet.contains { $0.id == .timerTwentyFive })

        let everything = PaletteCommand.available(
            PaletteCommand.all, hasTrack: true, hasVolume: true, hasMicrophone: true
        )
        #expect(everything.count == PaletteCommand.all.count)
    }

    /// Enough commands that the four-row island has to window the list, which
    /// is the case `ExpandedPaletteView.windowStart` exists for.
    @Test("The list outgrows the island's rows")
    func listOutgrowsTheIsland() {
        #expect(PaletteCommand.all.count > IslandLayout.maxPaletteRows)
    }

    @Test("Every command carries a glyph and searchable words")
    func commandsAreComplete() {
        for command in PaletteCommand.all {
            #expect(!command.title.isEmpty)
            #expect(!command.symbol.isEmpty)
        }
    }

    /// Typing the obvious word for each new command has to find it.
    @Test("The new commands are reachable by their obvious word")
    func newCommandsAreFindable() {
        #expect(titles("caffeine").first == "Keep Awake")
        #expect(titles("pomodoro").first == "Start 25-Minute Timer")
        #expect(titles("dark").first == "Toggle Dark Mode")
        #expect(titles("lock").first == "Lock Screen")
        #expect(titles("mic").first == "Mute or Unmute Microphone")
        #expect(titles("downloads").first == "Open Downloads")
        #expect(titles("screenshot").first == "Take Screenshot")
    }

    @Test("Every command has a distinct identifier")
    func identifiersAreUnique() {
        let ids = PaletteCommand.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Set(ids) == Set(PaletteCommandID.allCases))
    }
}

/// The island is sized from the number of matches, so the list and the
/// shape have to agree about how many rows there are.
@Suite("Palette layout")
struct PaletteLayoutTests {
    @Test("Height follows the match count, up to the cap")
    func heightFollowsRows() {
        let one = IslandLayout.palette(rows: 1).expandedExtraHeight
        let two = IslandLayout.palette(rows: 2).expandedExtraHeight
        let capped = IslandLayout.palette(rows: IslandLayout.maxPaletteRows).expandedExtraHeight

        #expect(two > one)
        #expect(IslandLayout.palette(rows: 99).expandedExtraHeight == capped)
    }

    /// An empty result list still draws "No commands match", so the island
    /// must never resolve to a zero-row shape.
    @Test("No matches still leaves a row of island")
    func emptyStillHasHeight() {
        #expect(IslandLayout.palette(rows: 0).expandedExtraHeight == IslandLayout.palette(rows: 1).expandedExtraHeight)
    }

    /// The canvas is sized from `all`; a layout missing from it would be a
    /// layout the window cannot contain.
    @Test("The palette fits the canvas every other layout is sized against")
    func paletteFitsTheCanvas() {
        let palette = IslandLayout.palette(rows: IslandLayout.maxPaletteRows)
        #expect(palette.expandedExtraWidth <= IslandLayout.maxExpandedExtraWidth)
        #expect(palette.expandedExtraHeight <= IslandLayout.maxExpandedExtraHeight)
    }
}
