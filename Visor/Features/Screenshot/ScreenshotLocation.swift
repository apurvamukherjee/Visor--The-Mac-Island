import Foundation

/// Where macOS is currently writing screenshots. Read once at start — the
/// setting lives in another process's defaults domain and changes so rarely
/// that watching it would cost more than a relaunch.
enum ScreenshotLocation {
    private static let domain = "com.apple.screencapture"
    private static let key = "location"

    static func current() -> URL {
        guard
            let raw = UserDefaults(suiteName: domain)?.string(forKey: key),
            !raw.isEmpty
        else {
            return defaultLocation
        }
        let expanded = (raw as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }

    private static var defaultLocation: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Desktop", isDirectory: true)
    }
}
