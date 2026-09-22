import Foundation
import Testing
@testable import Visor

/// The badge is 11pt of room for a number that ranges over six orders of
/// magnitude, so how it rounds is worth pinning.
@Suite("AI usage formatting")
struct AIUsageFormatTests {
    @Test("Counts shorten as they grow")
    func shortening() {
        #expect(AIUsageFormat.short(0) == "0")
        #expect(AIUsageFormat.short(999) == "999")
        #expect(AIUsageFormat.short(1000) == "1.0k")
        #expect(AIUsageFormat.short(9499) == "9.5k")
        // Past 10 the decimal is dropped: the badge has no room for it and
        // 12.4k against 12k is not a distinction anyone acts on.
        #expect(AIUsageFormat.short(12400) == "12k")
        #expect(AIUsageFormat.short(1_240_000) == "1.2M")
        #expect(AIUsageFormat.short(24_000_000) == "24M")
    }

    /// No budget means no percentage — never a division by zero, and never a
    /// made-up denominator standing in for the real plan limit.
    @Test("A percentage needs a budget the user actually set")
    func percentageNeedsABudget() {
        #expect(AIUsageFormat.percentage(tokens: 500, budget: 0) == nil)
        #expect(AIUsageFormat.percentage(tokens: 500, budget: -1) == nil)
        #expect(AIUsageFormat.percentage(tokens: 500, budget: 1000) == 50)
        #expect(AIUsageFormat.percentage(tokens: 1500, budget: 1000) == 150)
    }
}

/// The transcript parsing, against the shape a real Claude Code session file
/// actually has — every field name here was read off one before it was
/// written down.
@Suite("Claude usage parsing")
struct ClaudeUsageParsingTests {
    private let calendar = Calendar(identifier: .gregorian)

    private func line(type: String, timestamp: String, usage: [String: Int]) -> String {
        let entry: [String: Any] = [
            "type": type,
            "timestamp": timestamp,
            "message": ["model": "claude-opus-5", "usage": usage]
        ]
        let data = try? JSONSerialization.data(withJSONObject: entry)
        return String(data: data ?? Data(), encoding: .utf8) ?? ""
    }

    /// Cache *reads* are excluded on purpose — measured at 96.5% of a real
    /// day's gross total, which makes them a measure of context length rather
    /// than of work. This is the seam that decision lives on, so it is pinned
    /// rather than remembered.
    @Test("New tokens count; cache reads do not")
    func cacheReadsAreExcluded() {
        let usage: [String: Any] = [
            "input_tokens": 2,
            "output_tokens": 23,
            "cache_creation_input_tokens": 28113,
            "cache_read_input_tokens": 35208
        ]
        #expect(ClaudeUsageReader.tokens(inUsage: usage) == 28138)
    }

    @Test("A missing field is zero, not a crash")
    func missingFieldsAreZero() {
        #expect(ClaudeUsageReader.tokens(inUsage: [:]) == 0)
        #expect(ClaudeUsageReader.tokens(inUsage: ["output_tokens": 7]) == 7)
    }

