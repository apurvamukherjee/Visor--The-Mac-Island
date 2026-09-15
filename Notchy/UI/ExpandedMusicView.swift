import SwiftUI

/// Expanded with something playing: music on the left, date + a single-event
/// calendar peek on the right. The calendar shrinks to make room — it never
/// disappears — and the one-chip peek is what lets the island sit ~40pt
/// shorter than the idle layout.
struct ExpandedMusicView: View {
    let info: NowPlayingInfo
    let artwork: CGImage?
    let commands: NotchStore.NowPlayingCommands?
    let events: [CalendarEvent]

    private static let peekLimit = 1
    private static let artworkSide: CGFloat = 56

    /// The face currently on screen, which lags `artwork` by half a flip.
    @State private var shownArtwork: CGImage?
    @State private var flipAngle = 0.0
    private static let swipeThreshold: CGFloat = 50

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            musicColumn
            Divider().overlay(.white.opacity(0.12))
            calendarColumn
        }
        .foregroundStyle(.white)
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
                guard abs(value.translation.width) > Self.swipeThreshold else { return }
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
        artworkFace(shownArtwork)
            .frame(width: Self.artworkSide, height: Self.artworkSide)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
            .onAppear { shownArtwork = artwork }
            .onChange(of: info.trackIdentity) { flip(to: artwork) }
    }

    @ViewBuilder
    private func artworkFace(_ image: CGImage?) -> some View {
        if let image {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle().fill(.white.opacity(0.12))
        }
    }

    /// Reduce Motion gets the old crossfade instead — a rotation through
    /// perspective is exactly the vestibular trigger the setting asks about.
    private func flip(to newArtwork: CGImage?) {
        guard !Motion.reduceMotion else {
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
            transportButton("backward.fill", size: 16) { commands?.previous() }
            transportButton(info.isPlaying ? "pause.fill" : "play.fill", size: 22) {
                commands?.togglePlayPause()
            }
            transportButton("forward.fill", size: 16) { commands?.next() }
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
