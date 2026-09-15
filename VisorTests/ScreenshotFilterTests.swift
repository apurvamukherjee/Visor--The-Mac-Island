import Foundation
import Testing
@testable import Visor

struct ScreenshotFilterTests {
    private let mark = Date(timeIntervalSince1970: 1000)

    private func entry(_ name: String, _ offset: TimeInterval, isImage: Bool = true) -> ScreenshotFilter.Entry {
        ScreenshotFilter.Entry(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            modified: mark.addingTimeInterval(offset),
            isImage: isImage
        )
    }

    @Test
    func emptyListYieldsNothing() {
        #expect(ScreenshotFilter.newest(in: [], after: mark) == nil)
    }

    @Test
    func filesOlderThanTheMarkAreIgnored() {
        let entries = [entry("old.png", -10), entry("older.png", -500)]
        #expect(ScreenshotFilter.newest(in: entries, after: mark) == nil)
    }

    @Test
    func nonImagesAreIgnoredEvenWhenNewer() {
        let entries = [entry("clip.mov", 50, isImage: false)]
        #expect(ScreenshotFilter.newest(in: entries, after: mark) == nil)
    }

    @Test
    func dotfilesAreIgnored() {
        let entries = [entry(".hidden.png", 50)]
        #expect(ScreenshotFilter.newest(in: entries, after: mark) == nil)
    }

    @Test
    func newestQualifyingFileWins() {
        let entries = [entry("first.png", 10), entry("second.png", 40), entry("stale.png", -5)]
        #expect(ScreenshotFilter.newest(in: entries, after: mark)?.lastPathComponent == "second.png")
    }
}
