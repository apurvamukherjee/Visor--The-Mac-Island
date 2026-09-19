import CoreGraphics
import Foundation
import ImageIO
import Observation

/// Catches screenshots as macOS writes them.
///
/// A `DispatchSource` on the screenshot folder's file descriptor means the
/// kernel wakes us only when that folder changes — no timer, no polling, and
/// nothing at all while the user isn't taking screenshots.
@MainActor
final class ScreenshotService: NotchService {
    private let store: NotchStore
    private var source: DispatchSourceFileSystemObject?
    private var debounceTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var lastSeen = Date.now

    /// macOS writes the file and then renames it, so one screenshot produces a
    /// burst of directory events. Coalesce them.
    private static let debounce: Duration = .milliseconds(150)
    private static let visibleSeconds: TimeInterval = 60
    /// While the island is open the user is looking at the catch, so the
    /// countdown restarts instead of pulling it out from under them.
    private static let hoverGrace: Duration = .seconds(2)
    private nonisolated static let thumbnailPixels = 256

    init(store: NotchStore) {
        self.store = store
    }

    func start() {
        guard source == nil else { return }
        let folder = ScreenshotLocation.current()
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            Log.screenshot.notice("Screenshot folder unavailable at \(folder.path, privacy: .public)")
            return
        }
        lastSeen = .now
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.folderChanged() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
        store.screenshotCommands = NotchStore.ScreenshotCommands(
            adopt: { [weak self] url in self?.adopt(url) }
        )
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        dismissTask?.cancel()
        dismissTask = nil
        source?.cancel()
        source = nil
        store.screenshotCommands = nil
        store.clearShelf()
    }

    private func folderChanged() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.debounce)
            guard !Task.isCancelled else { return }
            self?.catchNewest()
        }
    }

    private func catchNewest() {
        let folder = ScreenshotLocation.current()
        guard let url = Self.newestImage(in: folder, after: lastSeen) else { return }
        guard url != store.shelf.first?.url else { return }
        lastSeen = .now

        present(url)
    }

    /// A file dragged onto the island. Same presentation as a screenshot the
    /// system just wrote — once it is in the notch there is no difference.
    func adopt(_ url: URL) {
        let isImage = (try? url.resourceValues(forKeys: [.contentTypeKey]))?
            .contentType?.conforms(to: .image) ?? false
        guard isImage else {
            Log.screenshot.notice("Ignoring dropped non-image")
            return
        }
        // A dropped file is usually older than the mark; move the mark past it
        // so the folder watcher doesn't re-announce it as a fresh capture.
        lastSeen = .now
        present(url)
    }

    private func present(_ url: URL) {
        Task { [weak self] in
            let thumbnail = await Self.thumbnail(for: url)
            guard let self, !Task.isCancelled else { return }
            store.addToShelf(ScreenshotCatch(url: url, thumbnail: thumbnail, caughtAt: .now))
            scheduleSweep()
        }
    }

    /// One task for the whole shelf, not one per catch: it sleeps until the
    /// oldest item is due, sweeps everything that has expired, then
    /// reschedules for whatever is next. If the island is open when the
    /// clock runs out nothing is pulled out from under the user — the sweep
    /// waits for the collapse instead. A re-check loop did this job by
    /// waking the CPU for as long as the pointer stayed on the island;
    /// observation costs nothing while idle.
    private func scheduleSweep() {
        dismissTask?.cancel()
        dismissTask = nil
        guard let oldest = store.shelf.map(\.caughtAt).min() else { return }
        let delay = max(0, oldest.addingTimeInterval(Self.visibleSeconds).timeIntervalSinceNow)
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            dismissTask = nil
            if store.state == .expanded {
                waitForCollapse()
            } else {
                sweep()
            }
        }
    }

    private func sweep() {
        let cutoff = Date.now.addingTimeInterval(-Self.visibleSeconds)
        for item in store.shelf where item.caughtAt <= cutoff {
            store.removeFromShelf(item)
        }
        scheduleSweep()
    }

    /// Fires once, when the island next leaves the expanded state.
    private func waitForCollapse() {
        withObservationTracking {
            _ = store.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.store.shelf.isEmpty else { return }
                guard self.store.state != .expanded else {
                    self.waitForCollapse()
                    return
                }
                self.dismissTask = Task { [weak self] in
                    try? await Task.sleep(for: Self.hoverGrace, tolerance: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    self?.sweep()
                }
            }
        }
    }

    private static func newestImage(in folder: URL, after mark: Date) -> URL? {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .contentTypeKey, .isRegularFileKey]
        guard
            let urls = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
        else {
            // Most often a TCC denial on Desktop/Documents/Downloads. The
            // feature goes quiet; nothing else is affected.
            Log.screenshot.notice("Screenshot folder unreadable at \(folder.path, privacy: .public)")
            return nil
        }
        let entries: [ScreenshotFilter.Entry] = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            guard values.isRegularFile == true else { return nil }
            return ScreenshotFilter.Entry(
                url: url,
                modified: values.contentModificationDate ?? .distantPast,
                isImage: values.contentType?.conforms(to: .image) ?? false
            )
        }
        return ScreenshotFilter.newest(in: entries, after: mark)
    }

    /// Off the main actor: a 6K screenshot is a large PNG, and ImageIO's
    /// thumbnail path still has to read it.
    private static func thumbnail(for url: URL) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: thumbnailPixels,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
    }
}
