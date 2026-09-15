import Foundation
import MediaRemoteAdapter
import Testing
@testable import Visor

struct NowPlayingInfoTests {
    @Test
    func mapsPayloadWithAllFieldsPresent() {
        let payload = TrackInfo.Payload(
            title: "Song",
            artist: "Artist",
            album: nil,
            isPlaying: true,
            durationMicros: 200_000_000,
            elapsedTimeMicros: 50_000_000,
            applicationName: nil,
            bundleIdentifier: "com.example.player",
            artworkDataBase64: nil,
            artworkMimeType: nil,
            timestampEpochMicros: 1_000_000_000_000,
            PID: nil,
            shuffleMode: nil,
            repeatMode: nil,
            playbackRate: 1.0,
            artwork: nil
        )

        let info = NowPlayingInfo.from(payload)

        #expect(info?.title == "Song")
        #expect(info?.artist == "Artist")
        #expect(info?.isPlaying == true)
        #expect(info?.trackIdentity == "com.example.player:Song:Artist")
    }

    @Test
    func missingTitleReturnsNil() {
        let payload = TrackInfo.Payload(
            title: nil,
            artist: nil,
            album: nil,
            isPlaying: nil,
            durationMicros: nil,
            elapsedTimeMicros: nil,
            applicationName: nil,
            bundleIdentifier: nil,
            artworkDataBase64: nil,
            artworkMimeType: nil,
            timestampEpochMicros: nil,
            PID: nil,
            shuffleMode: nil,
            repeatMode: nil,
            playbackRate: nil,
            artwork: nil
        )
        #expect(NowPlayingInfo.from(payload) == nil)
    }

    @Test @MainActor
    func artworkCacheReturnsNilAndCachesTheMissWhenSourceIsNil() {
        let cache = ArtworkCache()
        #expect(cache.image(for: "track-1", source: nil) == nil)
        // Second call with the same identity must still return nil without
        // re-decoding — this only proves it doesn't crash/hang; there's no
        // public way to assert "didn't redo work" from outside the cache.
        #expect(cache.image(for: "track-1", source: nil) == nil)
    }
}
