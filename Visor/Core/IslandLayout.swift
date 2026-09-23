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

/// The deck's constants, in one place because they move together: raise the
/// offset without the inset and the chins stop reading as *behind* the front
/// card and start reading as a lip on it.
enum IslandStackMetrics {
    /// How far each chin sits below the card in front of it.
    static let chinOffset: CGFloat = 9
    /// How far each chin is drawn in at the sides. This is what makes a
    /// chin read as a card behind rather than a second edge on the same
    /// shape — an equal-width card peeking under another is one silhouette
    /// with a lip, not two cards.
    static let chinInset: CGFloat = 11
    /// How much rounder each chin is than the card in front, so the stack
    /// recedes instead of reading as three identical slabs.
    static let chinRadiusDrop: CGFloat = 3
    /// Three pages exist, so two chins. A fourth page extends the table
    /// rather than redesigning it.
    static let maxDepth = 2

    /// Distance from the front along the swipe axis, per page.
    ///
    /// Taken from the cycle, so the page "before" the front sits at the
    /// *back* rather than at a negative depth — a card at -1 would draw over
    /// the front one and hide it.
    static func depths(front: IslandPage, in available: [IslandPage]) -> [IslandPage: Int] {
        let stack = available.sorted { $0.rawValue < $1.rawValue }
        guard let start = stack.firstIndex(of: front) else { return [front: 0] }
        return stack.enumerated().reduce(into: [:]) { depths, entry in
            depths[entry.element] = (entry.offset - start + stack.count) % stack.count
        }
    }

    /// How far the deepest chin protrudes below the front card.
    static func reveal(forDepths deepest: Int) -> CGFloat {
        CGFloat(min(deepest, maxDepth)) * chinOffset
    }
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
    /// How wide the text in the *compact* left wing needs to be. Zero unless
    /// something with a long label owns the wing — today only the greeting,
    /// which is the one that overflowed. The compact island is symmetric
    /// about the cutout, so a wing this wide costs twice as much island.
    var compactLeadingWidth: CGFloat = 0
    /// Whether the player is showing its lyrics column. The island widens
    /// for it rather than the panel overlapping the card.
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
    /// How far the chins protrude below the front card. Zero unless the card
    /// stack is on *and* more than one page is reachable — a stack of one is
    /// just the island. Added to the expanded height rather than taken out
    /// of it: the front card keeps the size it has today, and the deck grows
    /// downward from it.
    var chinReveal: CGFloat = 0
    var expandedRadii: NotchRadii = .expanded
    var compactRadii: NotchRadii = .compact

    func expandedSize(closed: CGSize) -> CGSize {
        CGSize(
            width: closed.width + expandedExtraWidth,
            height: closed.height + expandedExtraHeight + chinReveal
        )
    }

    func compactSize(closed: CGSize) -> CGSize {
        CGSize(width: closed.width + compactExtraWidth, height: closed.height)
    }

    /// Grown to also hold `other`, keeping the receiver's own wings and radii.
    ///
    /// Paging changes what is *on* the island, never how big it is: every
    /// screen the swipe can reach resolves to one box, so a swipe cross-fades
    /// content inside a shape that does not move. Each screen used to resolve
    /// its own size, which made the notch grow and shrink under a gesture
    /// that only ever meant "show me the next thing".
    ///
    /// The wings and the radii stay the activity's. They are what the island
    /// looks like at rest, so a screen you swiped to must not still be
    /// deciding them once it has closed.
    func covering(_ other: IslandLayout) -> IslandLayout {
        var box = self
        box.expandedExtraWidth = max(expandedExtraWidth, other.expandedExtraWidth)
        box.expandedExtraHeight = max(expandedExtraHeight, other.expandedExtraHeight)
        return box
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
        /// The palette's query line: what has been typed, with a caret.
        static let paletteQuery: CGFloat = 26
        /// One command: glyph, title.
        static let paletteRow: CGFloat = 30
        /// One tool on the usage screen: its mark and model over the context
        /// bar, with today's total under it. Uniform whether or not that tool
        /// reports a context, so the rows stay a list rather than a ragged
        /// stack of two different cards.
        static let usageRow: CGFloat = 60
    }

