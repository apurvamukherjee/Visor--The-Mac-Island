import SwiftUI

/// The scrub bar, alone on its row.
///
/// Shuffle, repeat and a lyrics toggle used to flank it. All three are gone:
/// they are MediaRemote commands the adapter cannot deliver for every player
/// — YouTube Music in a browser reports no shuffle or repeat state and
/// accepts neither command — so the buttons rendered as controls that
/// silently did nothing. A dead control is worse than an absent one.
///
/// The bar itself is the reference's `PlayerProgressBar`, ported as-is: it
/// carries the elapsed and remaining times inline and thickens under a drag,
/// which is what keeps the row one fixed height whatever the track is.
struct MusicSeekRow: View {
    let progress: NowPlayingProgress
    /// Passed through to the bar for the `.artwork` tint style.
    var tint: Color?
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
}
