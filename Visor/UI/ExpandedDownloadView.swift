import SwiftUI

/// One row per file arriving in ~/Downloads.
///
/// A file whose app reports no progress gets an indeterminate bar rather
/// than a guessed percentage — see `DownloadItem` for why that choice was
/// made rather than estimating from byte growth.
struct ExpandedDownloadView: View {
    let downloads: [DownloadItem]

    private var shown: [DownloadItem] {
        Array(downloads.prefix(IslandLayout.maxDownloadRows))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IslandSpacing.row) {
            ForEach(shown) { item in
                DownloadRow(item: item)
            }
            if downloads.count > shown.count {
                Text("+\(downloads.count - shown.count) more")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DownloadRow: View {
    let item: DownloadItem

    var body: some View {
        HStack(spacing: IslandSpacing.column) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let progress = item.progress {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 10, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.55))
                            .contentTransition(.numericText(value: progress))
                    }
                }
                DownloadBar(progress: item.progress)
            }
        }
    }
}

/// A determinate bar when the app told us where it is, and a plain track
/// when it didn't — never a moving bar that implies knowledge we lack.
private struct DownloadBar: View {
    let progress: Double?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                if let progress {
                    Capsule()
                        .fill(.blue)
                        .frame(width: geometry.size.width * min(max(progress, 0), 1))
                        .animation(Motion.resolved(Motion.layout), value: progress)
                }
            }
        }
        .frame(height: 3)
    }
}
