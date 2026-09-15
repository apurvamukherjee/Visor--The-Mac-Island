import SwiftUI

/// Expanded with something playing: music on the left, date + a trimmed
/// calendar peek on the right. The calendar shrinks to make room — it never
/// disappears.
struct ExpandedMusicView: View {
    let info: NowPlayingInfo
    let artwork: CGImage?
    let commands: NotchStore.NowPlayingCommands?
    let events: [CalendarEvent]

    private static let peekLimit = 2
    private static let swipeThreshold: CGFloat = 50

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            musicColumn
            Divider().overlay(.white.opacity(0.12))
            calendarColumn
        }
        .foregroundStyle(.white)
    }

    private var musicColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            artworkView
            VStack(alignment: .leading, spacing: 0) {
                Text(info.title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                if let artist = info.artist {
                    Text(artist)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            // Text crossfades on track change; it never flips or rotates.
            .id(info.trackIdentity)
            .transition(.opacity.animation(Motion.resolved(Motion.textSwap)))
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

    private var artworkView: some View {
        Group {
            if let artwork {
                Image(decorative: artwork, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(.white.opacity(0.12))
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
        HStack(spacing: 22) {
            Button { commands?.previous() } label: {
                Image(systemName: "backward.fill").font(.system(size: 15))
            }
            Button { commands?.togglePlayPause() } label: {
                Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17))
                    .contentTransition(.symbolEffect(.replace))
            }
            Button { commands?.next() } label: {
                Image(systemName: "forward.fill").font(.system(size: 15))
            }
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private var calendarColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            DateBlock(alignment: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
            ForEach(peek) { EventRow(event: $0) }
            Spacer(minLength: 0)
        }
        .frame(width: 210, alignment: .leading)
    }

    private var peek: [CalendarEvent] {
        CalendarEventMapper.upcoming(events, now: .now, limit: Self.peekLimit)
    }
}
