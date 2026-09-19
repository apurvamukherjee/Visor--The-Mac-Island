import SwiftUI

/// The player card on the lock screen. Ported from the reference's
/// `LockScreenNowPlayingView`, reading Visor's `NotchStore` instead of its
/// view models.
///
/// Every frame in here is fixed on purpose. The reference sizes the title and
/// artist with an explicit `frameWidth` and gives the whole card a constant
/// height, which is what stops the transport row moving when a track with a
/// longer title arrives — a layout that sizes itself to the text makes the
/// controls jump on every change.
struct LockScreenNowPlayingView: View {
    @Environment(\.notchScale) var scale

    let info: NowPlayingInfo
    let artwork: CGImage?
    let tint: Color?
    let progress: NowPlayingProgress?
    let commands: NotchStore.NowPlayingCommands?
    @Binding var onTapArtwork: Bool

    @State private var scrubProgress: CGFloat?

    /// The two widths the reference uses: narrow while the artwork thumbnail
    /// is beside the text, wide once it has been lifted out.
    private var textWidth: CGFloat {
        onTapArtwork ? 260.scaled(by: scale) : 180.scaled(by: scale)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: progressTick)) { context in
            timelineContent(at: context.date)
        }
    }

    private func timelineContent(at date: Date) -> some View {
        let duration = progress?.duration ?? 0
        let elapsed = progress?.elapsed(at: date) ?? 0
        let liveProgress = progressValue(elapsed: elapsed, duration: duration)
        let displayedProgress = min(max(scrubProgress ?? liveProgress, 0), 1)
        let displayedElapsed = duration > 0 ? TimeInterval(displayedProgress) * duration : elapsed

        return VStack {
            HStack(spacing: 15) {
                if onTapArtwork == false {
                    Button {
                        withAnimation(.spring(response: 0.6)) { onTapArtwork = true }
                    } label: {
                        artworkView(side: 60, cornerRadius: 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlaybackSourceButtonStyle())
                }

                HStack(alignment: .top) {
                    Button {
                        withAnimation(.spring(response: 0.6)) { onTapArtwork.toggle() }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            MarqueeText(
                                .constant(displayTitle),
                                font: .system(size: 16, weight: .medium),
                                nsFont: .headline,
                                textColor: .white.opacity(0.8),
                                backgroundColor: .clear,
                                minDuration: 2.0,
                                frameWidth: textWidth
                            )

                            MarqueeText(
                                .constant(displayArtist),
                                font: .system(size: 14),
                                nsFont: .headline,
                                textColor: .white.opacity(0.5),
                                backgroundColor: .clear,
                                minDuration: 3.0,
                                frameWidth: textWidth
                            )
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlaybackSourceButtonStyle())

                    Spacer()

                    LightweightNowPlayingEqualizerView(
                        isPlaying: info.isPlaying,
                        color: NSColor.white.withAlphaComponent(0.7),
                        barHeight: 20,
                        barWidth: 2.2
                    )
                    .frame(width: 13, height: 15)
                }
                .padding(.trailing, 5)
            }

            Spacer()

            PlayerProgressBar(
                progress: displayedProgress,
                displayedElapsedTime: displayedElapsed,
                duration: duration,
                isInteractive: duration > 0,
                tintGradient: tintGradient,
                primaryColor: .white.opacity(0.8),
                secondaryColor: .white.opacity(0.5),
                onScrubChanged: { scrubProgress = $0 },
                onScrubEnded: { newProgress in
                    commands?.seek(duration * TimeInterval(newProgress))
                    scrubProgress = nil
                }
            )

            Spacer()

            transportRow
        }
        .padding(18)
    }

    /// Split out only to keep the body under the length limit; the reference
    /// has it inline.
    private var transportRow: some View {
        HStack(spacing: 25) {
            PlayerControlButton(
                systemImage: "backward.fill",
                fontSize: 22,
                width: 42,
                height: 42,
                feedbackStyle: .backward
            ) {
                commands?.previous()
            }

            PlayerControlButton(
                systemImage: info.isPlaying ? "pause.fill" : "play.fill",
                fontSize: 32,
                width: 42,
                height: 42,
                feedbackStyle: .playPause
            ) {
                commands?.togglePlayPause()
            }

            PlayerControlButton(
                systemImage: "forward.fill",
                fontSize: 22,
                width: 42,
                height: 42,
                feedbackStyle: .forward
            ) {
                commands?.next()
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func artworkView(side: CGFloat, cornerRadius: CGFloat) -> some View {
        if let artwork {
            Image(decorative: artwork, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.white.opacity(0.1))
                .frame(width: side, height: side)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: side * 0.35))
                        .foregroundStyle(.white.opacity(0.5))
                }
        }
    }

    /// Follows the Settings tint style, reusing Visor's own `AlbumColor`
    /// result rather than the reference's separate CIAreaAverage palette.
    private var tintGradient: LinearGradient? {
        switch ProgressTintStyle.current {
        case .standard:
            nil
        case .artwork:
            tint.map { colour in
                LinearGradient(
                    colors: [colour, colour.opacity(0.7)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        case .accent:
            LinearGradient(
                colors: [.accentColor, .accentColor.opacity(0.7)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private var displayTitle: String {
        info.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Track" : info.title
    }

    private var displayArtist: String {
        let artist = info.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return artist.isEmpty ? "Unknown Artist" : artist
    }

    private func progressValue(elapsed: TimeInterval, duration: TimeInterval) -> CGFloat {
        guard duration > 0 else { return 0 }
        return min(max(CGFloat(elapsed / duration), 0), 1)
    }

    /// A second while playing, half a minute while paused — a paused track's
    /// position does not move, so there is nothing to redraw for.
    private var progressTick: TimeInterval {
        info.isPlaying ? 1.0 : 30.0
    }
}
