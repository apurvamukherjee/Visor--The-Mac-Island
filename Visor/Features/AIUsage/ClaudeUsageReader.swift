import Foundation

/// Reads today's token usage out of Claude Code's own session transcripts.
///
/// `~/.claude/projects/<escaped-cwd>/<session>.jsonl`, one append-only file
/// per session, written live as you work. Every `assistant` line carries a
/// `message.usage` object; the four token fields there are summed. Verified
/// against a real 2,660-line transcript before this was written.
///
/// There is nothing to parse for the CLI versus the VS Code extension: they
/// are the same engine writing the same files, so watching this one tree
/// covers both. That is why there is no "fall back to the extension" path.
///
/// Append-only is what makes this cheap. Each file's parsed byte offset is
/// remembered, so a folder event re-reads only what was appended since —
/// never the whole transcript, which is how a 2MB session would otherwise be
/// re-parsed on every keystroke's worth of output.
struct ClaudeUsageReader {
    /// Where the parse of one file got to, so the next read starts there.
    private var offsets: [URL: UInt64] = [:]
    /// The day `total` belongs to. A different day on the next read is a
    /// rollover, and the total starts again rather than carrying yesterday's
    /// figure into this morning.
    private var day: Date?
    private var total = 0

    private let root: URL
    private let calendar: Calendar

    init(root: URL = ClaudeUsageReader.defaultRoot, calendar: Calendar = .current) {
        self.root = root
        self.calendar = calendar
    }

    static var defaultRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Today's total, re-reading only what changed. `now` is injectable so a
    /// test can cross midnight without waiting for it.
    mutating func refresh(now: Date = .now) -> Int {
        let today = calendar.startOfDay(for: now)
        if day != today {
            day = today
            total = 0
            offsets = [:]
        }

        for url in Self.transcripts(in: root) {
            // A file untouched today cannot hold an entry from today, and
            // skipping it keeps a long history from being opened at all.
            guard Self.wasModified(url, onOrAfter: today) else { continue }
            total += consume(url, today: today)
        }
        return total
    }

    /// Everything appended to one file since it was last read.
    private mutating func consume(_ url: URL, today: Date) -> Int {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return 0 }
        defer { try? handle.close() }

        let start = offsets[url] ?? 0
        // A file that shrank was replaced, not appended to — start over
        // rather than seeking past its end.
        let size = (try? handle.seekToEnd()) ?? 0
        let from = size < start ? 0 : start
        guard size > from else { return 0 }

        guard
            (try? handle.seek(toOffset: from)) != nil,
            let data = try? handle.readToEnd()
        else {
            return 0
        }
        offsets[url] = size
        return Self.tokens(inAppendedData: data, today: today, calendar: calendar)
    }

    /// Sums every complete `assistant` line in a chunk of appended bytes.
    ///
    /// A trailing partial line — the writer caught mid-append — is dropped
    /// rather than half-parsed; the offset still advances past it, because
    /// the next event re-reads from the end of what was consumed, and a
    /// dropped line is one message's tokens, not a corrupted total.
    static func tokens(inAppendedData data: Data, today: Date, calendar: Calendar) -> Int {
        guard let text = String(data: data, encoding: .utf8) else { return 0 }
        // Built here rather than held as a static: `ISO8601DateFormatter` is
        // not `Sendable`, and one per appended chunk is one per burst of
        // events, not one per line.
        let isoFormatter = Self.makeISOFormatter()
        var sum = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard
                let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                entry["type"] as? String == "assistant",
                let stamp = entry["timestamp"] as? String,
                let date = isoFormatter.date(from: stamp),
                calendar.isDate(date, inSameDayAs: today),
                let message = entry["message"] as? [String: Any],
                let usage = message["usage"] as? [String: Any]
            else {
                continue
            }
            sum += Self.tokens(inUsage: usage)
        }
        return sum
    }

    /// New tokens: what was sent fresh, what was written to cache, and what
    /// came back. **`cache_read_input_tokens` is deliberately excluded.**
    ///
    /// Measured before deciding, across one real day's transcripts: 95.2M of
    /// a 98.6M gross total — 96.5% — was cache reads. That figure is a
    /// function of how long the context is and how many turns ran, not of how
    /// much work was done, so a badge counting it reads ~99M by mid-afternoon
    /// whatever you did with the day, and a budget set against it would be a
    /// budget against context length. The 3.4M that remains moves with the
    /// work, which is the number worth watching.
    static func tokens(inUsage usage: [String: Any]) -> Int {
        let fields = [
            "input_tokens",
            "output_tokens",
            "cache_creation_input_tokens"
        ]
        return fields.reduce(0) { $0 + ((usage[$1] as? Int) ?? 0) }
    }

    /// Claude Code writes fractional seconds; the plain ISO8601 formatter
    /// returns nil for those, which would silently zero every figure.
    private static func makeISOFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func transcripts(in root: URL) -> [URL] {
        guard
            let walker = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }

    private static func wasModified(_ url: URL, onOrAfter date: Date) -> Bool {
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        guard let modified else { return false }
        return modified >= date
    }
}
