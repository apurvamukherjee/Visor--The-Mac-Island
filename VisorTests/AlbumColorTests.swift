import Foundation
import Testing
@testable import Visor

struct AlbumColorTests {
    /// Builds a tightly packed RGBA8 buffer where `patch` fills the first
    /// `patchCount` pixels and `base` fills the rest.
    private func pixels(
        base: (UInt8, UInt8, UInt8),
        patch: (UInt8, UInt8, UInt8)? = nil,
        patchCount: Int = 0,
        side: Int = 8
    ) -> [UInt8] {
        var buffer: [UInt8] = []
        for index in 0 ..< (side * side) {
            let colour = index < patchCount ? (patch ?? base) : base
            buffer.append(contentsOf: [colour.0, colour.1, colour.2, 255])
        }
        return buffer
    }

    @Test
    func pureBlackCoverGetsNoTint() {
        let buffer = pixels(base: (0, 0, 0))
        #expect(AlbumColor.from(pixels: buffer, width: 8, height: 8) == nil)
    }

    @Test
    func greyscaleCoverGetsNoTint() {
        let buffer = pixels(base: (40, 40, 40), patch: (210, 210, 210), patchCount: 20)
        #expect(AlbumColor.from(pixels: buffer, width: 8, height: 8) == nil)
    }

    @Test
    func saturatedPatchWinsAndStaysRed() throws {
        let buffer = pixels(base: (8, 8, 8), patch: (220, 30, 30), patchCount: 12)
        let colour = try #require(AlbumColor.from(pixels: buffer, width: 8, height: 8))
        #expect(colour.red > colour.green)
        #expect(colour.red > colour.blue)
    }

    @Test
    func darkCoverIsLiftedUntilItIsLegibleOnBlack() throws {
        // Near-black navy: without the lightness lift this is invisible.
        let buffer = pixels(base: (4, 4, 4), patch: (10, 14, 60), patchCount: 30)
        let colour = try #require(AlbumColor.from(pixels: buffer, width: 8, height: 8))
        #expect(colour.blue > colour.red)
        #expect(contrastOnBlack(colour) >= 7)
    }

    @Test
    func sameCoverAlwaysYieldsTheSameColour() throws {
        let buffer = pixels(base: (12, 40, 90), patch: (200, 120, 20), patchCount: 18)
        let first = try #require(AlbumColor.from(pixels: buffer, width: 8, height: 8))
        let second = try #require(AlbumColor.from(pixels: buffer, width: 8, height: 8))
        #expect(first == second)
    }

    @Test
    func emptyBufferIsRejected() {
        #expect(AlbumColor.from(pixels: [], width: 0, height: 0) == nil)
    }

    /// WCAG relative luminance against #000.
    private func contrastOnBlack(_ colour: AlbumColor.RGB) -> Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * channel(colour.red)
            + 0.7152 * channel(colour.green)
            + 0.0722 * channel(colour.blue)
        return (luminance + 0.05) / 0.05
    }
}
