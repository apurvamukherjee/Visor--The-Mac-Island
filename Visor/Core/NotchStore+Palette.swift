/// The palette's behaviour, split off `NotchStore` to keep that file at a
/// size somebody can still read in one go. The stored properties stay on
/// the type — `@Observable` cannot see them from an extension — so this is
/// the logic and nothing else.
@MainActor
extension NotchStore {
    func openPalette() {
        // Never over the welcome flow: that one holds the island open until
        // it is finished, and two modes fighting for the same island is how
        // the first lock-screen pass went wrong.
        guard !isPaletteOpen, !isOnboardingActive else { return }
        paletteQuery = ""
        paletteResults = availablePaletteCommands
        paletteSelection = 0
        paletteShortcuts = PaletteShortcuts.load()
        launchGroups = LaunchGroups.load()
        isPaletteOpen = true
    }

    func closePalette() {
        guard isPaletteOpen else { return }
        isPaletteOpen = false
        paletteQuery = ""
        paletteResults = []
        paletteSelection = 0
    }

    /// Which slice of the results the island is showing. Owned here rather
    /// than by the view because the key handler needs the same answer: "run
    /// row 2" has to mean the second row the user can *see*.
    var paletteWindowStart: Int {
        guard paletteResults.count > IslandLayout.maxPaletteRows else { return 0 }
        let last = IslandLayout.maxPaletteRows - 1
        return min(max(paletteSelection - last, 0), paletteResults.count - IslandLayout.maxPaletteRows)
    }

    var visiblePaletteResults: [PaletteCommand] {
        Array(paletteResults.dropFirst(paletteWindowStart).prefix(IslandLayout.maxPaletteRows))
    }

    /// True exactly when the single-key shortcuts are live. The row badges
    /// follow this, so what the keys do is always what the island shows.
    var isPaletteShortcutModeActive: Bool {
        paletteQuery.isEmpty
    }

    /// A digit runs the nth visible row; a bound letter runs its command.
    /// Nil means "this keystroke is not a shortcut", and the caller types it.
    func paletteCommand(forShortcut character: Character) -> PaletteCommandID? {
        guard isPaletteShortcutModeActive else { return nil }
        if let digit = character.wholeNumberValue, digit >= 1, digit <= IslandLayout.maxPaletteRows {
            let visible = visiblePaletteResults
            guard digit <= visible.count else { return nil }
            return visible[digit - 1].id
        }
        guard let id = paletteShortcuts.command(for: character) else { return nil }
        // Bound, but not offered right now — a shortcut must not reach a
        // command the palette has decided cannot act.
        return paletteResults.contains { $0.id == id } ? id : nil
    }

    func runPaletteCommand(_ id: PaletteCommandID) {
        closePalette()
        paletteCommands?.run(id)
    }

    func updatePaletteQuery(_ query: String) {
        paletteQuery = query
        paletteResults = PaletteMatch.filter(availablePaletteCommands, query: query)
        paletteSelection = min(paletteSelection, max(paletteResults.count - 1, 0))
    }

    /// Wraps, because a four-row list is short enough that running off
    /// either end and stopping reads as the key being broken.
    func movePaletteSelection(by delta: Int) {
        guard !paletteResults.isEmpty else { return }
        paletteSelection = (paletteSelection + delta + paletteResults.count) % paletteResults.count
    }

    /// Closes *before* running: several commands open a window or replay the
    /// welcome tour, and the palette still being up behind them is not what
    /// pressing return meant.
    func runPaletteSelection() {
        guard paletteResults.indices.contains(paletteSelection) else { return }
        let id = paletteResults[paletteSelection].id
        closePalette()
        paletteCommands?.run(id)
    }

    private var availablePaletteCommands: [PaletteCommand] {
        // Gathered once per open rather than per keystroke: the CoreAudio
        // reads are round trips, and none of this can change while a palette
        // is on screen without something else firing first.
        let shelfFile = shelf.first?.url
        let context = PaletteContext(
            hasTrack: nowPlaying != nil,
            hasVolume: volume != nil,
            hasMicrophone: SystemCommands.hasMutableMicrophone,
            hasMultipleOutputs: SystemCommands.hasMultipleOutputs,
            hasShelfFile: shelfFile != nil,
            hasShelfArchive: shelfFile.map(SystemCommands.isArchive) ?? false,
            hasShelfImage: shelfFile.map(SystemCommands.isImage) ?? false,
            forceQuitTargetName: SystemCommands.forceQuitTarget?.localizedName,
            hasStashableClipboard: SystemCommands.hasStashableClipboard(),
            configuredLaunchGroups: launchGroups.configuredIDs
        )
        // A configured slot is retitled with the user's own name and apps
        // here, and only here: `PaletteCommand.all` carries nothing but a
        // placeholder, so nobody's group name lives in a static list.
        return PaletteCommand.available(PaletteCommand.all, in: context).map { command in
            // Naming the app is the whole point of the row: "Force Quit" with
            // no object is a command you have to guess the target of, and the
            // target is whatever you were looking at a moment ago.
            if command.id == .forceQuitFrontmost, let app = context.forceQuitTargetName {
                return command.retitled("Force Quit \(app)", keywords: command.keywords + [app])
            }
            let group = launchGroups.group(for: command.id)
            guard group.isConfigured else { return command }
            return command.retitled(group.name, keywords: group.apps.map(\.displayName))
        }
    }
}
