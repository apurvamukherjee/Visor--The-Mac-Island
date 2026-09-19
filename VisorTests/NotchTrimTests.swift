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

    /// The bug this pins: `x` was `left.maxX + closedWidthInset / 2`, which
    /// ignores `widthOffset` entirely — so a trim took its width off the
    /// **right** edge only and walked the island left of the cutout. At the
    /// -13.65 a real user had stored, the island sat 6.8pt off centre with a
    /// 0.5pt gap one side and 14.15pt the other, which reads as the island
    /// collapsing too far and landing out of line with the hardware.
    @Test
    func everyTrimStaysCentredOnTheCutout() {
        // The cutout this fake screen describes: 656...856, midpoint 756.
        let cutoutMidX: CGFloat = 756
        for offset in [CGFloat(-16), -13.65, -8, 0, 8, 16] {
            let rect = NotchGeometry.closedRect(for: screen, widthOffset: offset, heightOffset: 0)
            #expect(abs(rect.midX - cutoutMidX) < 0.001)
        }
    }

    /// A trim must come off both sides equally, which is the same property
    /// stated as a gap rather than a centre.
    @Test
    func aTrimNarrowsBothEdgesEqually() {
        let full = NotchGeometry.closedRect(for: screen, widthOffset: 0, heightOffset: 0)
        let trimmed = NotchGeometry.closedRect(for: screen, widthOffset: -12, heightOffset: 0)
        let leftGap = trimmed.minX - full.minX
        let rightGap = full.maxX - trimmed.maxX
        #expect(abs(leftGap - rightGap) < 0.001)
    }
}

private struct TrimFakeScreen: ScreenGeometryProviding {
    var frame: CGRect
    var safeAreaInsets: NSEdgeInsets
    var auxiliaryTopLeftArea: CGRect?
    var auxiliaryTopRightArea: CGRect?
}
