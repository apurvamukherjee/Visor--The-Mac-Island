import Testing
@testable import Visor

struct BatteryAlertTests {
    private func info(_ percentage: Int, charging: Bool) -> BatteryInfo {
        BatteryInfo(percentage: percentage, isCharging: charging)
    }

    @Test
    func firesOnTheEdgeIntoLow() {
        #expect(BatteryAlert.crossing(from: info(25, charging: false), to: info(20, charging: false)) == .low(20))
    }

    /// The point of the edge check: IOKit reports every percent, and an
    /// alert per report would be a stream of them all the way to empty.
    @Test
    func staysSilentWhileAlreadyLow() {
        #expect(BatteryAlert.crossing(from: info(20, charging: false), to: info(19, charging: false)) == nil)
        #expect(BatteryAlert.crossing(from: info(12, charging: false), to: info(11, charging: false)) == nil)
    }

    @Test
    func plugSomethingInAndLowStopsApplying() {
        #expect(BatteryAlert.crossing(from: info(15, charging: false), to: info(15, charging: true)) == nil)
    }

    /// Unplugging while already under the threshold is a fresh crossing —
    /// the machine has just started running down.
    @Test
    func unpluggingWhileLowAlertsAgain() {
        #expect(BatteryAlert.crossing(from: info(15, charging: true), to: info(15, charging: false)) == .low(15))
    }

    @Test
    func firesOnceOnReachingFull() {
        #expect(BatteryAlert.crossing(from: info(99, charging: true), to: info(100, charging: true)) == .full)
        #expect(BatteryAlert.crossing(from: info(100, charging: true), to: info(100, charging: true)) == nil)
    }

    @Test
    func fullOnBatteryIsNotAnAlert() {
        #expect(BatteryAlert.crossing(from: info(100, charging: true), to: info(100, charging: false)) == nil)
    }

    @Test
    func ordinaryLevelsSaySilent() {
        #expect(BatteryAlert.crossing(from: info(80, charging: false), to: info(79, charging: false)) == nil)
    }
}
