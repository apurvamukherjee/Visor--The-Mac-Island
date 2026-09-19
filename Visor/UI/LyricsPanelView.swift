import SwiftUI

/// Fills the calendar column when lyrics are toggled on. A small window
/// around the active line rather than a scrolling list — the column is
/// ~150pt tall, which is a few lines of context, not a lyric sheet.
struct LyricsPanelView: View {
    let result: LyricsResult?
    let progress: NowPlayingProgress?

    var body: some View {
        Group {
            switch result {
            case nil:
                loading
            case .unavailable:
                placeholder("No lyrics found")
            case let .plain(text):
                plainText(text)
            case let .synced(lyrics):
                synced(lyrics)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var loading: some View {
        ProgressView()
            .controlSize(.small)
            .tint(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(.white.opacity(0.4))
    }

    private func plainText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, design: .rounded))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(6)
    }

    @ViewBuilder
    private func synced(_ lyrics: TrackLyrics) -> some View {
        if let progress {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                lines(lyrics, elapsed: progress.elapsed(at: context.date))
            }
        } else {
            lines(lyrics, elapsed: 0)
        }
    }

    private func lines(_ lyrics: TrackLyrics, elapsed: TimeInterval) -> some View {
        let activeIndex = lyrics.activeLineIndex(at: elapsed)
        return VStack(alignment: .leading, spacing: 4) {
            ForEach(lyrics.window(around: activeIndex, radius: 1)) { entry in
                Text(entry.line.text)
                    .font(.system(
                        size: entry.isActive ? 12 : 10,
                        weight: entry.isActive ? .semibold : .regular,
                        design: .rounded
                    ))
                    .foregroundStyle(entry.isActive ? .white : .white.opacity(0.4))
                    .lineLimit(2)
            }
        }
        .animation(Motion.resolved(Motion.textSwap), value: activeIndex)
    }
}
