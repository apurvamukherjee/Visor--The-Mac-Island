import SwiftUI

struct ExpandedNowPlayingView: View {
    let info: NowPlayingInfo
    let artwork: CGImage?
    let commands: NotchStore.NowPlayingCommands?

    var body: some View {
        HStack(spacing: 10) {
            artworkView
            VStack(alignment: .leading, spacing: 2) {
                Text(info.title).font(.callout).lineLimit(1)
                if let artist = info.artist {
                    Text(artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                progressView
            }
            controls
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var artworkView: some View {
        if let artwork {
            Image(decorative: artwork, scale: 1)
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.15))
                .frame(width: 40, height: 40)
        }
    }

    /// Ticks once per second only while actually playing — a paused track
    /// renders a single static value instead of re-evaluating on a timer,
    /// per the power rule (nothing ticks when not playing).
    @ViewBuilder
    private var progressView: some View {
        if let duration = info.duration, duration > 0 {
            if info.isPlaying {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let projected = info.elapsedTime + context.date.timeIntervalSince(info.timestamp) * info
                        .playbackRate
                    ProgressView(value: min(max(projected, 0), duration), total: duration)
                        .tint(.white)
                }
            } else {
                ProgressView(value: min(max(info.elapsedTime, 0), duration), total: duration)
                    .tint(.white)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                commands?.previous()
            } label: {
                Image(systemName: "backward.fill")
            }
            Button {
                commands?.togglePlayPause()
            } label: {
                Image(systemName: info.isPlaying ? "pause.fill" : "play.fill")
            }
            Button {
                commands?.next()
            } label: {
                Image(systemName: "forward.fill")
            }
        }
        .buttonStyle(.plain)
    }
}
