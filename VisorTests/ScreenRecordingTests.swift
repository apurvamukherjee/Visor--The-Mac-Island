import Foundation
import Testing
@testable import Visor

struct ScreenRecordingTests {
    @Test
    func elapsedCountsUpFromTheStart() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let recording = ScreenRecording(startedAt: start)
        #expect(recording.elapsed(at: start.addingTimeInterval(65)) == 65)
    }

    /// A clock that went backwards would print a negative time; clamp it.
    @Test
    func elapsedNeverGoesNegative() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let recording = ScreenRecording(startedAt: start)
        #expect(recording.elapsed(at: start.addingTimeInterval(-10)) == 0)
    }

    @Test
    func formatsAsMinutesAndSecondsUntilAnHour() {
        #expect(ScreenRecording.formatted(0) == "00:00")
        #expect(ScreenRecording.formatted(65) == "01:05")
        #expect(ScreenRecording.formatted(3599) == "59:59")
    }

    @Test
    func growsAnHoursFieldOnlyWhenItIsNeeded() {
        #expect(ScreenRecording.formatted(3600) == "1:00:00")
        #expect(ScreenRecording.formatted(3725) == "1:02:05")
    }
}