    /// Column widths, absolute because columns hold real text at real
    /// sizes. `extraWidth` turns one into the delta the island stores.
    enum Column {
        static let date: CGFloat = 46
        static let agenda: CGFloat = 240
        /// The agenda's empty state, which needs a sentence, not a list.
        static let emptyAgenda: CGFloat = 150
        static let music: CGFloat = 240
        static let alertIcon: CGFloat = 40
        static let alertText: CGFloat = 250
        /// The drawn battery is wider than the symbol the other alerts use,
        /// so it gets its own column rather than widening theirs.
        static let batteryIndicator: CGFloat = 75
        /// The preset row sets a floor under the idle island even when the
        /// agenda is empty.
        static let timerPresets: CGFloat = 200
        /// A sentence of body copy, centred, plus a full-width button.
        static let onboarding: CGFloat = 230
        static let download: CGFloat = 260
        static let airDrop: CGFloat = 200
        static let recording: CGFloat = 170
        /// Wide enough that a command title and its glyph never truncate,
        /// which is the one thing a palette cannot do.
        static let palette: CGFloat = 300
        /// A few lines of lyric beside the player. Not a lyric sheet — the
        /// panel shows a window around the active line and nothing scrolls.
        static let lyrics: CGFloat = 170
        /// Wide enough for a full-length model identifier beside the tool's
        /// own name, which is the longest thing on the usage screen.
        static let usage: CGFloat = 280
    }

    /// Past this the list scrolls off the island rather than growing it —
    /// an island tall enough for seven rows stops being an island.
    static let maxPaletteRows = 4
    /// One row per agent, and there are two agents.
    static let maxUsageRows = 2
    static let maxEventRows = 3
    /// How many events the agenda *page* draws, which is one fewer than the
    /// idle home screen.
    ///
    /// Paging holds every screen in one box and the player is what measures
    /// it, so the agenda has the player's content height to work in: 128pt.
    /// Three rows and a "+N more" is 146 and would push the box 18pt taller
    /// than the card it opens on — the island's height would then track how
    /// many meetings you have. Two rows and the overflow line is 104 and
    /// fits, and the count is still honest because the overflow line grows
    /// by the row it lost. Same reasoning as `maxPaletteRows`.
    static let maxPagedEventRows = 2
    /// Past this the rows stop fitting and the island shows a count instead.
    static let maxDownloadRows = 3

    /// The cutout the absolute column widths above were tuned against.
    /// Sizes stay deltas so they land on any notch; this only converts a
    /// content width into one.
    static let referenceNotchWidth: CGFloat = 185

    /// Chrome every expanded layout carries: clearance above the content
    /// for the camera housing, and the gutter below it.
    static let chrome = IslandSpacing.cameraClearance + IslandSpacing.bottom

    /// These three are the vocabulary every layout in
    /// `IslandLayout+Resolution` is written in, which is why they are not
    /// private: the layouts moved to their own file and the words they are
    /// built from stayed here with the blocks and columns.
    static func extraWidth(content: CGFloat) -> CGFloat {
        content + 2 * IslandSpacing.gutter - referenceNotchWidth
    }

    static func extraHeight(_ blocks: CGFloat..., gap: CGFloat = IslandSpacing.block) -> CGFloat {
        chrome + blocks.reduce(0, +) + gap * CGFloat(max(blocks.count - 1, 0))
    }

    /// The agenda column's drawn height.
    static func agendaHeight(rows: Int, overflow: Bool = false) -> CGFloat {
        guard rows > 0 else { return Block.emptyAgenda }
        let list = CGFloat(rows) * Block.eventRow + CGFloat(rows - 1) * IslandSpacing.row
        return overflow ? list + IslandSpacing.row + Block.agendaOverflow : list
    }
}
