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
    // Visor: browsers report a new track before its cover has loaded, and
    // MediaRemote does not always post another change once it has, so the
    // app icon stayed up for the whole track.
    private var artworkRetryTask: Task<Void, Never>?
    private static let artworkRetryDelays: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4)]

    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        let bundleID = playbackState.bundleIdentifier
        return bundleID == "com.apple.Music" || bundleID == "com.spotify.client"
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
                try? await AppleScriptHelper.executeVoid(script)
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
    init?() {
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
    func play() async {
        mediaController.play()
    }

    func pause() async {
        mediaController.pause()
    }

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
        if !bundleID.isEmpty {
            if bundleID == "com.apple.Music" {
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")
                if !runningApps.isEmpty {
                    let script = "tell application \"Music\" to set sound volume to \(volumePercentage)"
                    try? await AppleScriptHelper.executeVoid(script)
                }
            } else if bundleID == "com.spotify.client" {
                let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")
                if !runningApps.isEmpty {
                    let script = "tell application \"Spotify\" to set sound volume to \(volumePercentage)"
                    try? await AppleScriptHelper.executeVoid(script)
                }
            }
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
        if payload.artworkDataBase64 != lastArtworkBase64 {
            lastArtworkBase64 = payload.artworkDataBase64
            lastArtwork = payload.artworkDataBase64.flatMap {
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

        if newPlaybackState.artwork == nil && !newPlaybackState.title.isEmpty {
            retryMissingArtwork(for: newPlaybackState.title)
        } else {
            artworkRetryTask?.cancel()
        }
    }

    // Visor: `get` reads MediaRemote afresh, so it sees a cover that arrived
    // without a change notification. Bounded, and only while one is missing.
    private func retryMissingArtwork(for title: String) {
        artworkRetryTask?.cancel()
        artworkRetryTask = Task { @MainActor [weak self] in
            for delay in Self.artworkRetryDelays {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                self.mediaController.getTrackInfo { [weak self] trackInfo in
                    guard let self,
                          let payload = trackInfo?.payload,
                          payload.title == title,
                          payload.artworkDataBase64 != nil,
                          self.playbackState.title == title,
                          self.playbackState.artwork == nil
                    else { return }
                    self.handleTrackInfo(trackInfo)
                }
            }
        }
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
