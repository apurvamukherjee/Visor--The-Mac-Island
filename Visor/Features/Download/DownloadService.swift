import Foundation

/// Shows downloads as they arrive in `~/Downloads`.
///
/// A `DispatchSource` on the folder, the same mechanism `ScreenshotService`
/// uses: the kernel wakes us when the folder changes and nothing runs in
/// between. The reference implementation this is ported from also ran a 1s
/// rescan timer to animate progress smoothly — that is the polling loop the
/// power rules forbid, and it is not needed: a download in flight rewrites
/// its own file continuously, so the folder events arrive on their own.
///
/// Only `~/Downloads` is watched. The reference watched Desktop, Documents,
/// Movies, Music and Pictures too, each of which is its own TCC prompt on a
/// modern macOS, for files that are rarely downloads.
@MainActor
final class DownloadService: NotchService {
    private let store: NotchStore
    private var source: DispatchSourceFileSystemObject?
    private var debounceTask: Task<Void, Never>?
    private var clearTask: Task<Void, Never>?

    /// A single download write produces a burst of directory events.
    private static let debounce: Duration = .milliseconds(200)
    /// A plain file with no progress attribute counts as a download only
    /// while it is this fresh — otherwise every file already in the folder
    /// would read as one every time the folder changed.
    private nonisolated static let recentWindow: TimeInterval = 10

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        guard source == nil else { return }
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        guard let folder else {
            Log.download.notice("No Downloads folder; download activity disabled")
            return
        }
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Log.download.notice("Downloads folder unavailable at \(folder.path, privacy: .public)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.folderChanged(folder) }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        clearTask?.cancel()
        clearTask = nil
        source?.cancel()
        source = nil
        store.downloads = []
        store.deactivate(.download)
    }

    private func folderChanged(_ folder: URL) {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self?.rescan(folder)
        }
    }

    private func rescan(_ folder: URL) {
        let items = Self.inFlight(in: folder)
        guard items != store.downloads else { return }
        store.downloads = items
        if items.isEmpty {
            // Nothing in flight: the last one finished. Hold it a beat so a
            // download that completes the instant it starts is still seen.
            scheduleClear()
        } else {
            clearTask?.cancel()
            clearTask = nil
            store.activate(.download)
        }
    }

    private func scheduleClear() {
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Dwell.downloadLinger, tolerance: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.store.deactivate(.download)
        }
    }

    /// Everything in the folder that is currently arriving. Temporary files
    /// always count; a plain file counts only while it is both recently
    /// modified and still reporting progress, which is what a download
    /// written straight to its final name looks like.
    private nonisolated static func inFlight(in folder: URL) -> [DownloadItem] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }
        let now = Date.now
        return urls.compactMap { url -> DownloadItem? in
            let name = url.lastPathComponent
            let isTemporary = DownloadFilter.isTemporary(name)
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            let progress = progressAttribute(for: url)
            if !isTemporary {
                guard
                    values.isRegularFile == true,
                    progress != nil,
                    let modified = values.contentModificationDate,
                    now.timeIntervalSince(modified) <= recentWindow
                else {
                    return nil
                }
            }
            return DownloadItem(
                url: url,
                displayName: DownloadFilter.displayName(for: name),
                byteCount: Int64(values.fileSize ?? 0),
                progress: progress
            )
        }
        .sorted { $0.displayName < $1.displayName }
    }

    /// The public attribute Safari, WebKit and most download managers write
    /// onto a file in flight. Nothing else here is scraped — the reference's
    /// Chromium History-database reader was dropped rather than ported: an
    /// undocumented per-browser SQLite schema for one more progress bar.
    private nonisolated static func progressAttribute(for url: URL) -> Double? {
        let name = "com.apple.progress.fractionCompleted"
        return url.withUnsafeFileSystemRepresentation { path -> Double? in
            guard let path else { return nil }
            let length = getxattr(path, name, nil, 0, 0, 0)
            guard length > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: length)
            let read = getxattr(path, name, &buffer, length, 0, 0)
            guard read > 0 else { return nil }
            // Failable rather than lossy: bytes that are not valid UTF-8
            // are not a progress figure, and `String(decoding:)` would turn
            // them into replacement characters that then parse as nil
            // anyway, one step later.
            guard let text = String(bytes: buffer[0 ..< read], encoding: .utf8) else { return nil }
            return DownloadFilter.parseProgress(text)
        }
    }
}
