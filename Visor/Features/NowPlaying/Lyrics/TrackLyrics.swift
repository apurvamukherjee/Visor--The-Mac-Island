import Foundation

/// Time-tagged lyric lines for one track, and the pure lookups the panel
/// reads from a `TimelineView` tick — see `LyricsPanelView`.
struct TrackLyrics: Equatable, Sendable {
    let lines: [LyricLine]

    struct WindowEntry: Identifiable, Equatable {
        let id: Int
        let line: LyricLine
        let isActive: Bool
    }

    /// The last line whose timestamp has passed, or nil before the first
    /// one / when there are none.
    func activeLineIndex(at elapsed: TimeInterval) -> Int? {
        var result: Int?
        for (index, line) in lines.enumerated() where line.time <= elapsed {
            result = index
        }
        return result
    }

    /// A small window around the active line — the panel shows a few lines
    /// of context, not the whole song, so nothing here scrolls.
    func window(around activeIndex: Int?, radius: Int) -> [WindowEntry] {
        guard let activeIndex, !lines.isEmpty else { return [] }
        let low = max(0, activeIndex - radius)
        let high = min(lines.count - 1, activeIndex + radius)
        guard low <= high else { return [] }
        return (low ... high).map { WindowEntry(id: $0, line: lines[$0], isActive: $0 == activeIndex) }
    }

    /// LRCLIB's synced format: `[mm:ss.xx]text` per line. Metadata tags
    /// (`[ar:...]`, `[ti:...]`) and blank lines are skipped rather than
    /// erroring — LRC is a loose format in practice, and a file with a few
    /// tags at the top is the common case, not an edge one.
    static func parseLRC(_ raw: String) -> TrackLyrics {
        var lines: [LyricLine] = []
        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            guard rawLine.hasPrefix("["), let closeIndex = rawLine.firstIndex(of: "]") else { continue }
            let timestamp = rawLine[rawLine.index(after: rawLine.startIndex) ..< closeIndex]
            let text = rawLine[rawLine.index(after: closeIndex)...].trimmingCharacters(in: .whitespaces)
            guard let time = parseTimestamp(timestamp), !text.isEmpty else { continue }
            lines.append(LyricLine(time: time, text: text))
        }
        return TrackLyrics(lines: lines.sorted { $0.time < $1.time })
    }

    /// "mm:ss.xx". A metadata tag's contents (`ar:Some Artist`) fail the
    /// two-numeric-parts split or the `Double` parse and are dropped, which
    /// is what lets `parseLRC` skip them without recognising tags by name.
    private static func parseTimestamp(_ raw: Substring) -> TimeInterval? {
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]) else { return nil }
        return minutes * 60 + seconds
    }
}
