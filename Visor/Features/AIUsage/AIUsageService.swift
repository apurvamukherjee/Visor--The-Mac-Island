import Foundation

/// Keeps today's Claude Code and Codex token counts current.
///
/// Event-driven, like every other service here: nothing ticks, and between an
/// agent writing and the kernel waking us this runs no code at all.
///
/// **FSEvents, not a `DispatchSource`.** The other watchers in this codebase
/// (`DownloadService`, `ScreenshotService`) use a `DispatchSource` on one
/// folder, which only reports changes to that folder's own direct entries.
/// Claude's transcripts live a level deeper —
/// `~/.claude/projects/<project>/<session>.jsonl` — and appending to one does
/// not touch the folder above it, so a `DispatchSource` on `projects/` would
/// have sat silent through an entire session. FSEvents watches a tree.
///
/// One stream covers both tools. Its own `latency` does the coalescing a
/// debounce would otherwise have to: a model turn writes many times, and
/// re-reading once at the end of the burst is the whole point. The re-read is
/// cheap regardless — `ClaudeUsageReader` parses only bytes it has not seen.
@MainActor
final class AIUsageService: NotchService {
    private let store: NotchStore
    private var claude: ClaudeUsageReader
    private let codex: CodexUsageReader

    private var stream: FSEventStreamRef?
    private var defaultsObserver: NSObjectProtocol?

    /// Seconds FSEvents waits for a burst to settle before delivering it.
    /// Long enough to collapse a model turn's writes into one wake-up, short
    /// enough that the figure is current by the time you look at it.
    private static let latency: CFTimeInterval = 0.5

    init(
        store: NotchStore,
        claude: ClaudeUsageReader = ClaudeUsageReader(),
        codex: CodexUsageReader = CodexUsageReader()
    ) {
        self.store = store
        self.claude = claude
        self.codex = codex
    }

    func start() {
        // The watcher follows the setting rather than the launch: with the
        // feature off, nothing is opened and nothing is read.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.syncEnabled() }
        }
        syncEnabled()
    }

    func stop() {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
        defaultsObserver = nil
        teardown()
        store.aiUsage = .empty
        store.isUsageTracked = false
    }

    /// One switch, and it is the badge's. Paging is structural now, so it no
    /// longer implies the reader: the usage *screen* is only reachable while
    /// this is on (`availablePages`), because a screen of zeroes is worse than
    /// no screen and because reading two agents' transcripts is a thing to be
    /// asked for, not a side effect of a redesign.
    private func syncEnabled() {
        let wanted = NewFeatures.aiUsageTracker.isEnabled()
        store.isUsageTracked = wanted
        guard wanted != (stream != nil) else { return }
        if wanted {
            startWatching()
            refresh()
        } else {
            teardown()
            store.aiUsage = .empty
        }
    }

    /// Both roots on one stream. A path that does not exist yet is still
    /// watched — Codex may never have run, and FSEvents reports it once it
    /// appears rather than failing now.
    private func startWatching() {
        guard stream == nil else { return }
        let paths = [
            ClaudeUsageReader.defaultRoot.path,
            CodexUsageReader.defaultDatabaseURL.deletingLastPathComponent().path
        ] as CFArray

        // `self` travels as the stream's context rather than a capture: the
        // callback is a C function pointer and cannot close over anything.
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes
        )
        guard let created = FSEventStreamCreate(
            nil,
            { _, info, _, _, _, _ in
                guard let info else { return }
                let service = Unmanaged<AIUsageService>.fromOpaque(info).takeUnretainedValue()
                // The stream is dispatched on the main queue below, so this
                // is the main actor already and not a hop.
                MainActor.assumeIsolated { service.refresh() }
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            Self.latency,
            flags
        ) else {
            Log.aiUsage.error("Could not watch the agent folders; usage will not update")
            return
        }
        FSEventStreamSetDispatchQueue(created, .main)
        FSEventStreamStart(created)
        stream = created
    }

    private func teardown() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func refresh() {
        // `claude.context` is only valid after the refresh that reads it.
        let claudeTokens = claude.refresh()
        let snapshot = AIUsageSnapshot(
            claudeTokens: claudeTokens,
            codexTokens: codex.refresh(),
            claudeContext: claude.context
        )
        guard snapshot != store.aiUsage else { return }
        store.aiUsage = snapshot
    }
}
