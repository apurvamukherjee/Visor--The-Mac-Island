import AppKit

/// Sends files dropped on the island via AirDrop.
///
/// Outgoing only. There is no public API that reports an *incoming* AirDrop
/// at all, so the reference's "bidirectional transfer tracking" was really
/// one direction plus a decorative ring; this ships the direction that works.
///
/// Files are copied into a temporary directory before sharing, exactly as the
/// reference does: `NSSharingService` reads them asynchronously and the
/// source may be a promise that goes away the moment the drag ends.
@MainActor
final class AirDropService: NSObject, NotchService {
    private let store: NotchStore
    private var sessions: [UUID: ShareSession] = [:]
    private var clearTask: Task<Void, Never>?

    init(store: NotchStore) {
        self.store = store
        super.init()
    }

    func start() {
        store.airDropCommands = NotchStore.AirDropCommands(
            send: { [weak self] urls in self?.send(urls) },
            dismiss: { [weak self] in self?.clear() }
        )
    }

    func stop() {
        clearTask?.cancel()
        clearTask = nil
        sessions.removeAll()
        store.airDropCommands = nil
        store.airDropTransfer = nil
        store.deactivate(.airDrop)
    }

    private func send(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let identifier = UUID()
        store.airDropTransfer = AirDropTransfer(
            id: identifier,
            fileNames: urls.map(\.lastPathComponent),
            status: .sending
        )
        store.activate(.airDrop)
        clearTask?.cancel()
        clearTask = nil

        Task { [weak self] in
            do {
                let staged = try await Self.stage(urls)
                self?.beginShare(identifier: identifier, urls: staged.urls, directory: staged.directory)
            } catch {
                self?.finish(identifier, status: .failed(error.localizedDescription))
            }
        }
    }

    private func beginShare(identifier: UUID, urls: [URL], directory: URL) {
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            finish(identifier, status: .failed("AirDrop isn't available on this Mac."))
            return
        }
        guard service.canPerform(withItems: urls) else {
            finish(identifier, status: .failed("These items can't be shared via AirDrop."))
            return
        }
        let session = ShareSession(directory: directory) { [weak self] status in
            self?.finish(identifier, status: status)
        }
        sessions[identifier] = session
        service.delegate = session
        // AirDrop's own picker is a panel belonging to this app, and an
        // accessory app is never frontmost — without this it opens behind
        // whatever the user was looking at.
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    private func finish(_ identifier: UUID, status: AirDropTransfer.Status) {
        sessions.removeValue(forKey: identifier)
        guard store.airDropTransfer?.id == identifier else { return }
        store.airDropTransfer?.status = status
        clearTask?.cancel()
        clearTask = Task { [weak self] in
            try? await Task.sleep(for: Dwell.airDropLinger, tolerance: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.clear()
        }
    }

    private func clear() {
        clearTask?.cancel()
        clearTask = nil
        store.airDropTransfer = nil
        store.deactivate(.airDrop)
    }

    /// Copies the dropped files somewhere they will still exist when the
    /// share service gets round to reading them, and hands back the directory
    /// so the session can delete it afterwards.
    private nonisolated static func stage(_ urls: [URL]) async throws -> (urls: [URL], directory: URL) {
        try await Task.detached(priority: .userInitiated) {
            let manager = FileManager.default
            let directory = manager.temporaryDirectory
                .appendingPathComponent("Visor/AirDrop/\(UUID().uuidString)", isDirectory: true)
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            var staged: [URL] = []
            for (index, source) in urls.enumerated() {
                var destination = directory.appendingPathComponent(source.lastPathComponent)
                // Two dropped files can share a name; the second would
                // otherwise fail the copy and take the whole send with it.
                if manager.fileExists(atPath: destination.path) {
                    let base = source.deletingPathExtension().lastPathComponent
                    destination = directory.appendingPathComponent("\(base)-\(index + 1)")
                    if !source.pathExtension.isEmpty {
                        destination.appendPathExtension(source.pathExtension)
                    }
                }
                try manager.copyItem(at: source, to: destination)
                staged.append(destination)
            }
            return (staged, directory)
        }.value
    }
}

/// Holds the share alive until its delegate fires — `NSSharingService` keeps
/// only a weak delegate reference, so without this the callback never lands.
/// It also owns the staged copies' lifetime.
private final class ShareSession: NSObject, NSSharingServiceDelegate {
    private let directory: URL
    private let onFinish: @MainActor (AirDropTransfer.Status) -> Void
    private var hasFinished = false

    init(directory: URL, onFinish: @escaping @MainActor (AirDropTransfer.Status) -> Void) {
        self.directory = directory
        self.onFinish = onFinish
        super.init()
    }

    func sharingService(_: NSSharingService, didShareItems _: [Any]) {
        finish(.completed)
    }

    func sharingService(_: NSSharingService, didFailToShareItems _: [Any], error: Error) {
        // Cancelling the AirDrop picker arrives here as an error too, which
        // is not worth an alert — the island just clears.
        Log.airDrop.notice("AirDrop send failed: \(error.localizedDescription, privacy: .public)")
        finish(.failed(error.localizedDescription))
    }

    private func finish(_ status: AirDropTransfer.Status) {
        guard !hasFinished else { return }
        hasFinished = true
        try? FileManager.default.removeItem(at: directory)
        Task { @MainActor [onFinish] in onFinish(status) }
    }
}