    @Test("Only today's assistant lines are summed")
    func filtersByTypeAndDay() {
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_789_000_000))
        let todayStamp = ISO8601DateFormatter.visorTest.string(from: today.addingTimeInterval(3600))
        let yesterdayStamp = ISO8601DateFormatter.visorTest.string(from: today.addingTimeInterval(-3600))

        let text = [
            line(type: "assistant", timestamp: todayStamp, usage: ["input_tokens": 100]),
            // A user line carries no usage and must not be counted.
            line(type: "user", timestamp: todayStamp, usage: ["input_tokens": 999]),
            // Yesterday's work belongs to yesterday.
            line(type: "assistant", timestamp: yesterdayStamp, usage: ["input_tokens": 555]),
            line(type: "assistant", timestamp: todayStamp, usage: ["output_tokens": 40])
        ].joined(separator: "\n")

        let total = ClaudeUsageReader.tokens(
            inAppendedData: Data(text.utf8), today: today, calendar: calendar
        )
        #expect(total == 140)
    }

    /// The writer is appending while this reads, so the last line of a chunk
    /// is routinely half-written. It must be skipped, not half-counted.
    @Test("A truncated trailing line is dropped, not half-parsed")
    func truncatedLineIsDropped() {
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_789_000_000))
        let stamp = ISO8601DateFormatter.visorTest.string(from: today.addingTimeInterval(60))
        let complete = line(type: "assistant", timestamp: stamp, usage: ["input_tokens": 10])
        let text = complete + "\n" + String(complete.prefix(complete.count / 2))

        let total = ClaudeUsageReader.tokens(
            inAppendedData: Data(text.utf8), today: today, calendar: calendar
        )
        #expect(total == 10)
    }

    @Test("Junk in the file is skipped rather than fatal")
    func junkIsSkipped() {
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_789_000_000))
        let text = "not json at all\n{}\n{\"type\":\"assistant\"}\n"
        let total = ClaudeUsageReader.tokens(
            inAppendedData: Data(text.utf8), today: today, calendar: calendar
        )
        #expect(total == 0)
    }
}

/// Codex stores milliseconds; getting the unit wrong would return either
/// everything ever or nothing at all.
@Suite("Codex usage bounds")
struct CodexUsageReaderTests {
    @Test("The day starts at local midnight, in milliseconds")
    func startOfDayIsMilliseconds() {
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(identifier: "UTC") else { fatalError("UTC unavailable") }
        calendar.timeZone = utc

        let noon = Date(timeIntervalSince1970: 1_789_041_600)
        let start = CodexUsageReader.startOfDayMilliseconds(for: noon, calendar: calendar)

        #expect(start % 1000 == 0)
        #expect(start <= Int64(noon.timeIntervalSince1970 * 1000))
        // Within the same day, never more than 24h back.
        #expect(Int64(noon.timeIntervalSince1970 * 1000) - start < 86_400_000)
    }

    /// Codex may never have run. That is a zero, not a failure.
    @Test("A database that is not there reads as zero")
    func missingDatabaseIsZero() {
        let reader = CodexUsageReader(
            databaseURL: URL(fileURLWithPath: "/nonexistent/visor-test/state.sqlite")
        )
        #expect(reader.refresh() == 0)
    }
}

/// The snapshot the badge draws from.
@Suite("AI usage snapshot")
struct AIUsageSnapshotTests {
    @Test("Empty means nothing used today by either tool")
    func emptiness() {
        #expect(AIUsageSnapshot.empty.isEmpty)
        #expect(!AIUsageSnapshot(claudeTokens: 1).isEmpty)
        #expect(!AIUsageSnapshot(codexTokens: 1).isEmpty)
    }

    @Test("Each tool reads its own figure")
    func perToolLookup() {
        let snapshot = AIUsageSnapshot(claudeTokens: 10, codexTokens: 20)
        #expect(snapshot.tokens(for: .claude) == 10)
        #expect(snapshot.tokens(for: .codex) == 20)
    }

    /// Every tool needs a bundled mark and its own budget key, or the badge
    /// draws a blank square and two tools share one target.
    @Test("Every tool is fully described")
    func toolsAreComplete() {
        let keys = AIUsageTool.allCases.map(Preferences.dailyTokenBudgetKey(for:))
        #expect(Set(keys).count == AIUsageTool.allCases.count)
        for tool in AIUsageTool.allCases {
            #expect(!tool.assetName.isEmpty)
            #expect(!tool.title.isEmpty)
        }
    }
}

extension ISO8601DateFormatter {
    /// Matches what Claude Code writes: internet date time with fractional
    /// seconds. A function rather than a stored static — the formatter is not
    /// `Sendable`, which under strict concurrency a shared one would have to
    /// be.
    static var visorTest: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
