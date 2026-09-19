import SwiftUI

/// The player on the locked screen: artwork, title, artist and a progress
/// bar. Read-only — no transport controls, because the panel takes no mouse
/// events at all while the screen is locked.
struct LockScreenNowPlayingView: View {
    let info: NowPlayingInfo
    let artwork: CGImage?
    let tint: Color?
    let progress: NowPlayingProgress?

    private static let artSize: CGFloat = 76

    var body: some View {
        HStack(spacing: 14) {
            artworkCard
            VStack(alignment: .leading, spacing: 4) {
                Text(info.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let artist = info.artist {
                    Text(artist)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let progress {
                    // Projected from the anchor by `TimelineView`, so nothing
                    // ticks to keep it true — the same reason the scrub bar
                    // on the island does it this way.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        LockScreenProgressBar(
                            fraction: fraction(of: progress, at: context.date),
                            tint: tint ?? .white
                        )
                    }
                }
            }
            .frame(maxHeight: Self.artSize, alignment: .top)
        }
    }

    private func fraction(of progress: NowPlayingProgress, at date: Date) -> Double {
        guard progress.duration > 0 else { return 0 }
        return min(max(progress.elapsed(at: date) / progress.duration, 0), 1)
    }

    @ViewBuilder
    private var artworkCard: some View {
        if let artwork {
            Image(decorative: artwork, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: Self.artSize, height: Self.artSize)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.1))
                .frame(width: Self.artSize, height: Self.artSize)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.5))
                }
        }
    }
}

private struct LockScreenProgressBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 4)
    }
}
