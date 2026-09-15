import Foundation

/// Picks the newest freshly-written image out of a directory listing. Pure so
/// the selection rules are testable without a real folder.
enum ScreenshotFilter {
    struct Entry: Equatable, Sendable {
        let url: URL
        let modified: Date
        let isImage: Bool
    }

    /// Deliberately not matched on a "Screenshot" filename prefix: that string
    /// is localized, so it breaks for anyone not running macOS in English.
    static func newest(in entries: [Entry], after mark: Date) -> URL? {
        entries
            .filter(\.isImage)
            .filter { $0.modified > mark }
            .filter { !$0.url.lastPathComponent.hasPrefix(".") }
            .max { $0.modified < $1.modified }?
            .url
    }
}
