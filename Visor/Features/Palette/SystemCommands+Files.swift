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

    // MARK: - Clipboard

    /// Image types the clipboard is read for, best first. PNG before TIFF
    /// because every app that copies a picture offers one of the two and TIFF
    /// is the lossless-but-enormous fallback macOS puts on the board itself —
    /// a screenshot copied with ⌃⌘⇧4 is ~20x larger as TIFF than as PNG.
    private static let clipboardImageTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff
    ]

    /// Whether `stashClipboard` would find anything, without writing a file
    /// to find out. Read when the palette opens, which is why it is separate
    /// from the command itself.
    /// `board` is injectable for the same reason `launch`'s `resolve` is: a
    /// scratch pasteboard lets the branch below be exercised without putting
    /// anything on the user's real clipboard.
    static func hasStashableClipboard(on board: NSPasteboard = .general) -> Bool {
        if board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return true
        }
        return board.availableType(from: clipboardImageTypes) != nil
    }

    /// The clipboard as something the shelf can hold.
    ///
    /// A copied *file* is handed over as-is — there is no reason to duplicate
    /// a file that already exists somewhere the user chose. Image data copied
    /// out of an app that never wrote a file is written to a temporary one,
    /// because the shelf holds URLs: a chip is dragged out as a file, and a
    /// `CGImage` cannot be dropped into Finder.
    ///
    /// Returns nil rather than throwing: the caller is a palette row that is
    /// only offered when `hasStashableClipboard`, so nil here means the board
    /// changed between the palette opening and the key being pressed, which
    /// is nothing to report.
    func stashClipboard(on board: NSPasteboard = .general) -> URL? {
        let urls = board.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        if let url = urls?.first {
            return url
        }
        guard
            let type = board.availableType(from: Self.clipboardImageTypes),
            let data = board.data(forType: type)
        else {
            return nil
        }
        return Self.writeClipboardImage(data, type: type)
    }

    /// Named for when it was copied, so two stashes in a row are two rows on
    /// the shelf rather than one overwriting the other — and so the name says
    /// something once it has been dragged into a folder.
    private static func writeClipboardImage(
        _ data: Data,
        type: NSPasteboard.PasteboardType
    ) -> URL? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Visor/Clipboard", isDirectory: true)
        let stamp = Date.now.formatted(
            .verbatim("yyyy-MM-dd 'at' HH.mm.ss", locale: .current, timeZone: .current, calendar: .current)
        )
        let url = directory
            .appendingPathComponent("Clipboard \(stamp)")
            .appendingPathExtension(type == .png ? "png" : "tiff")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url)
            return url
        } catch {
            Log.app.error("Stashing the clipboard failed: \(error.localizedDescription)")
            return nil
        }
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
