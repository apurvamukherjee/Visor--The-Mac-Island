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
    let events: [CalendarEvent]
    /// Cursor position for the parallax tilt, nil when the pointer is away.
    let hoverPoint: CGPoint?
    /// Pre-blurred artwork for the halo behind the cover.
    let bleed: CGImage?

    private static let peekLimit = 1
    private static let artworkSide: CGFloat = 56
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

    @AppStorage(Preferences.vinylModeKey) private var vinylMode = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            musicColumn
            separator
            calendarColumn
        }
        .foregroundStyle(.white)
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

    /// Art beside the title, transport underneath: at a 400pt island the
    /// music column is ~220pt, too narrow to carry art, text and a 130pt
    /// transport row on one line without shrinking the targets.
    private var musicColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                artworkView
                VStack(alignment: .leading, spacing: 1) {
                    Text(info.title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    if let artist = info.artist {
                        Text(artist)
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
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
                if value.translation.width < 0 {
                    commands?.next()
                } else {
                    commands?.previous()
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

    private var controls: some View {
        HStack(spacing: 8) {
            transportButton("backward.fill", size: 16) {
                commands?.previous()
            }
            transportButton(info.isPlaying ? "pause.fill" : "play.fill", size: 22) {
                commands?.togglePlayPause()
            }
            transportButton("forward.fill", size: 16) {
                commands?.next()
            }
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
    }

    private func transportButton(
        _ symbol: String,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size))
                .contentTransition(.symbolEffect(.replace))
                // Padding alone leaves the gaps dead; an explicit square with
                // a content shape makes the whole target clickable.
                .frame(width: 38, height: 34)
                .contentShape(Rectangle())
        }
    }

    private var calendarColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            DateBlock(alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
            ForEach(peek) { EventRow(event: $0) }
            Spacer(minLength: 0)
        }
        // The date block plus one chip need ~150; everything left over goes
        // to the music column and its transport row.
        .frame(width: 150, alignment: .leading)
    }

    private var peek: [CalendarEvent] {
        CalendarEventMapper.upcoming(events, now: .now, limit: Self.peekLimit)
    }
}
