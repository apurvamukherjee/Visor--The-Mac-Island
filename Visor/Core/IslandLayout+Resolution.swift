import CoreGraphics

// One layout per thing the island can be showing, plus the single
// resolution both the panel geometry and the view read. Split from
// `IslandLayout` itself, which is now just the type and the blocks and
// columns every layout below is assembled from.
// MARK: - Resolving a layout for what is on screen

extension IslandLayout {
    /// Nothing playing: the date block beside the agenda, timer presets
    /// underneath. Both axes follow the agenda — an empty one takes the
    /// island down to a pill rather than leaving a screen of black.
    static func idle(_ content: IslandContent) -> IslandLayout {
        // The wing grows to fit its label. It used to be a flat 160 — 80pt a
        // side, 64 of it usable — while the greeting it had to carry wanted
        // 130, so the rest of the sentence was drawn underneath the camera
        // housing where nothing can be seen. Measured, not guessed.
        let compactExtra = max(160, 2 * (content.compactLeadingWidth + CompactLabel.margin))
        let rows = min(max(content.agendaRows, 0), maxEventRows)
        let body = max(Block.date, agendaHeight(rows: rows, overflow: content.hasAgendaOverflow))
        let agendaWidth = rows > 0 ? Column.agenda : Column.emptyAgenda
        let columns = Column.date + IslandSpacing.column + agendaWidth
        return IslandLayout(
            // Same floor the player carries, and for the same reason: an
            // empty agenda resolved to 275pt against a 344pt compact wing,
            // so opening the island made it *narrower* than the wing it grew
            // out of. Measured on the reference cutout.
            expandedExtraWidth: max(
                extraWidth(content: max(columns, Column.timerPresets)),
                compactExtra + idleExpandMargin
            ),
            expandedExtraHeight: content.hasTimerPresets
                ? extraHeight(body, Block.timerPresets)
                : extraHeight(body),
            compactExtraWidth: compactExtra
        )
    }

    /// How much wider than its own compact wing the idle island opens. Same
    /// job as `musicExpandMargin`, but deliberately small: this is a floor
    /// for the degenerate case, not a target. At 40 it exceeded even the
    /// three-row island's own content width, so every agenda resolved to the
    /// same size and the content-resolved sizing this file exists for
    /// stopped doing anything. At 12 only the genuinely-too-narrow layouts
    /// are caught, and an empty agenda still visibly shrinks.
    private static let idleExpandMargin: CGFloat = 12

    /// Playing *or paused*: the player owns the whole island. The calendar
    /// peek that used to sit beside it is gone — with a track loaded the
    /// island is the player, and the agenda is what the idle island shows
    /// instead. The second column only returns for the lyrics panel.
    ///
    /// The width has a floor: dropping the calendar column left the player
    /// narrower than the compact wing it grows out of, so expanding *shrank*
    /// the island sideways, which read as cramped and wrong. The card is now
    /// at least as wide as the wing plus a margin, so opening it always
    /// feels like it is opening.
    static func nowPlaying(_: IslandContent) -> IslandLayout {
        let compactExtra: CGFloat = 160
        // One column now: the player. The corner date box and the lyrics
        // panel are both gone, so nothing else claims width here — the
        // floor below is what actually sizes the card.
        let columns = Column.music
        return IslandLayout(
            expandedExtraWidth: max(extraWidth(content: columns), compactExtra + musicExpandMargin),
            expandedExtraHeight: extraHeight(Block.musicColumn),
            compactExtraWidth: compactExtra
        )
    }

    /// The paused hint: the player's expanded card over a wing just wide
    /// enough for a dot. `.nowPlaying`'s 160pt wing is sized for artwork and
    /// playback bars, and reserving that for a single dot left the island
    /// looking like it was still showing something.
    static func pausedTrack(_ content: IslandContent) -> IslandLayout {
        var layout = nowPlaying(content)
        layout.compactExtraWidth = 22
        return layout
    }

    /// How much wider than its own compact wing the player opens. Enough to
    /// read as a panel rather than a slightly larger pill, and enough that
    /// the wider gutter comes out of the island rather than out of the
    /// player: the floor is what binds here, so raising the gutter alone
    /// would only squeeze the content it was meant to inset.
    private static let musicExpandMargin: CGFloat = 76

    /// A header over a row of thumbnails. Width stays fixed: a chip is as
    /// wide as its screenshot's aspect ratio makes it, which is not known
    /// until the image is decoded, so the row centres inside a constant
    /// island instead of the island chasing it.
    static let shelf = IslandLayout(
        expandedExtraWidth: 215,
        expandedExtraHeight: extraHeight(Block.shelfHeader, Block.shelfTile),
        compactExtraWidth: 190
    )

    static let networkAlert = IslandLayout(
        expandedExtraWidth: extraWidth(content: Column.alertIcon + IslandSpacing.column + Column.alertText),
        expandedExtraHeight: extraHeight(Block.alert + IslandSpacing.block + Block.alertActions),
        compactExtraWidth: 176
    )

    static let batteryAlert = IslandLayout(
        expandedExtraWidth: extraWidth(
            content: Column.alertText + IslandSpacing.column + Column.batteryIndicator
        ),
        expandedExtraHeight: extraHeight(Block.alert),
        compactExtraWidth: 176
    )

    /// Smaller and rounder than the rest: a countdown is a single
    /// glanceable figure with two controls, not a panel, so it reads as a
    /// pill. So does the volume bar.
    static let timer = IslandLayout(
        expandedExtraWidth: 175,
        expandedExtraHeight: extraHeight(Block.countdown),
        compactExtraWidth: 150,
        expandedRadii: NotchRadii(top: 11, bottom: 34)
    )

