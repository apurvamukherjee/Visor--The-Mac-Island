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
    case keepAwake
    case lockScreen
    case sleepDisplay
    case toggleDarkMode
    case toggleMicrophone
    case takeScreenshot
    case copyTrack
    case searchTrack
    case openDownloads
    case timerFive
    case timerTwentyFive
    case switchAudioOutput
    case toggleIslandHidden
    case quickNote
    case compressShelfFile
    case expandShelfFile
    case convertShelfImage
}

/// What the machine can do right now. Gathered once when the palette opens,
/// so a row is never offered for something that would quietly fail — the
/// rule `MusicSeekRow` states: a dead control is worse than an absent one.
struct PaletteContext: Equatable, Sendable {
    var hasTrack = false
    var hasVolume = false
    var hasMicrophone = false
    /// One output device is not a choice, so there is nothing to switch to.
    var hasMultipleOutputs = false
    var hasShelfFile = false
    var hasShelfArchive = false
    var hasShelfImage = false
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
        /// Not every input device has a mute — the probe found a Continuity
        /// iPhone microphone with none at all.
        case whileMicrophoneExists
        case whileMultipleOutputs
        case whileShelfHasFile
        case whileShelfHasArchive
        case whileShelfHasImage

        func isSatisfied(by context: PaletteContext) -> Bool {
            switch self {
            case .always: true
            case .whilePlaying: context.hasTrack
            case .whileVolumeExists: context.hasVolume
            case .whileMicrophoneExists: context.hasMicrophone
            case .whileMultipleOutputs: context.hasMultipleOutputs
            case .whileShelfHasFile: context.hasShelfFile
            case .whileShelfHasArchive: context.hasShelfArchive
            case .whileShelfHasImage: context.hasShelfImage
            }
        }
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
            id: .copyTrack,
            title: "Copy Track Name",
            symbol: "doc.on.clipboard",
            keywords: ["clipboard", "share", "title"],
            availability: .whilePlaying
        ),
        PaletteCommand(
            id: .searchTrack,
            title: "Find Track on YouTube",
            symbol: "magnifyingglass",
            keywords: ["search", "video", "web"],
            availability: .whilePlaying
        ),
        PaletteCommand(
            id: .keepAwake,
            title: "Keep Awake",
            symbol: "cup.and.saucer.fill",
            keywords: ["caffeine", "sleep", "insomnia", "stay"]
        ),
        PaletteCommand(
            id: .toggleMicrophone,
            title: "Mute or Unmute Microphone",
            symbol: "mic.slash.fill",
            keywords: ["mic", "silence", "meeting", "call"],
            availability: .whileMicrophoneExists
        ),
        PaletteCommand(
            id: .lockScreen,
            title: "Lock Screen",
            symbol: "lock.fill",
            keywords: ["away", "secure"]
        ),
        PaletteCommand(
            id: .sleepDisplay,
            title: "Sleep Display",
            symbol: "moon.zzz.fill",
            // Not "dark": that word belongs to Toggle Dark Mode, and the two
            // tied on score so the list order decided — which is exactly the
            // kind of coin-toss a palette must not make.
            keywords: ["screen", "off", "blank"]
        ),
        PaletteCommand(
            id: .toggleDarkMode,
            title: "Toggle Dark Mode",
            symbol: "circle.lefthalf.filled",
            keywords: ["appearance", "light", "theme"]
        ),
        PaletteCommand(
            id: .takeScreenshot,
            title: "Take Screenshot",
            symbol: "camera.viewfinder",
            keywords: ["capture", "grab", "shot"]
        ),
        PaletteCommand(
            id: .timerFive,
            title: "Start 5-Minute Timer",
            symbol: "timer",
            keywords: ["countdown", "break", "tea"]
        ),
        PaletteCommand(
            id: .timerTwentyFive,
            title: "Start 25-Minute Timer",
            symbol: "timer",
            keywords: ["pomodoro", "focus", "countdown", "work"]
        ),
        PaletteCommand(
            id: .switchAudioOutput,
            title: "Switch Audio Output",
            symbol: "hifispeaker.fill",
            keywords: ["speaker", "headphones", "airpods", "sound", "device"],
            availability: .whileMultipleOutputs
        ),
        PaletteCommand(
            id: .quickNote,
            title: "New Quick Note",
            symbol: "square.and.pencil",
            keywords: ["write", "jot", "scratch", "memo"]
        ),
        PaletteCommand(
            id: .compressShelfFile,
            title: "Compress Shelf File",
            symbol: "archivebox.fill",
            keywords: ["zip", "archive", "shrink"],
            availability: .whileShelfHasFile
        ),
        PaletteCommand(
            id: .expandShelfFile,
            title: "Expand Shelf File",
            symbol: "arrow.up.bin.fill",
            keywords: ["unzip", "extract", "open archive"],
            availability: .whileShelfHasArchive
        ),
        PaletteCommand(
            id: .convertShelfImage,
            title: "Convert Shelf Image to JPEG",
            symbol: "photo.fill",
            keywords: ["jpg", "compress", "convert", "image"],
            availability: .whileShelfHasImage
        ),
        PaletteCommand(
            id: .toggleIslandHidden,
            title: "Hide or Show the Island",
            symbol: "eye.slash.fill",
            keywords: ["hide", "show", "away", "disappear"]
        ),
        PaletteCommand(
            id: .openDownloads,
            title: "Open Downloads",
            symbol: "folder.fill",
            keywords: ["finder", "files"]
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
    static func available(_ commands: [PaletteCommand], in context: PaletteContext) -> [PaletteCommand] {
        commands.filter { $0.availability.isSatisfied(by: context) }
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
