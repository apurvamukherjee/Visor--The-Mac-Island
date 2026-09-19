import Foundation
import Testing
@testable import Visor

struct IslandTimerTests {
    private let epoch = Date(timeIntervalSinceReferenceDate: 0)

    @Test
    func remainingCountsDownFromTheDeadline() {
        let timer = IslandTimer(duration: 300, deadline: epoch.addingTimeInterval(300))
        #expect(timer.remaining(at: epoch) == 300)
        #expect(timer.remaining(at: epoch.addingTimeInterval(120)) == 180)
    }

    /// Never negative: an overdue timer reads "Time's up", not a growing
    /// count of how late it is.
    @Test
    func remainingClampsAtZero() {
        let timer = IslandTimer(duration: 60, deadline: epoch.addingTimeInterval(60))
        #expect(timer.remaining(at: epoch.addingTimeInterval(90)) == 0)
        #expect(timer.isFinished(at: epoch.addingTimeInterval(90)))
    }

    /// A paused timer ignores the clock entirely — that is the whole reason
    /// the paused value is stored rather than the deadline being moved.
    @Test
    func pausedRemainingIgnoresElapsedTime() {
        var timer = IslandTimer(duration: 300, deadline: epoch.addingTimeInterval(300))
        timer.pausedRemaining = 42
        #expect(timer.isPaused)
        #expect(timer.remaining(at: epoch.addingTimeInterval(10000)) == 42)
    }

    /// Rounded up, so a 5m timer reads 05:00 on its first frame rather than
    /// 04:59.
    @Test
    func formatRoundsUpAndPads() {
        #expect(IslandTimer.format(300) == "05:00")
        #expect(IslandTimer.format(299.4) == "05:00")
        #expect(IslandTimer.format(59) == "00:59")
        #expect(IslandTimer.format(0) == "00:00")
    }

    @Test
    func formatGrowsAnHoursFieldOnlyWhenNeeded() {
        #expect(IslandTimer.format(3599) == "59:59")
        #expect(IslandTimer.format(3600) == "1:00:00")
        #expect(IslandTimer.format(7325) == "2:02:05")
    }
}
