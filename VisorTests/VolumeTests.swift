import Testing
@testable import Visor

struct VolumeTests {
    /// The tiers are what the island and Control Center have to agree on.
    @Test
    func glyphTiersWithLevel() {
        #expect(VolumeGlyph.symbolName(level: 0, isMuted: false) == "speaker.fill")
        #expect(VolumeGlyph.symbolName(level: 0.2, isMuted: false) == "speaker.wave.1.fill")
        #expect(VolumeGlyph.symbolName(level: 0.5, isMuted: false) == "speaker.wave.2.fill")
        #expect(VolumeGlyph.symbolName(level: 1, isMuted: false) == "speaker.wave.3.fill")
    }

    /// Mute wins at any level: the hardware level stays where it was so
    /// unmuting can restore it, which is exactly when a level-driven glyph
    /// would lie.
    @Test
    func muteWinsOverLevel() {
        #expect(VolumeGlyph.symbolName(level: 0.9, isMuted: true) == "speaker.slash.fill")
        #expect(VolumeInfo(level: 0.9, isMuted: true).effectiveLevel == 0)
        #expect(VolumeInfo(level: 0.9, isMuted: true).percentage == 0)
        #expect(VolumeInfo(level: 0.9, isMuted: false).percentage == 90)
    }

    /// A drag past either end of the bar is the normal case, not an error.
    @Test
    func scrubbingClampsToTheTrack() {
        #expect(VolumeInfo.clamped(-0.4) == 0)
        #expect(VolumeInfo.clamped(1.7) == 1)
        #expect(VolumeInfo.clamped(0.42) == 0.42)
    }
}
