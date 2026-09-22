import Foundation

/// What the palette can run.
///
/// The identifier is an enum rather than a closure on the struct, so the
/// list stays a plain value: the matching below is then pure, testable, and
/// says nothing about AppKit. `PaletteService` owns what each one does.
enum PaletteCommandID: String, CaseIterable, Sendable {
    case playPause
    case nextTrack
    case previousTrack
    case toggleMute
    case openSettings
    case replayWelcome
    case quit
}

struct PaletteCommand: Identifiable, Equatable, Sendable {
    let id: PaletteCommandID
    let title: String
    let symbol: String
    /// Words someone might type that are not in the title. "skip" for next,
    /// "prefs" for settings — the things a palette is judged on.
    let keywords: [String]

    /// Whether the command can do anything right now. A palette that lists
    /// "Next track" with nothing playing is offering a button that does
    /// nothing, which this codebase already decided is worse than an absent
    /// one (see `MusicSeekRow`).
    enum Availability: Sendable {
        case always
        case whilePlaying
        case whileVolumeExists
    }

    let availability: Availability

    init(
        id: PaletteCommandID,
        title: String,
        symbol: String,
        keywords: [String] = [],
        availability: Availability = .always
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.keywords = keywords
        self.availability = availability
    }

    static let all: [PaletteCommand] = [
        PaletteCommand(
            id: .playPause,
            title: "Play or Pause",
            symbol: "playpause.fill",
            keywords: ["music", "resume", "stop"],
            availability: .whilePlaying
        ),
        PaletteCommand(
            id: .nextTrack,
            title: "Next Track",
            symbol: "forward.end.fill",
            keywords: ["skip", "forward"],
            availability: .whilePlaying
        ),
        PaletteCommand(
            id: .previousTrack,
            title: "Previous Track",
            symbol: "backward.end.fill",
            keywords: ["back", "rewind"],
            availability: .whilePlaying
        ),
        PaletteCommand(
            id: .toggleMute,
            title: "Mute or Unmute",
            symbol: "speaker.slash.fill",
            keywords: ["volume", "silence"],
            availability: .whileVolumeExists
        ),
        PaletteCommand(
            id: .openSettings,
            title: "Open Settings",
            symbol: "gearshape.fill",
            keywords: ["preferences", "prefs", "options"]
        ),
        PaletteCommand(
            id: .replayWelcome,
            title: "Replay Welcome Tour",
            symbol: "sparkles",
            keywords: ["onboarding", "intro"]
        ),
        PaletteCommand(
            id: .quit,
            title: "Quit Visor",
            symbol: "power",
            keywords: ["exit", "close"]
        )
    ]
}

extension PaletteCommand {
    /// Only what can actually do something right now. Pure so the gating is
    /// pinned by a test rather than discovered by finding a dead row.
    static func available(_ commands: [PaletteCommand], hasTrack: Bool, hasVolume: Bool) -> [PaletteCommand] {
        commands.filter { command in
            switch command.availability {
            case .always: true
            case .whilePlaying: hasTrack
            case .whileVolumeExists: hasVolume
            }
        }
    }
}

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
