import SwiftUI

/// Expanded with something playing: music on the left, a trimmed calendar
/// peek on the right. The calendar shrinks to make room — it never
/// disappears.
struct ExpandedMusicView: View {
    let info: NowPlayingInfo
    let artwork: CGImage?
    let commands: NotchStore.NowPlayingCommands?
    let events: [CalendarEvent]

    private static let peekLimit = 2
    private static let swipeThreshold: CGFloat = 50

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            musicColumn
            Divider().overlay(.white.opacity(0.15))
            calendarColumn
        }
        .foregroundStyle(.white)
    }

    private var musicColumn: some View {
        HStack(spacing: 10) {
            artworkView
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title)
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .lineLimit(1)
                if let artist = info.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                controls.padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        // Text crossfades on track change; it never flips or rotates.
        .id(info.trackIdentity)
        .transition(.opacity.animation(Motion.resolved(Motion.textSwap)))
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

    private var artworkView: some View {
        Group {
            if let artwork {
                Image(decorative: artwork, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(.white.opacity(0.15))
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        // Crossfade + scale-pop, not a 3D flip: at this size a Y-axis flip's
        // foreshortened mid-frames span a handful of pixels and read as a
        // flicker. See the spec's §9.2.
        .id(info.trackIdentity)
        .transition(
            .asymmetric(
                insertion: .opacity.combined(with: .scale(scale: 0.92)),
                removal: .opacity
            )
            .animation(Motion.resolved(Motion.artSwap))
        )
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button { commands?.previous() } label: { Image(systemName: "backward.fill") }
            Button { commands?.togglePlayPause() } label: {
                Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            Button { commands?.next() } label: { Image(systemName: "forward.fill") }
        }
        .font(.caption)
        .buttonStyle(.plain)
    }

    private var calendarColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(peek) { EventRow(event: $0) }
            Spacer(minLength: 0)
        }
        .frame(width: 200, alignment: .leading)
    }

    private var peek: [CalendarEvent] {
        CalendarEventMapper.upcoming(events, now: .now, limit: Self.peekLimit)
    }
}
