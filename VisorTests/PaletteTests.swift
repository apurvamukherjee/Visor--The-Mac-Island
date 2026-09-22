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
        let quiet = PaletteCommand.available(PaletteCommand.all, in: PaletteContext())
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

        // A bare machine must not be offered a file command either.
        #expect(!quiet.contains { $0.id == .compressShelfFile })
        #expect(!quiet.contains { $0.id == .switchAudioOutput })

        let everything = PaletteCommand.available(
            PaletteCommand.all,
            in: PaletteContext(
                hasTrack: true,
                hasVolume: true,
                hasMicrophone: true,
                hasMultipleOutputs: true,
                hasShelfFile: true,
                hasShelfArchive: true,
                hasShelfImage: true,
                forceQuitTargetName: "Safari",
                configuredLaunchGroups: Set(PaletteCommandID.allCases)
            )
        )
        #expect(everything.count == PaletteCommand.all.count)

        // An unconfigured launch-group slot is not "empty content", it is an
        // absent command — the same rule as every other dead control.
        #expect(!quiet.contains { $0.id == .launchGroup1 })
    }

    /// Force quit is offered only when there is something to quit. Visor
    /// itself and the Finder are both excluded upstream, and that exclusion
    /// arrives here as a nil name — so a nil name must keep the row out
    /// rather than offer a command with no object.
    @Test("Force quit is absent when there is nothing to force quit")
    func forceQuitNeedsATarget() {
        let none = PaletteCommand.available(PaletteCommand.all, in: PaletteContext())
        #expect(!none.contains { $0.id == .forceQuitFrontmost })

        let some = PaletteCommand.available(
            PaletteCommand.all,
            in: PaletteContext(forceQuitTargetName: "Safari")
        )
        #expect(some.contains { $0.id == .forceQuitFrontmost })

        // Activity Monitor is always there to open, so it never gates.
        #expect(none.contains { $0.id == .openActivityMonitor })
    }

    /// "quit" must still answer with the command whose title is that word.
    /// Both commands score the same, and the tiebreak is declaration order —
    /// which is why the force-quit row is declared after Quit Visor and not
    /// wherever it happened to read well in the source.
    @Test("Force quit does not displace Quit Visor for the word quit")
    func quitStillMeansQuitVisor() {
        #expect(titles("quit").first == "Quit Visor")
        #expect(titles("quit").contains("Force Quit Frontmost App"))
        // And the things you would actually type to reach it do reach it.
        #expect(titles("force").first == "Force Quit Frontmost App")
        #expect(titles("frozen").first == "Force Quit Frontmost App")
        #expect(titles("activity").first == "Open Activity Monitor")
    }

    /// A plain file can be compressed but not expanded or converted; only a
    /// zip can be expanded. Getting this backwards offers "Expand" on a PNG.
    @Test("Shelf commands follow what is actually on the shelf")
    func shelfGates() {
        let plain = PaletteCommand.available(
            PaletteCommand.all, in: PaletteContext(hasShelfFile: true)
        )
        #expect(plain.contains { $0.id == .compressShelfFile })
        #expect(!plain.contains { $0.id == .expandShelfFile })
        #expect(!plain.contains { $0.id == .convertShelfImage })

        let archive = PaletteCommand.available(
            PaletteCommand.all, in: PaletteContext(hasShelfFile: true, hasShelfArchive: true)
        )
        #expect(archive.contains { $0.id == .expandShelfFile })

        let image = PaletteCommand.available(
            PaletteCommand.all, in: PaletteContext(hasShelfFile: true, hasShelfImage: true)
        )
        #expect(image.contains { $0.id == .convertShelfImage })
        #expect(!image.contains { $0.id == .expandShelfFile })
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
        #expect(titles("zip").first == "Compress Shelf File")
        #expect(titles("unzip").first == "Expand Shelf File")
        #expect(titles("note").first == "New Quick Note")
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

/// The lyrics panel was written months ago and wired to nothing. These pin
/// the seam it was reconnected through, so it cannot fall off again quietly.
@Suite("Lyrics")
struct LyricsLayoutTests {
    @Test("Opening the panel widens the island")
    func openingWidensTheIsland() {
        let shut = IslandLayout.nowPlaying(IslandContent())
        let open = IslandLayout.nowPlaying(IslandContent(hasLyrics: true))

        #expect(open.expandedExtraWidth > shut.expandedExtraWidth)
        #expect(open.expandedExtraHeight == shut.expandedExtraHeight)
        #expect(open.compactExtraWidth == shut.compactExtraWidth)
    }

    /// The canvas is sized from `all`; a layout missing from it is a layout
    /// the window clips instead of drawing.
    @Test("The open panel fits the canvas")
    func openPanelFitsTheCanvas() {
        let open = IslandLayout.nowPlaying(IslandContent(hasLyrics: true))
        #expect(open.expandedExtraWidth <= IslandLayout.maxExpandedExtraWidth)
        #expect(open.expandedExtraHeight <= IslandLayout.maxExpandedExtraHeight)
    }

    @Test("LRC parsing survives the metadata tags real files carry")
    func lrcParsingSkipsTags() {
        let raw = """
        [ar:Someone]
        [ti:A Song]

        [00:12.50]First line
        [01:05.00]Second line
        """
        let lyrics = TrackLyrics.parseLRC(raw)

        #expect(lyrics.lines.count == 2)
        #expect(lyrics.lines.first?.text == "First line")
        #expect(lyrics.activeLineIndex(at: 0) == nil)
        #expect(lyrics.activeLineIndex(at: 13) == 0)
        #expect(lyrics.activeLineIndex(at: 70) == 1)
    }
}

/// The dispatch table replaced a 24-case `switch`, and with it the
/// compiler's exhaustiveness check. This is what took over that job: add a
/// command to the list and forget to wire it, and this fails rather than the
/// row silently doing nothing when someone presses return on it.
@MainActor
@Suite("Palette dispatch")
struct PaletteDispatchTests {
    @Test("Every command has an action")
    func everyCommandHasAnAction() {
        let service = PaletteService(store: NotchStore(), showSettings: {})
        let wired = Set(service.actions().keys)

        #expect(wired == Set(PaletteCommandID.allCases))
        #expect(wired.count == PaletteCommand.all.count)
    }
}
