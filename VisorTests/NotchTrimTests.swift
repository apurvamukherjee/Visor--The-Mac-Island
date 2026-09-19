import AppKit
import Testing
@testable import Visor

/// The user's width/height trim from Settings, on top of the hardware
/// calibration. Passed in rather than read from `UserDefaults` so these run
/// without touching the user's own preferences.
struct NotchTrimTests {
    private let screen = TrimFakeScreen(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaInsets: NSEdgeInsets(top: 32, left: 0, bottom: 0, right: 0),
        auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 656, height: 32),
        auxiliaryTopRightArea: CGRect(x: 856, y: 950, width: 656, height: 32)
    )

    private var untrimmed: CGRect {
        NotchGeometry.closedRect(for: screen, widthOffset: 0, heightOffset: 0)
    }

    @Test
    func aPositiveTrimWidensAndLengthensTheIsland() {
        let rect = NotchGeometry.closedRect(for: screen, widthOffset: 10, heightOffset: 3)
        #expect(rect.width == untrimmed.width + 10)
        #expect(rect.height == untrimmed.height + 3)
    }

    @Test
    func aNegativeTrimNarrowsIt() {
        let rect = NotchGeometry.closedRect(for: screen, widthOffset: -8, heightOffset: -2)
        #expect(rect.width == untrimmed.width - 8)
        #expect(rect.height == untrimmed.height - 2)
    }

    /// The top edge stays welded to the screen edge whatever the trim does,
    /// which is what keeps the island hidden behind the real cutout.
    @Test
    func theTopEdgeNeverMoves() {
        for offset in [-4.0, 0, 4.0] as [CGFloat] {
            #expect(NotchGeometry.closedRect(for: screen, widthOffset: 0, heightOffset: offset).maxY == 982)
        }
    }

    /// A stored value from an older build, or one edited by hand, must not
    /// be able to produce an island too small to right-click for Settings.
    @Test
    func anAbsurdTrimIsClampedRatherThanObeyed() {
        let rect = NotchGeometry.closedRect(for: screen, widthOffset: -10000, heightOffset: -10000)
        #expect(rect.width >= 8)
        #expect(rect.height >= 8)
    }

    @Test
    func trimsBeyondTheSettingsRangeAreClampedToIt() {
        let far = NotchGeometry.closedRect(for: screen, widthOffset: 500, heightOffset: 500)
        let edge = NotchGeometry.closedRect(
            for: screen,
            widthOffset: CGFloat(Preferences.notchWidthOffsetRange.upperBound),
            heightOffset: CGFloat(Preferences.notchHeightOffsetRange.upperBound)
        )
        #expect(far.size == edge.size)
    }
}

private struct TrimFakeScreen: ScreenGeometryProviding {
    var frame: CGRect
    var safeAreaInsets: NSEdgeInsets
    var auxiliaryTopLeftArea: CGRect?
    var auxiliaryTopRightArea: CGRect?
}
