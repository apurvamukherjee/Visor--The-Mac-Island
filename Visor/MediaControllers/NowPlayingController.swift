//
//  NowPlayingController.swift
//  
//
//  Created by Apurva on 2025-03-29.
//

import AppKit
import Combine
import Foundation
import MediaRemoteAdapter

final class NowPlayingController: ObservableObject, MediaControllerProtocol {
    func updatePlaybackInfo() async {
        await fetchFavoriteStateIfSupported()
    }

    // MARK: - Properties
    @Published private(set) var playbackState: PlaybackState = .init(
        bundleIdentifier: "com.apple.Music"
    )

    // Visor: every adapter event repeats the whole cover as base64, usually unchanged.
    private var lastArtworkBase64: String?
    private var lastArtwork: Data?
    // Visor: browsers report a new track with no cover or the previous
    // track's, and send the real one about a second later. MediaRemote does
    // not always post that change, and the adapter keeps the old cover when
    // the new one is smaller, so the wrong image could stay up all track.
    private var trackTitle = ""
    private var previousTrackArtworkBase64: String?
    private var refetchedArtworkBase64: String?
    private var artworkRetryTitle: String?
    private var artworkRetryTask: Task<Void, Never>?
    private static let artworkRetryDelays: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4)]

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        AppleScriptHelper.volumeScriptableApps[playbackState.bundleIdentifier] != nil
    }

    var supportsFavorite: Bool {
        let bundleID = playbackState.bundleIdentifier
        return bundleID == "com.apple.Music"
    }

    func setFavorite(_ favorite: Bool) async {
        let bundleID = playbackState.bundleIdentifier
        
        if bundleID == "com.apple.Music" {
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
            if !runningApps.isEmpty {
                let script = """
                tell application "Music"
                    try
                        set favorited of current track to \(favorite ? "true" : "false")
                    end try
                end tell
                """
                try? await AppleScriptHelper.execute(script)
            }
        }
        
        // Update the favorite state locally and fetch updated info
        try? await Task.sleep(for: .milliseconds(150))
        await updatePlaybackInfo()
    }

    // MARK: - Media Remote Adapter
    // Visor's MediaRemoteAdapter package, not a bundled perl script: the
    // script and framework this controller used to launch were never bundled,
    // so it received nothing and browser players (YouTube Music in Chrome,
    // Safari, ...) never appeared. The package reports every MediaRemote
    // source, browsers included, and carries the transport commands too.
    private let mediaController = MediaController()

    // MARK: - Initialization
    init() {
        mediaController.onTrackInfoReceived = { [weak self] trackInfo in
            self?.handleTrackInfo(trackInfo)
        }
        mediaController.startListening()
    }

    deinit {
        artworkRetryTask?.cancel()
        mediaController.stopListening()
    }

    // MARK: - Protocol Implementation
    func togglePlay() async {
        mediaController.togglePlayPause()
    }

    func nextTrack() async {
        mediaController.nextTrack()
    }

    func previousTrack() async {
        mediaController.previousTrack()
    }

    func seek(to time: Double) async {
        mediaController.setTime(seconds: time)
    }

    func isActive() -> Bool {
        return true
    }
    
    func toggleShuffle() async {
        mediaController.setShuffleMode(playbackState.isShuffled ? .off : .songs)
        playbackState.isShuffled.toggle()
    }
    
    func toggleRepeat() async {
        let newRepeatMode: RepeatMode = switch playbackState.repeatMode {
        case .off: .all
        case .all: .one
        case .one: .off
        }
        playbackState.repeatMode = newRepeatMode
        mediaController.setRepeatMode(Self.adapterRepeatMode(newRepeatMode))
    }
    
    func setVolume(_ level: Double) async {
        // MediaRemote framework doesn't provide direct volume control for the active audio session
        // As a workaround, try to control the currently active music app directly
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        
        let bundleID = playbackState.bundleIdentifier
        if let appName = AppleScriptHelper.volumeScriptableApps[bundleID],
           !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty {
            try? await AppleScriptHelper.execute("tell application \"\(appName)\" to set sound volume to \(volumePercentage)")
        }
        
        playbackState.volume = clampedLevel
    }

    // MARK: - Update Methods
    /// The adapter sends a whole payload per event, or nil when nothing is
    /// playing. nil maps to the same empty state the old stream produced.
    private func handleTrackInfo(_ trackInfo: TrackInfo?) {
        guard let payload = trackInfo?.payload else {
            var empty = PlaybackState(bundleIdentifier: playbackState.bundleIdentifier)
            empty.title = ""
            empty.artist = ""
            empty.album = ""
            empty.lastUpdated = Date()
            empty.volume = playbackState.volume
            playbackState = empty
            return
        }

        var newPlaybackState = PlaybackState(
            bundleIdentifier: payload.bundleIdentifier ?? playbackState.bundleIdentifier
        )
        newPlaybackState.title = payload.title ?? ""
        newPlaybackState.artist = payload.artist ?? ""
        newPlaybackState.album = payload.album ?? ""
        newPlaybackState.duration = (payload.durationMicros ?? 0) / 1_000_000
        newPlaybackState.currentTime = (payload.elapsedTimeMicros ?? 0) / 1_000_000
        newPlaybackState.isShuffled = (payload.shuffleMode ?? .off) != .off
        newPlaybackState.repeatMode = switch payload.repeatMode ?? .off {
        case .off: .off
        case .one: .one
        case .all: .all
        }
        if newPlaybackState.title != trackTitle {
            trackTitle = newPlaybackState.title
            previousTrackArtworkBase64 = lastArtworkBase64
            refetchedArtworkBase64 = nil
        }
        var artworkBase64 = payload.artworkDataBase64
        let artworkMayBeStale = artworkBase64 == nil || artworkBase64 == previousTrackArtworkBase64
        if artworkMayBeStale, let refetched = refetchedArtworkBase64 {
            artworkBase64 = refetched
        }
        if artworkBase64 != lastArtworkBase64 {
            lastArtworkBase64 = artworkBase64
            lastArtwork = artworkBase64.flatMap {
                Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        newPlaybackState.artwork = lastArtwork
        newPlaybackState.lastUpdated = payload.timestampEpochMicros
            .map { Date(timeIntervalSince1970: $0 / 1_000_000) } ?? Date()
        newPlaybackState.isPlaying = payload.isPlaying ?? false
        newPlaybackState.playbackRate = payload.playbackRate ?? (newPlaybackState.isPlaying ? 1.0 : 0.0)
        newPlaybackState.volume = playbackState.volume
        newPlaybackState.isFavorite = playbackState.title == newPlaybackState.title
            && playbackState.artist == newPlaybackState.artist
            && playbackState.isFavorite

        self.playbackState = newPlaybackState

        if artworkMayBeStale && refetchedArtworkBase64 == nil && !trackTitle.isEmpty {
            retryArtwork(for: trackTitle)
        } else {
            cancelArtworkRetry()
        }
    }

    // Visor: `get` reads MediaRemote afresh, past the adapter's cached cover.
    // At most one bounded round per track; a same-album track whose cover
    // really is unchanged just runs out of attempts.
    private func retryArtwork(for title: String) {
        guard artworkRetryTitle != title else { return }
        artworkRetryTask?.cancel()
        artworkRetryTitle = title
        artworkRetryTask = Task { @MainActor [weak self] in
            for delay in Self.artworkRetryDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                self.mediaController.getTrackInfo { [weak self] trackInfo in
                    guard let self,
                          let payload = trackInfo?.payload,
                          let artwork = payload.artworkDataBase64,
                          payload.title == title,
                          self.trackTitle == title,
                          self.refetchedArtworkBase64 == nil,
                          artwork != self.previousTrackArtworkBase64
                    else { return }
                    self.refetchedArtworkBase64 = artwork
                    self.handleTrackInfo(trackInfo)
                }
            }
        }
    }

    private func cancelArtworkRetry() {
        artworkRetryTask?.cancel()
        artworkRetryTask = nil
        artworkRetryTitle = nil
    }

    private static func adapterRepeatMode(_ mode: RepeatMode) -> TrackInfo.RepeatMode {
        switch mode {
        case .off: .off
        case .one: .one
        case .all: .all
        }
    }
    
     private func fetchFavoriteStateIfSupported() async {
         let bundleID = playbackState.bundleIdentifier
        
         if bundleID == "com.apple.Music" {
             let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
             guard !runningApps.isEmpty else { return }
             
             let script = """
             tell application "Music"
                 try
                     return favorited of current track
                 on error
                     return false
                 end try
             end tell
             """
             if let result = try? await AppleScriptHelper.execute(script) {
                 var updated = self.playbackState
                 updated.isFavorite = result.booleanValue
                 self.playbackState = updated
             }
         }
     }
    
}
