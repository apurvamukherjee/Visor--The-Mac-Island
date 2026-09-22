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
        isPaletteOpen = true
    }

    func closePalette() {
        guard isPaletteOpen else { return }
        isPaletteOpen = false
        paletteQuery = ""
        paletteResults = []
        paletteSelection = 0
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
        PaletteCommand.available(
            PaletteCommand.all,
            hasTrack: nowPlaying != nil,
            hasVolume: volume != nil,
            // Asked once per open rather than per keystroke: it is a
            // CoreAudio round trip, and the input device cannot change while
            // a palette is on screen without something else firing first.
            hasMicrophone: SystemCommands.hasMutableMicrophone
        )
    }
}
