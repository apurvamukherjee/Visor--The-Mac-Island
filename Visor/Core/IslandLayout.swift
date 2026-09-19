import CoreGraphics

/// The two radii one island state draws with. `top` is the outward-flaring
/// shoulder (see `NotchShape`), `bottom` the ordinary rounded corner.
struct NotchRadii: Equatable, Sendable {
    var top: CGFloat
    var bottom: CGFloat

    /// Zero shoulder, and only here: material outside the physical cutout
    /// would make the closed island visible against the hardware notch.
    static let closed = NotchRadii(top: 0, bottom: 12)
    static let compact = NotchRadii(top: 8, bottom: 14)
    static let expanded = NotchRadii(top: 11, bottom: 28)
}

/// What the feature that owns the island actually has to show right now.
///
/// Layouts used to be constants sized for each feature's *fullest* state,
/// which meant a quiet day still got the island a packed one needs: the
/// agenda reserved three event rows whether or not three existed, so the
/// expanded idle island was mostly empty black. Sizes are resolved from
/// this instead, so the island is only ever as big as its contents.
struct IslandContent: Equatable, Sendable {
    /// Agenda rows that will really be drawn, already clamped.
    var agendaRows = 0
    /// Whether a "+N more" row sits under those rows. Reserved explicitly
    /// rather than folded into `agendaRows`: it is a shorter row than an
    /// event, and rounding it up to one would re-introduce the dead space
    /// this struct exists to remove.
    var hasAgendaOverflow = false
    /// Whether the idle island is offering the timer presets.
    var hasTimerPresets = false
    /// Download rows that will really be drawn, already clamped.
    var downloadRows = 0
    /// Whether the lyrics panel is open beside the player, which is the only
    /// thing that still claims the music layout's second column.
    var hasLyrics = false

    static let empty = IslandContent()
}

/// What one feature wants the island to look like while it owns it.
///
/// Sizes are **deltas from the measured notch**, not absolutes. The cutout
/// is 185x33pt on a 15" M4 Air and not on every machine, so a hardcoded 400
/// quietly assumes one of them; expressed as a delta the same layout lands
/// correctly on any notch.
struct IslandLayout: Equatable, Sendable {
    var expandedExtraWidth: CGFloat
    var expandedExtraHeight: CGFloat
    /// How much wider than the closed notch the compact wings run.
    var compactExtraWidth: CGFloat
    var expandedRadii: NotchRadii = .expanded
    var compactRadii: NotchRadii = .compact

    func expandedSize(closed: CGSize) -> CGSize {
        CGSize(width: closed.width + expandedExtraWidth, height: closed.height + expandedExtraHeight)
    }

    func compactSize(closed: CGSize) -> CGSize {
        CGSize(width: closed.width + compactExtraWidth, height: closed.height)
    }
}

// MARK: - The blocks layouts are built from

extension IslandLayout {
    /// Heights of the pieces expanded layouts stack, declared rather than
    /// measured. The island is sized *before* its content lays out, so a
    /// height that followed a `GeometryReader` would arrive a frame late
    /// and the island would morph twice for one change.
    ///
    /// Each is the block's drawn height at its own type sizes. They are the
    /// numbers to touch if a layout looks tight or airy — not the totals,
    /// which are derived.
    enum Block {
        /// `DateBlock`: 12pt weekday over a 34pt day number.
        static let date: CGFloat = 52
        /// `EventRow`: two lines of 12/11pt plus 4pt padding either side.
        static let eventRow: CGFloat = 37
        /// "Nothing scheduled" in place of the rows.
        static let emptyAgenda: CGFloat = 34
        /// The "+N more" line under the agenda.
        static let agendaOverflow: CGFloat = 20
        static let timerPresets: CGFloat = 24
        /// Artwork (56, or 72 in vinyl mode) beside the title, then the
        /// scrub row (18) and the transport row (30), with 12pt between
        /// each. Measured against what the column actually draws, so there
        /// is no dead space under the transport row.
        static let musicColumn: CGFloat = 128
        static let shelfHeader: CGFloat = 18
        static let shelfTile: CGFloat = 76
        /// Title over two lines of detail.
        static let alert: CGFloat = 47
        /// The OK/Settings row an alert may carry under its detail.
        static let alertActions: CGFloat = 24
        /// The countdown figure and its label; the buttons are shorter.
        static let countdown: CGFloat = 52
        static let volumeBar: CGFloat = 32
        /// Glyph tile (44), title (20) and three lines of body text (43.5),
        /// plus the 6pt gaps between them. Measured against what the view
        /// actually draws: it was 92, which is 27pt short of the copy block
        /// alone, and the shortfall came out of the bottom of the island —
        /// clipping the secondary "View GitHub" link clean in half.
        static let onboardingBody: CGFloat = 120
        /// The primary capsule (30) plus the secondary link (18) and the
        /// 6pt between them.
        static let onboardingButtons: CGFloat = 54
        /// The step dots between the copy and the buttons. Never reserved
        /// before, so every step was one row shorter than it drew.
        static let onboardingDots: CGFloat = 5
        /// One download: name over a progress bar.
        static let downloadRow: CGFloat = 34
        /// The AirDrop card: glyph over the file name and its status.
        static let airDrop: CGFloat = 62
        /// The recording indicator and its elapsed clock, side by side.
        static let recording: CGFloat = 34
    }

