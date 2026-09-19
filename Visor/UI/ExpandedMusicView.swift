import SwiftUI

/// Expanded with something playing: music on the left, date + a single-event
/// calendar peek on the right. The calendar shrinks to make room — it never
/// disappears — and the one-chip peek is what lets the island sit ~40pt
/// shorter than the idle layout.
struct ExpandedMusicView: View {
    let info: NowPlayingInfo
    let artwork: CGImage?
    let tint: Color?
    let commands: NotchStore.NowPlayingCommands?
    /// Anchor-based position, nil when the source app reports no duration.
    let progress: NowPlayingProgress?
    let events: [CalendarEvent]
    /// Reports the lyrics panel's state back to the store, so the island
    /// can resize for the second column before it draws.
    var onLyricsVisibilityChange: ((Bool) -> Void)?
    /// Cursor position for the parallax tilt, nil when the pointer is away.
    let hoverPoint: CGPoint?
    /// Pre-blurred artwork for the halo behind the cover.
    let bleed: CGImage?

    private static let artworkSide: CGFloat = 56
    /// Fixed, so a long title can never reflow the rows beneath it. Wide
    /// enough to clear the date box in the corner above it, since the title
    /// row is the one row that shares its height.
    private static let textWidth: CGFloat = 190
    /// The record runs larger than the cover it replaces: a disc reads as a
    /// disc only once the grooves and the tonearm have room. Still inside the
    /// existing 168pt island — the height comes out of the music column's
    /// slack, so the notch itself does not grow.
    private static let vinylSide: CGFloat = 72
    /// Raised from 6° after live feedback: at 6° the parallax was real but
    /// nobody noticed it. 12° is still short of the angle where the card stops
    /// reading as a surface and starts reading as an object in a box.
    private static let maxTilt = 12.0
    /// A little scale on top of the tilt, so the card also leans *toward* the
    /// cursor rather than only rotating under it — the part that makes the
    /// movement legible at a glance.
    private static let hoverLift = 1.04

    /// The face currently on screen, which lags `artwork` by half a flip.
    @State private var shownArtwork: CGImage?
    @State private var flipAngle = 0.0
    /// Read on appear and after each toggle rather than observed: device mute
    /// only changes when someone changes it, and a listener here would be a
    /// live CoreAudio callback for a glyph nobody is looking at.
    @State private var isMuted: Bool?

    /// Fetched only while this is true — see `loadLyricsIfNeeded` — so
    /// playing music never phones out to LRCLIB on its own.
    @State private var showLyrics = false
    @State private var lyricsResult: LyricsResult?
    @State private var lyricsTask: Task<Void, Never>?

    @AppStorage(Preferences.vinylModeKey) private var vinylMode = false
    @AppStorage(Preferences.equalizerKey) private var showEqualizer = false

    var body: some View {
        // The date is an overlay in the top-right corner, not a column.
        // As a column it claimed full height for content that only fills the
        // top of it, so the player was squeezed into the left while a tall
        // strip of black sat beside it — and the full-height separator drew
        // a line down the middle of that emptiness. The player now gets the
        // whole width and the date sits in the corner it actually occupies.
        //
        // The lyrics panel is still a real column: it is full-height content.
        HStack(alignment: .top, spacing: IslandSpacing.column) {
            musicColumn
            if showLyrics {
                separator
                lyricsColumn
            }
        }
        .overlay(alignment: .topTrailing) {
            if !showLyrics {
                datePeek
            }
        }
        .foregroundStyle(.white)
        .onChange(of: showLyrics) {
            onLyricsVisibilityChange?(showLyrics)
            loadLyricsIfNeeded()
        }
        .onDisappear { onLyricsVisibilityChange?(false) }
        .onChange(of: info.trackIdentity) { loadLyricsIfNeeded() }
    }

    private func loadLyricsIfNeeded() {
        lyricsTask?.cancel()
        guard showLyrics else { return }
        lyricsResult = nil
        let title = info.title
        let artist = info.artist
        lyricsTask = Task {
            let result = await LyricsFetcher.fetch(title: title, artist: artist)
            guard !Task.isCancelled else { return }
            lyricsResult = result
        }
    }

    /// A hairline inset equally top and bottom, so it reads as centred
    /// between the columns rather than a full-height rule cutting the island
    /// in two.
    private var separator: some View {
        Capsule()
            // Just enough to separate the columns. Anything brighter draws
            // the eye to the divider instead of the content, and reads as a
            // grey line laid over the black rather than part of it.
            .fill(.white.opacity(0.07))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .padding(.vertical, 8)
    }

