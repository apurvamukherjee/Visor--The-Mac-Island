import AppKit
import ImageIO
import UniformTypeIdentifiers

/// The file commands. Split into their own file for length: these all act on
/// one URL from the shelf and share nothing with the power, appearance, and
/// audio commands in `SystemCommands.swift`.
@MainActor
extension SystemCommands {
    // MARK: - Files

    static func isArchive(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .archive) ?? false
    }

    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
    }

    /// A plain Markdown file in Application Support, opened in whatever the
    /// user reads Markdown with. Deliberately **not** `~/Documents`: that
    /// directory is TCC-gated on a modern macOS, and a note-taking command
    /// that raises a permission dialog is not a quick note.
    func makeQuickNote() {
        guard let directory = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("Visor", isDirectory: true) else { return }
        let url = directory.appendingPathComponent("Notes.md")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let stamp = Date.now.formatted(date: .abbreviated, time: .shortened)
            let entry = "\n## \(stamp)\n\n"
            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(entry.utf8))
            } else {
                try Data("# Visor Notes\n\(entry)".utf8).write(to: url)
            }
        } catch {
            Log.app.error("Quick note failed: \(error.localizedDescription)")
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// `NSFileCoordinator`'s `.forUploading` — the documented way to get a
    /// zip of any file *or* folder without a third-party archiver. It hands
    /// back a temporary copy, which is why this moves the result rather than
    /// writing in place.
    func compress(_ url: URL) {
        var error: NSError?
        var moved = false
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.forUploading], error: &error) { zipped in
            let destination = Self.available(url.deletingPathExtension().appendingPathExtension("zip"))
            do {
                try FileManager.default.copyItem(at: zipped, to: destination)
                moved = true
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                Log.app.error("Compress failed: \(error.localizedDescription)")
            }
        }
        if let error, !moved {
            Log.app.error("Compress failed: \(error.localizedDescription)")
        }
    }

    /// `ditto -x -k`, because Foundation has no unarchiver at all — only the
    /// `.forUploading` trick in the other direction.
    func expand(_ url: URL) {
        let destination = Self.available(
            url.deletingPathExtension(),
            isDirectory: true
        )
        run("/usr/bin/ditto", ["-x", "-k", url.path, destination.path])
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    /// ImageIO, already linked for artwork decoding. 0.9 rather than 1.0:
    /// the point of converting a screenshot to JPEG is that it gets smaller.
    func convertToJPEG(_ url: URL) {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            Log.app.error("Could not read \(url.lastPathComponent) as an image.")
            return
        }
        let destination = Self.available(url.deletingPathExtension().appendingPathExtension("jpg"))
        guard let output = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(output) else {
            Log.app.error("Could not write \(destination.lastPathComponent).")
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([destination])
    }

    /// Never overwrite what is already there. A command run twice should
    /// produce a second file, not destroy the first one's result.
    private static func available(_ url: URL, isDirectory: Bool = false) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension()
        let ext = url.pathExtension
        for suffix in 2 ... 99 {
            var candidate = base.appendingPathExtension("")
            candidate = URL(fileURLWithPath: "\(base.path) \(suffix)", isDirectory: isDirectory)
            if !ext.isEmpty {
                candidate = candidate.appendingPathExtension(ext)
            }
            if !FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return url
    }
}

// Ruled out by the same probe, each for a measured reason:
//
// - **Empty Trash.** `~/.Trash` is not even listable without Full Disk
//   Access — the probe got nil back for its contents. Same wall as the
//   notification mirroring that was cut in 2026-09-16.
// - **Night Shift.** `CBBlueLightClient` exists and loads, but driving it
//   from Swift means hand-declaring an ObjC interface for a class with no
//   header, to pass a primitive `BOOL`. That is the `@_silgen_name` class of
//   binding this codebase already replaced once for being brittle.
// - **`screencapture -i`.** Works, but see `openScreenshotTool` — the TCC
//   attribution is the risk, not the call.
