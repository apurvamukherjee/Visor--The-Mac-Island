import MediaRemoteAdapter
import SwiftUI

/// Shuffle and repeat flank the scrub bar rather than sit in the transport
/// row below it — the same split the reference flow uses, and the only one
/// that leaves `ExpandedMusicView`'s existing `controls` row untouched.
///
/// The bar itself is the reference's `PlayerProgressBar`, ported as-is: it
/// carries the elapsed and remaining times inline and thickens under a drag,
/// which is what keeps the row one fixed height whatever the track is.
struct MusicSeekRow: View {
    let shuffleMode: TrackInfo.ShuffleMode
    let repeatMode: TrackInfo.RepeatMode
    let progress: NowPlayingProgress
    /// Passed through to the bar for the `.artwork` tint style.
    var tint: Color?
    @Binding var showLyrics: Bool
    var commands: NotchStore.NowPlayingCommands?

    @State private var scrubProgress: CGFloat?

    var body: some View {
        // Ticks once a second while playing and every half minute while
        // paused — a paused track's position does not move, so there is
        // nothing to redraw for.
        TimelineView(.periodic(from: .now, by: progress.isPlaying ? 1 : 30)) { context in
            let elapsed = progress.elapsed(at: context.date)
            let live = progress.duration > 0 ? CGFloat(elapsed / progress.duration) : 0
            let shown = min(max(scrubProgress ?? live, 0), 1)

            HStack(spacing: 4) {
                miniButton("shuffle", isOn: shuffleMode != .off) {
                    commands?.toggleShuffle()
                }

                PlayerProgressBar(
                    progress: shown,
                    displayedElapsedTime: progress.duration > 0
                        ? TimeInterval(shown) * progress.duration
                        : elapsed,
                    duration: progress.duration,
                    isInteractive: progress.duration > 0,
                    tintGradient: tintGradient,
                    primaryColor: .white.opacity(0.7),
                    secondaryColor: .white.opacity(0.45),
                    onScrubChanged: { scrubProgress = $0 },
                    onScrubEnded: { newProgress in
                        commands?.seek(progress.duration * TimeInterval(newProgress))
                        scrubProgress = nil
                    }
                )

                miniButton(repeatGlyph, isOn: repeatMode != .off) {
                    commands?.cycleRepeat()
                }
                miniButton("text.quote", isOn: showLyrics) {
                    showLyrics.toggle()
                }
            }
        }
    }

    /// Follows the Settings tint style, off Visor's own `AlbumColor` result.
    private var tintGradient: LinearGradient? {
        switch ProgressTintStyle.current {
        case .standard:
            nil
        case .artwork:
            tint.map {
                LinearGradient(colors: [$0, $0.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
            }
        case .accent:
            LinearGradient(
                colors: [.accentColor, .accentColor.opacity(0.7)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var repeatGlyph: String {
        repeatMode == .one ? "repeat.1" : "repeat"
    }

    private func miniButton(_ symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isOn ? .white : .white.opacity(0.35))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