    /// Column widths, absolute because columns hold real text at real
    /// sizes. `extraWidth` turns one into the delta the island stores.
    enum Column {
        static let date: CGFloat = 46
        static let agenda: CGFloat = 240
        /// The agenda's empty state, which needs a sentence, not a list.
        static let emptyAgenda: CGFloat = 150
        static let music: CGFloat = 240
        /// Date block plus the one-event peek beside music.
        static let musicPeek: CGFloat = 140
        /// The same peek with nothing to peek at: the date block alone.
        static let datePeek: CGFloat = 92
        static let alertIcon: CGFloat = 40
        static let alertText: CGFloat = 250
        /// The preset row sets a floor under the idle island even when the
        /// agenda is empty.
        static let timerPresets: CGFloat = 200
        /// A sentence of body copy, centred, plus a full-width button.
        static let onboarding: CGFloat = 230
        static let download: CGFloat = 260
        static let airDrop: CGFloat = 200
        static let recording: CGFloat = 170
    }

    static let maxEventRows = 3
    /// Past this the rows stop fitting and the island shows a count instead.
    static let maxDownloadRows = 3

    /// The cutout the absolute column widths above were tuned against.
    /// Sizes stay deltas so they land on any notch; this only converts a
    /// content width into one.
    static let referenceNotchWidth: CGFloat = 185

    /// Chrome every expanded layout carries: clearance above the content
    /// for the camera housing, and the gutter below it.
    private static let chrome = IslandSpacing.cameraClearance + IslandSpacing.bottom

    private static func extraWidth(content: CGFloat) -> CGFloat {
        content + 2 * IslandSpacing.gutter - referenceNotchWidth
    }

    private static func extraHeight(_ blocks: CGFloat..., gap: CGFloat = IslandSpacing.block) -> CGFloat {
        chrome + blocks.reduce(0, +) + gap * CGFloat(max(blocks.count - 1, 0))
    }

    /// The agenda column's drawn height.
    static func agendaHeight(rows: Int, overflow: Bool = false) -> CGFloat {
        guard rows > 0 else { return Block.emptyAgenda }
        let list = CGFloat(rows) * Block.eventRow + CGFloat(rows - 1) * IslandSpacing.row
        return overflow ? list + IslandSpacing.row + Block.agendaOverflow : list
    }
}

// MARK: - Resolving a layout for what is on screen

extension IslandLayout {
    /// Nothing playing: the date block beside the agenda, timer presets
    /// underneath. Both axes follow the agenda — an empty one takes the
    /// island down to a pill rather than leaving a screen of black.
    static func idle(_ content: IslandContent) -> IslandLayout {
        let rows = min(max(content.agendaRows, 0), maxEventRows)
        let body = max(Block.date, agendaHeight(rows: rows, overflow: content.hasAgendaOverflow))
        let agendaWidth = rows > 0 ? Column.agenda : Column.emptyAgenda
        let columns = Column.date + IslandSpacing.column + agendaWidth
        return IslandLayout(
            expandedExtraWidth: extraWidth(content: max(columns, Column.timerPresets)),
            expandedExtraHeight: content.hasTimerPresets
                ? extraHeight(body, Block.timerPresets)
                : extraHeight(body),
            compactExtraWidth: 160
        )
    }

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
    static func nowPlaying(_ content: IslandContent) -> IslandLayout {
        let compactExtra: CGFloat = 160
        // The date is an overlay in the corner, not a column, so it costs
        // the island width only insofar as the title row stops short of it
        // — which `Column.music` already accounts for. Only the lyrics
        // panel is a real second column.
        let columns = content.hasLyrics
            ? Column.music + IslandSpacing.column + 1 + IslandSpacing.column + Column.musicPeek
            : Column.music + IslandSpacing.column + Column.datePeek
        return IslandLayout(
            expandedExtraWidth: max(extraWidth(content: columns), compactExtra + musicExpandMargin),
            expandedExtraHeight: extraHeight(Block.musicColumn),
            compactExtraWidth: compactExtra
        )
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
        expandedExtraWidth: extraWidth(content: Column.alertIcon + IslandSpacing.column + Column.alertText),
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
        nowPlaying(IslandContent(hasLyrics: true)),
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
        lock
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