    /// Art beside the title, scrub row and transport underneath.
    ///
    /// The title and artist are `MarqueeText` at an explicit width, which is
    /// the reference's own answer to the row below them jumping: a `Text`
    /// that sizes itself to its content reflows the whole column every time
    /// a longer title arrives, and the transport row visibly moves.
    private var musicColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                artworkView
                VStack(alignment: .leading, spacing: 1) {
                    MarqueeText(
                        .constant(info.title),
                        font: .system(size: 14, weight: .bold, design: .rounded),
                        nsFont: .headline,
                        textColor: .white,
                        backgroundColor: .clear,
                        minDuration: 2.0,
                        frameWidth: Self.textWidth
                    )
                    MarqueeText(
                        .constant(info.artist ?? ""),
                        font: .system(size: 12, design: .rounded),
                        nsFont: .headline,
                        textColor: .white.opacity(0.55),
                        backgroundColor: .clear,
                        minDuration: 3.0,
                        frameWidth: Self.textWidth
                    )
                }
                // The new track's text rises into place as the old one leaves
                // upward; clipped to its own box so it never paints over the
                // artwork or past the island's edge.
                .id(info.trackIdentity)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                    .animation(Motion.resolved(Motion.textSwap))
                )
                .frame(height: 32, alignment: .leading)
                .clipped()

                if showEqualizer {
                    NowPlayingEqualizer(isPlaying: info.isPlaying, tint: tint)
                }
                Spacer(minLength: 0)
            }
            // The date box sits above this row, so it stops short of it.
            // The scrub and transport rows below run the full width.
            .padding(.trailing, showLyrics ? 0 : dateBoxWidth + IslandSpacing.column)
            // Hidden outright when the source app reports no duration,
            // rather than drawing a bar with nothing to show.
            if let progress {
                MusicSeekRow(
                    shuffleMode: info.shuffleMode,
                    repeatMode: info.repeatMode,
                    progress: progress,
                    tint: tint,
                    showLyrics: $showLyrics,
                    commands: commands
                )
            }
            controls
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .gesture(swipe)
    }

    /// Threshold swipe only — no live drag tracking, no velocity handling.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                guard abs(value.translation.width) > NotchContentView.swipeThreshold else { return }
                // Same direction as the trackpad swipe in `NotchContentView`:
                // right advances, left goes back.
                if value.translation.width < 0 {
                    commands?.previous()
                } else {
                    commands?.next()
                }
            }
    }

    /// Card flip on track change: the old face turns to edge-on, the image
    /// swaps at that hidden frame, and the new face swings out. Two halves
    /// rather than one 180° turn, or the new art would land mirrored.
    private var artworkView: some View {
        // A ZStack, not `card.background`: a background is sized to the view
        // it backs, which would pen a halo drawn at 1.9x the cover into a
        // cover-sized slot. As siblings the glow keeps its own footprint and
        // the card's own clip never applies to it.
        ZStack {
            if let bleed, AmbientArtBleed.isPermitted {
                AmbientArtBleed(image: bleed, side: side)
                    .transition(.opacity)
            }
            card
        }
        // The halo is decoration and must not claim space: without this the
        // ZStack sizes to the 1.9x glow and pushes the title column sideways.
        .frame(width: side, height: side)
        .animation(Motion.resolved(Motion.artSwap), value: info.trackIdentity)
        // Clicking the cover brings the player forward — the cover only,
        // since a click anywhere else on the island already means something
        // (double-click toggles playback, right-click opens Settings).
        .contentShape(Rectangle())
        .onTapGesture { activatePlayer() }
        .help("Open \(info.bundleIdentifier == nil ? "the player" : "in the player")")
    }

    /// Brings whichever app is playing to the front. `NSRunningApplication`
    /// rather than `NSWorkspace.launchApplication`: the app is already
    /// running by definition, and this activates the existing instance
    /// instead of risking a second one.
    private func activatePlayer() {
        guard let bundleIdentifier = info.bundleIdentifier else { return }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard let app = running.first else { return }
        app.activate(options: [.activateAllWindows])
    }

    private var card: some View {
        artworkFace(shownArtwork)
            .frame(width: side, height: side)
            // Only the square cover needs rounding. The disc draws itself
            // round and keeps the tonearm inside its own bounds (the record
            // is inset to 0.88 to make that room), so a radius here would
            // gain nothing and risks shaving the arm.
            .clipShape(RoundedRectangle(cornerRadius: vinylMode ? 0 : 12))
            // Paused art dims and settles back a little. State without an
            // icon: the transport button already says "play", so the card
            // only has to *feel* stopped.
            .saturation(info.isPlaying ? 1 : 0.65)
            // Pause shrink and hover lift multiply rather than override: a
            // paused card still leans toward the cursor, just from smaller.
            .scaleEffect((info.isPlaying ? 1 : 0.96) * (hoverPoint == nil ? 1 : Self.hoverLift))
            .animation(Motion.resolved(Motion.artSwap), value: info.isPlaying)
            // Flip first, then parallax: the flip owns the card's own Y axis,
            // and tilting the result keeps the two from fighting over it. The
            // reverse order skews the card mid-flip.
            //
            // The flip and `tilt.x` share the Y axis but must NOT be summed
            // into one modifier: the flip relies on hitting exactly ±90°, the
            // edge-on frame where the card is invisible and the image swaps.
            // Adding a live tilt to that angle lands it at 78° or 102°, where
            // the card still has width — and the swap becomes visible.
            .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(tilt.y), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
            .rotation3DEffect(.degrees(tilt.x), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .animation(Motion.resolved(Motion.artSwap), value: hoverPoint == nil)
            // Added after the rotation so the bars stay flat while the card
            // turns, and scrimmed so they read against pale artwork.
            // Not in vinyl mode: a bottom-trailing badge on a round disc sits
            // outside the circle, and the tonearm already says whether the
            // record is playing.
            .overlay(alignment: .bottomTrailing) {
                if !vinylMode {
                    PlaybackBars(isPlaying: info.isPlaying, height: 13, tint: tint)
                        .padding(5)
                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
                        .padding(4)
                }
            }
            .onAppear { shownArtwork = artwork }
            .onChange(of: info.trackIdentity) { flip(to: artwork) }
    }

    /// The record is larger than the cover it stands in for.
    private var side: CGFloat {
        vinylMode ? Self.vinylSide : Self.artworkSide
    }

    /// Degrees of tilt on each axis. Y inverts because a cursor *above* the
    /// card should push its top edge away, not pull it forward.
    private var tilt: (x: Double, y: Double) {
        guard let hoverPoint, !Motion.reduceMotion else { return (0, 0) }
        return (x: hoverPoint.x * Self.maxTilt, y: -hoverPoint.y * Self.maxTilt)
    }

    @ViewBuilder
    private func artworkFace(_ image: CGImage?) -> some View {
        if vinylMode {
            VinylDisc(
                isSpinning: info.isPlaying,
                side: side,
                tint: tint,
                artwork: image
            )
        } else if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle().fill(.white.opacity(0.12))
        }
    }

    /// Reduce Motion gets the old crossfade instead — a rotation through
    /// perspective is exactly the vestibular trigger the setting asks about.
    /// So does vinyl mode: flipping a record that is already turning reads as
    /// two competing rotations, and the disc has no back face to reveal.
    private func flip(to newArtwork: CGImage?) {
        guard !Motion.reduceMotion, !vinylMode else {
            withAnimation(Motion.resolved(Motion.artSwap)) { shownArtwork = newArtwork }
            return
        }
        withAnimation(Motion.artFlipOut, completionCriteria: .logicallyComplete) {
            flipAngle = 90
        } completion: {
            shownArtwork = newArtwork
            flipAngle = -90
            withAnimation(Motion.artFlipIn) { flipAngle = 0 }
        }
    }

    /// The reference's own transport buttons, with their press feedback —
    /// a pulse, a scale and a directional nudge. Ported rather than
    /// re-implemented, so it behaves exactly as it does there.
    private var controls: some View {
        HStack(spacing: 14) {
            PlayerControlButton(
                systemImage: "backward.fill",
                fontSize: 16,
                width: 34,
                height: 30,
                feedbackStyle: .backward
            ) {
                commands?.previous()
            }

            PlayerControlButton(
                systemImage: info.isPlaying ? "pause.fill" : "play.fill",
                fontSize: 22,
                width: 34,
                height: 30,
                feedbackStyle: .playPause
            ) {
                commands?.togglePlayPause()
            }

            PlayerControlButton(
                systemImage: "forward.fill",
                fontSize: 16,
                width: 34,
                height: 30,
                feedbackStyle: .forward
            ) {
                commands?.next()
            }

            if let isMuted {
                PlayerControlButton(
                    systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    fontSize: 15,
                    width: 34,
                    height: 30
                ) {
                    SystemMute.toggle()
                    self.isMuted = SystemMute.isMuted
                }
                .opacity(isMuted ? 1 : 0.55)
            }
        }
        .onAppear { isMuted = SystemMute.isMuted }
        .frame(maxWidth: .infinity)
    }

    /// The date, and at most one upcoming event under it. With nothing
    /// upcoming this is the date block alone and the column narrows, so a
    /// clear day does not hold an empty panel open.
    /// The date, and the single next event under it when there is one.
    /// A fixed box in the corner: it takes only the height it draws, so
    /// nothing below it is dead space, and it never resizes the island
    /// under the player.
    private var datePeek: some View {
        VStack(alignment: .trailing, spacing: IslandSpacing.row) {
            DateBlock(alignment: .trailing)
            if let next = peek.first {
                EventRow(event: next)
                    .frame(width: IslandLayout.Column.datePeek, alignment: .leading)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: IslandLayout.Column.datePeek, alignment: .trailing)
        .animation(Motion.resolved(Motion.layout), value: peek.isEmpty)
        .transition(.island)
    }

    /// What the corner box occupies, so the title row can stop short of it.
    private var dateBoxWidth: CGFloat {
        IslandLayout.Column.datePeek
    }

    private var peek: [CalendarEvent] {
        CalendarEventMapper.upcoming(events, now: .now, limit: 1)
    }

    private var lyricsColumn: some View {
        LyricsPanelView(result: lyricsResult, progress: progress)
            .frame(width: IslandLayout.Column.musicPeek, alignment: .leading)
            .transition(.island)
    }
}
