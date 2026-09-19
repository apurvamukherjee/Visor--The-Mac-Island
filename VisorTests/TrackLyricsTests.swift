import Testing
@testable import Visor

struct TrackLyricsTests {
    private let lyrics = TrackLyrics(lines: [
        LyricLine(time: 0, text: "First"),
        LyricLine(time: 10, text: "Second"),
        LyricLine(time: 20, text: "Third")
    ])

    @Test func activeLineIsNilBeforeTheFirstTimestamp() {
        let untimed = TrackLyrics(lines: [LyricLine(time: 5, text: "Later")])
        #expect(untimed.activeLineIndex(at: 0) == nil)
    }

    @Test func activeLineIsTheLastOneReached() {
        #expect(lyrics.activeLineIndex(at: 15) == 1)
    }

    @Test func activeLineHoldsPastTheFinalTimestamp() {
        #expect(lyrics.activeLineIndex(at: 999) == 2)
    }

    @Test func windowIsEmptyWithNoActiveLine() {
        #expect(lyrics.window(around: nil, radius: 1).isEmpty)
    }

    @Test func windowClampsAtTheEdges() {
        let window = lyrics.window(around: 0, radius: 1)
        #expect(window.map(\.id) == [0, 1])
        #expect(window.first?.isActive == true)
        #expect(window.last?.isActive == false)
    }

    @Test func parseLRCSkipsMetadataTagsAndBlankLines() {
        let raw = "[ar:Someone]\n[00:01.50]First line\n\n[00:12.00]Second line"
        let parsed = TrackLyrics.parseLRC(raw)
        #expect(parsed.lines.map(\.text) == ["First line", "Second line"])
        #expect(parsed.lines.map(\.time) == [1.5, 12.0])
    }

    @Test func parseLRCSortsOutOfOrderLines() {
        let raw = "[00:20.00]Later\n[00:05.00]Earlier"
        let parsed = TrackLyrics.parseLRC(raw)
        #expect(parsed.lines.map(\.text) == ["Earlier", "Later"])
    }
}
