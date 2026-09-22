import Foundation

/// Which coding agent a figure belongs to. Two, deliberately: Claude Code and
/// Codex are what is actually installed here. Cursor was in the original
/// sketch and is not shipped — it would be a third reader for a tool this
/// machine does not run.
enum AIUsageTool: String, CaseIterable, Sendable {
    case claude
    case codex

    var title: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        }
    }

    /// Asset-catalogue name. Both marks are the vendors' own, bundled rather
    /// than drawn: there is no SF Symbol for either.
    var assetName: String {
        switch self {
        case .claude: "ClaudeMark"
        case .codex: "CodexMark"
        }
    }
}

/// Tokens used today, per tool. Whole-day totals in the local calendar, not a
/// rolling window: "today" is the only boundary anyone reasons about, and a
/// rolling 24h figure that silently drops this morning's work reads as a bug.
struct AIUsageSnapshot: Equatable, Sendable {
    var claudeTokens = 0
    var codexTokens = 0

    static let empty = AIUsageSnapshot()

    func tokens(for tool: AIUsageTool) -> Int {
        switch tool {
        case .claude: claudeTokens
        case .codex: codexTokens
        }
    }

    var isEmpty: Bool {
        claudeTokens == 0 && codexTokens == 0
    }
}

/// How a token count is written in a badge barely wider than the numbers in
/// it. Pure, so the rounding is pinned by a test rather than eyeballed at
/// 11pt.
enum AIUsageFormat {
    static func short(_ tokens: Int) -> String {
        switch tokens {
        case ..<1000:
            "\(tokens)"
        case ..<1_000_000:
            "\(rounded(Double(tokens) / 1000))k"
        default:
            "\(rounded(Double(tokens) / 1_000_000))M"
        }
    }

    /// One decimal below 10, none above: "9.4k" then "12k". Two characters of
    /// precision is all the badge has room for, and 12.4k against 12k is not
    /// a distinction anyone acts on.
    private static func rounded(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f", value) : String(format: "%.0f", value)
    }

    /// Progress toward a budget the user set themselves. Nil when no budget
    /// is set, which is the default — there is no way to read the real plan
    /// limit off this machine, so the bar is only ever against your own
    /// target, never a guess at Anthropic's or OpenAI's.
    static func percentage(tokens: Int, budget: Int) -> Int? {
        guard budget > 0 else { return nil }
        return Int((Double(tokens) / Double(budget) * 100).rounded())
    }
}
