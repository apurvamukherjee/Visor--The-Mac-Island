import Foundation
import SQLite3

/// Reads today's token usage out of Codex CLI's own state database.
///
/// Codex does not keep JSONL transcripts the way Claude Code does — it keeps
/// SQLite at `~/.codex/state_5.sqlite`, in WAL mode, with a `threads` table
/// carrying a `tokens_used` column. Schema read off the real file before this
/// was written; `codex-cli 0.154.0`.
///
/// Opened **read-only**, and never written to. WAL means this does not block
/// Codex's own writer and Codex does not block us — but a read-only
/// connection to a WAL database still needs to map the `-shm` file, which is
/// why this needs the containing directory to be writable. It is: Visor runs
/// unsandboxed (App Sandbox is off so the media adapter can spawn), and the
/// directory is the user's own.
///
/// **One honest imprecision:** `tokens_used` is a running per-thread total,
/// and the schema has no per-day breakdown. A thread started yesterday and
/// continued today therefore contributes all of its tokens, not just today's.
/// Threads are short enough in practice that this is the closest figure
/// available without Codex writing one, and inventing a proration would be a
/// guess dressed as precision.
struct CodexUsageReader {
    private let databaseURL: URL
    private let calendar: Calendar

    init(databaseURL: URL = CodexUsageReader.defaultDatabaseURL, calendar: Calendar = .current) {
        self.databaseURL = databaseURL
        self.calendar = calendar
    }

    static var defaultDatabaseURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".codex/state_5.sqlite")
    }

    /// Milliseconds since the epoch at the start of the local day — the unit
    /// `threads.updated_at_ms` is in.
    static func startOfDayMilliseconds(for date: Date, calendar: Calendar) -> Int64 {
        Int64(calendar.startOfDay(for: date).timeIntervalSince1970 * 1000)
    }

    /// Today's total, or 0 when Codex is not installed, has never run, or the
    /// database cannot be opened. A tracker that cannot read one of its two
    /// sources shows a zero for it; it does not fail.
    func refresh(now: Date = .now) -> Int {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return 0 }

        var database: OpaquePointer?
        let opened = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(database) }
        guard opened == SQLITE_OK, let database else {
            Log.aiUsage.notice("Codex database unavailable: \(opened)")
            return 0
        }
        // Codex is mid-write often enough that a busy return is normal rather
        // than exceptional. Wait briefly, then give up and keep the previous
        // figure until the next event — never spin.
        sqlite3_busy_timeout(database, 50)

        // `updated_at_ms` is filled by a trigger and can be null on rows
        // written before that migration, so fall back to the seconds column.
        let sql = """
        SELECT COALESCE(SUM(tokens_used), 0) FROM threads
        WHERE COALESCE(updated_at_ms, updated_at * 1000) >= ?
        """
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            Log.aiUsage.notice("Codex usage query failed to prepare")
            return 0
        }
        sqlite3_bind_int64(statement, 1, Self.startOfDayMilliseconds(for: now, calendar: calendar))
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
    }
}