    static let volume = IslandLayout(
        expandedExtraWidth: 175,
        expandedExtraHeight: extraHeight(Block.volumeBar),
        compactExtraWidth: 150,
        expandedRadii: NotchRadii(top: 11, bottom: 34)
    )

    /// One row per download in flight, so a single file does not get the
    /// island a batch needs — the same content-resolved sizing the agenda
    /// uses.
    static func downloads(_ content: IslandContent) -> IslandLayout {
        let rows = min(max(content.downloadRows, 1), maxDownloadRows)
        let body = CGFloat(rows) * Block.downloadRow + CGFloat(rows - 1) * IslandSpacing.row
        return IslandLayout(
            expandedExtraWidth: extraWidth(content: Column.download),
            expandedExtraHeight: extraHeight(body),
            compactExtraWidth: 150
        )
    }

    static let airDrop = IslandLayout(
        expandedExtraWidth: extraWidth(content: Column.airDrop),
        expandedExtraHeight: extraHeight(Block.airDrop),
        compactExtraWidth: 160
    )

    static let bluetoothAlert = IslandLayout(
        expandedExtraWidth: extraWidth(content: Column.alertIcon + IslandSpacing.column + Column.alertText),
        expandedExtraHeight: extraHeight(Block.alert),
        compactExtraWidth: 176
    )

    /// The padlock wing. `compactExtraWidth` is the reference's own figure
    /// for the compact style (baseWidth + 55); it never expands, so its
    /// expanded numbers only exist to satisfy the type.
    static let lock = IslandLayout(
        expandedExtraWidth: 0,
        expandedExtraHeight: 0,
        compactExtraWidth: 55
    )

    /// A pill, like the timer and the volume bar: one glyph and one clock.
    static let screenRecording = IslandLayout(
        expandedExtraWidth: extraWidth(content: Column.recording),
        expandedExtraHeight: extraHeight(Block.recording),
        compactExtraWidth: 150,
        expandedRadii: NotchRadii(top: 11, bottom: 34)
    )

    /// The welcome flow. One size for all three steps rather than resizing
    /// step to step — the copy is written to fit the same box, and a flow
    /// the user cannot yet dismiss on their own is the wrong place for the
    /// island to also be resizing under them.
    static func onboarding(_: OnboardingStep) -> IslandLayout {
        IslandLayout(
            expandedExtraWidth: extraWidth(content: Column.onboarding),
            expandedExtraHeight: extraHeight(
                Block.onboardingBody,
                Block.onboardingDots,
                Block.onboardingButtons
            ),
            compactExtraWidth: 160
        )
    }

    /// The palette, which is a *mode* rather than an activity — like
    /// onboarding, and resolved before the ladder for the same reason. Its
    /// height follows the number of matches, so typing narrows the island
    /// as it narrows the list.
    static func palette(rows: Int) -> IslandLayout {
        let clamped = min(max(rows, 1), maxPaletteRows)
        let list = CGFloat(clamped) * Block.paletteRow + CGFloat(clamped - 1) * IslandSpacing.row
        return IslandLayout(
            expandedExtraWidth: extraWidth(content: Column.palette),
            expandedExtraHeight: extraHeight(Block.paletteQuery, list),
            compactExtraWidth: 160
        )
    }

    /// The single resolution both the panel geometry and the view read, so
    /// the island can never be sized for one feature and filled with
    /// another.
    static func resolved(for kind: ActivityKind?, content: IslandContent) -> IslandLayout {
        switch kind {
        case .screenshot: shelf
        case .network: networkAlert
        case .batteryAlert: batteryAlert
        case .bluetooth: bluetoothAlert
        case .airDrop: airDrop
        case .download: downloads(content)
        case .screenRecording: screenRecording
        case .nowPlaying: nowPlaying(content)
        // The same expanded card — the dot's whole purpose is that opening
        // it finds a transport row — over a much narrower wing.
        case .pausedTrack: pausedTrack(content)
        case .timer: timer
        case .volume: volume
        // The compact-only peeks never reach here — `resolveExpandedKind`
        // does not return them — but the island behind them is the idle one.
        // `.lock` is compact-only, like the peeks below it.
        case .charging, .deviceBattery, .wave, .greeting, .focus, .lock, nil: idle(content)
        }
    }

    /// Every layout at its largest, which is what the canvas is sized from.
    static let all: [IslandLayout] = [
        idle(IslandContent(agendaRows: maxEventRows, hasAgendaOverflow: true, hasTimerPresets: true)),
        // The widest the greeting wing can get. Without this the canvas is
        // sized for a 160pt wing and a long greeting is clipped by the
        // window rather than drawn.
        idle(IslandContent(compactLeadingWidth: CompactLabel.maxWidth)),
        nowPlaying(IslandContent()),
        pausedTrack(IslandContent()),
        shelf,
        networkAlert,
        batteryAlert,
        timer,
        volume,
        onboarding(.welcome),
        downloads(IslandContent(downloadRows: maxDownloadRows)),
        airDrop,
        bluetoothAlert,
        screenRecording,
        lock,
        palette(rows: maxPaletteRows)
    ]

    static let maxExpandedExtraWidth = all.map(\.expandedExtraWidth).max() ?? 0
    static let maxExpandedExtraHeight = all.map(\.expandedExtraHeight).max() ?? 0
    static let maxCompactExtraWidth = all.map(\.compactExtraWidth).max() ?? 0

    /// What the panel canvas is sized to. Every layout fits inside it, so a
    /// layout change is a shape morph and never a window resize mid-hover.
    static func maxExpandedSize(closed: CGSize) -> CGSize {
        CGSize(width: closed.width + maxExpandedExtraWidth, height: closed.height + maxExpandedExtraHeight)
    }
}
