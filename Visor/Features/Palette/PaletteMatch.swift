import Foundation

/// Fuzzy subsequence matching, scored so that the obvious answer comes
/// first: "next" must put Next Track above Previous Track even though both
/// contain those letters in order.
enum PaletteMatch {
    /// `declaredAt` is the tiebreak: equal scores keep the order the list
    /// was written in, so an ambiguous query does not shuffle rows under
    /// the cursor between keystrokes.
    private struct Ranked {
        let command: PaletteCommand
        let score: Int
        let declaredAt: Int
    }

    /// Awarded when a matched character starts a word. The reason "ot"
    /// finds "Open Settings" — and the reason typing a word's initials
    /// works at all.
    private static let wordStartBonus = 8
    /// Consecutive matches compound, so a literal substring beats the same
    /// letters scattered across the title.
    private static let streakWeight = 2

    /// nil when `query` is not a subsequence of `candidate`.
    static func score(_ candidate: String, query: String) -> Int? {
        guard !query.isEmpty else { return 0 }
        let haystack = Array(candidate.lowercased())
        let needle = Array(query.lowercased())
        var hay = 0
        var need = 0
        var total = 0
        var streak = 0

        while hay < haystack.count, need < needle.count {
            if haystack[hay] == needle[need] {
                streak += 1
                total += streak * streakWeight
                if hay == 0 || haystack[hay - 1] == " " {
                    total += wordStartBonus
                }
                need += 1
            } else {
                streak = 0
            }
            hay += 1
        }

        return need == needle.count ? total : nil
    }

    /// Best score across the title and every keyword, highest first. Ties
    /// keep the declared order, so an empty or ambiguous query leaves the
    /// list where the author put it rather than shuffling under the cursor.
    static func filter(_ commands: [PaletteCommand], query: String) -> [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return commands }

        return commands.enumerated()
            .compactMap { index, command -> Ranked? in
                let best = ([command.title] + command.keywords)
                    .compactMap { score($0, query: trimmed) }
                    .max()
                return best.map { Ranked(command: command, score: $0, declaredAt: index) }
            }
            .sorted { lhs, rhs in
                lhs.score == rhs.score ? lhs.declaredAt < rhs.declaredAt : lhs.score > rhs.score
            }
            .map(\.command)
    }
}
