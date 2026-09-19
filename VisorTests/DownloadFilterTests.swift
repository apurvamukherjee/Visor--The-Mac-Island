import Testing
@testable import Visor

struct DownloadFilterTests {
    @Test
    func recognisesTheSuffixesBrowsersUseWhileDownloading() {
        #expect(DownloadFilter.isTemporary("movie.mp4.crdownload"))
        #expect(DownloadFilter.isTemporary("report.pdf.download"))
        #expect(DownloadFilter.isTemporary("archive.zip.part"))
        #expect(!DownloadFilter.isTemporary("movie.mp4"))
    }

    /// Case matters here: a file wearing ".CRDOWNLOAD" is still in flight.
    @Test
    func matchesSuffixesRegardlessOfCase() {
        #expect(DownloadFilter.isTemporary("movie.mp4.CRDOWNLOAD"))
    }

    /// The point of the loop in `displayName`: a download manager can stack
    /// more than one temporary suffix on the same file.
    @Test
    func stripsEveryTemporarySuffix() {
        #expect(DownloadFilter.displayName(for: "movie.mp4.crdownload") == "movie.mp4")
        #expect(DownloadFilter.displayName(for: "movie.mp4.part.tmp") == "movie.mp4")
        #expect(DownloadFilter.displayName(for: "movie.mp4") == "movie.mp4")
    }

    /// A file called nothing but a suffix must not be stripped to an empty
    /// name — the row would then be a blank line.
    @Test
    func leavesAFileNamedOnlyAfterItsSuffixAlone() {
        #expect(!DownloadFilter.displayName(for: ".crdownload").isEmpty)
    }

    /// The attribute is written as a string in the writer's locale, so a
    /// comma is a decimal point on plenty of machines.
    @Test
    func parsesProgressInEitherDecimalConvention() {
        #expect(DownloadFilter.parseProgress("0.42") == 0.42)
        #expect(DownloadFilter.parseProgress("0,42") == 0.42)
        #expect(DownloadFilter.parseProgress(" 0.42\n") == 0.42)
    }

    @Test
    func clampsProgressAndRejectsNonsense() {
        #expect(DownloadFilter.parseProgress("1.5") == 1)
        #expect(DownloadFilter.parseProgress("-0.2") == 0)
        #expect(DownloadFilter.parseProgress("nope") == nil)
        #expect(DownloadFilter.parseProgress("") == nil)
    }
}
