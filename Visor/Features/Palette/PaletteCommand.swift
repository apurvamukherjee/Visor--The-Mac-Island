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
    case forceQuitFrontmost
    case openActivityMonitor
    /// Ten fixed slots rather than an open-ended list: each is a user-named,
    /// user-populated set of apps (`LaunchGroup`), but the *slot* is a plain
    /// `PaletteCommandID` case like every other command, so it needs no new
    /// dispatch mechanism, no new shortcut-binding code, and stays covered
    /// by `PaletteDispatchTests.everyCommandHasAnAction`. An empty slot is
    /// simply not offered — see `Availability.whileGroupConfigured`.
    case launchGroup1
    case launchGroup2
    case launchGroup3
    case launchGroup4
    case launchGroup5
    case launchGroup6
    case launchGroup7
    case launchGroup8
    case launchGroup9
    case launchGroup10
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
    /// The app a force quit would end, by name — nil when there is none, and
    /// that nil is also what keeps the row out of the palette. Carried as the
    /// name rather than a flag so the row can say which app it means: one
    /// `NSWorkspace` read answers both questions.
    var forceQuitTargetName: String?
    /// Which launch-group slots have a name and at least one app. A slot
    /// with neither is not "empty content", it is an absent command.
    var configuredLaunchGroups: Set<PaletteCommandID> = []
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
    enum Availability: Sendable, Equatable {
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
        /// Nothing to quit when the frontmost app is Visor itself or the
        /// Finder, which is the only time this is false.
        case whileForceQuitTargetExists
        /// The associated id is the slot's own — each launch-group command
        /// checks only its own membership in `configuredLaunchGroups`.
        case whileGroupConfigured(PaletteCommandID)

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
            case .whileForceQuitTargetExists: context.forceQuitTargetName != nil
            case let .whileGroupConfigured(id): context.configuredLaunchGroups.contains(id)
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
        ),
        PaletteCommand(
            id: .forceQuitFrontmost,
            // Retitled with the real app's name in
            // `NotchStore.availablePaletteCommands`; this placeholder is only
            // ever seen if that lookup comes back empty, which is also when
            // the row is gated out.
            title: "Force Quit Frontmost App",
            symbol: "xmark.octagon.fill",
            keywords: ["kill", "unresponsive", "frozen", "beachball", "stuck"],
            availability: .whileForceQuitTargetExists
        ),
        PaletteCommand(
            id: .openActivityMonitor,
            title: "Open Activity Monitor",
            symbol: "chart.bar.xaxis",
            keywords: ["force quit", "processes", "cpu", "memory", "task manager"]
        )
    ] + launchGroupSlots

    /// Placeholder title and no keywords: an unconfigured slot never reaches
    /// the palette (see `Availability.whileGroupConfigured`), and a
    /// configured one is retitled with the user's own name and app list by
    /// `NotchStore.availablePaletteCommands` before it is ever shown.
    private static let launchGroupSlots: [PaletteCommand] = [
        PaletteCommandID.launchGroup1, .launchGroup2, .launchGroup3, .launchGroup4, .launchGroup5,
        .launchGroup6, .launchGroup7, .launchGroup8, .launchGroup9, .launchGroup10
    ].enumerated().map { index, id in
        PaletteCommand(
            id: id,
            title: "Launch Group \(index + 1)",
            symbol: "bolt.fill",
            availability: .whileGroupConfigured(id)
        )
    }
}

extension PaletteCommand {
    /// A copy with the display swapped for a launch group's own name and
    /// apps. The identifier and availability stay put — only what the row
    /// says about itself changes.
    func retitled(_ title: String, keywords: [String]) -> PaletteCommand {
        PaletteCommand(id: id, title: title, symbol: symbol, keywords: keywords, availability: availability)
    }
}

extension PaletteCommand {
    /// Only what can actually do something right now. Pure so the gating is
    /// pinned by a test rather than discovered by finding a dead row.
    static func available(_ commands: [PaletteCommand], in context: PaletteContext) -> [PaletteCommand] {
        commands.filter { $0.availability.isSatisfied(by: context) }
    }
}
