import Foundation

/// One in-flight download. Progress is whatever the downloading app itself
/// reported through the `com.apple.progress.fractionCompleted` extended
/// attribute, or nil when it reported nothing — a nil is drawn as an
/// indeterminate bar rather than guessed at, because a wrong number that
/// looks precise is worse than an honest "working on it".
struct DownloadItem: Equatable, Identifiable, Sendable {
    let url: URL
    let displayName: String
    let byteCount: Int64
    let progress: Double?

    var id: String {
        url.path
    }
}

/// The pure half of `DownloadService`: which files in a folder listing count
/// as downloads in flight, and what they are called. Separated so it can be
/// tested without a real Downloads folder.
enum DownloadFilter {
    /// Suffixes browsers and download managers give a file while it is still
    /// arriving. A file wearing one is in flight by definition; anything else
    /// is only in flight while it is still reporting progress.
    static let temporarySuffixes = [".download", ".crdownload", ".part", ".partial", ".tmp"]

    static func isTemporary(_ fileName: String) -> Bool {
        let lowercased = fileName.lowercased()
        return temporarySuffixes.contains { lowercased.hasSuffix($0) }
    }

    /// Strips the temporary suffixes back off, so "video.mp4.crdownload"
    /// shows as "video.mp4" while it downloads rather than changing name the
    /// instant it lands. Loops because a file can wear more than one.
    static func displayName(for fileName: String) -> String {
        var name = fileName
        while isTemporary(name) {
            let trimmed = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
            guard trimmed != name, !trimmed.isEmpty else { break }
            name = trimmed
        }
        return name
    }

    /// Progress as the downloading app reported it. The value is written as a
    /// string whose decimal separator follows the writer's locale, so both
    /// "." and "," are accepted.
    static func parseProgress(_ raw: String) -> Double? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }
}
