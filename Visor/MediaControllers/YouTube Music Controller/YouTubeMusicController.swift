//
//  YouTubeMusicController.swift
//  
//
//  Created by Apurva on 2025-03-30.
//  Modified by Apurva on 2025-06-16.
//

import Foundation
import Combine
import SwiftUI

final class YouTubeMusicController: MediaControllerProtocol {
    // MARK: - Published Properties
    @Published var playbackState = PlaybackState(
        bundleIdentifier: YouTubeMusicConfiguration.default.bundleIdentifier
    )

    private var artworkFetchTask: Task<Void, Never>?
    // Visor: see updatePlaybackState.
    private var lastArtworkURL: String?
    
    var playbackStatePublisher: AnyPublisher<PlaybackState, Never> {
        $playbackState.eraseToAnyPublisher()
    }

    var supportsVolumeControl: Bool {
        return true
    }

    var supportsFavorite: Bool { true }

    func setFavorite(_ favorite: Bool) async {
        do {
            let token = try await authenticate()
            if favorite != playbackState.isFavorite {
                _ = try await httpClient.toggleLike(token: token)
            }
            try? await Task.sleep(for: .milliseconds(150))
            await updatePlaybackInfo()
        } catch {
            print("[YouTubeMusicController] Failed to set favorite: \(error)")
        }
    }

    // MARK: - Private Properties
    // Visor: nothing passed another configuration, so the init takes none.
    private let configuration = YouTubeMusicConfiguration.default
    private let httpClient = YouTubeMusicHTTPClient(baseURL: YouTubeMusicConfiguration.default.baseURL)
    // Visor: replaces the YouTubeMusicAuthManager actor. One cached token
    // task, shared by concurrent callers; main-actor isolation stands in for
    // the actor, and a failure or a 401 clears it so the next call re-auths.
    @MainActor private var authTask: Task<String, Error>?
    private var webSocketClient: YouTubeMusicWebSocketClient?
    
    private var updateTimer: Timer?
    private var appStateObserver: Task<Void, Never>?
    private var reconnectDelay: TimeInterval = 1.0
    
    // MARK: - Initialization
    init() {
        setupAppStateObserver()
        
        Task {
            await initializeIfAppActive()
        }
    }
    
    // MARK: - MediaControllerProtocol Implementation
    func togglePlay() async {
        if !isActive() { launchApp() }
        await sendCommand(endpoint: "/toggle-play", method: "POST")
    }
    
    func nextTrack() async { await sendCommand(endpoint: "/next", method: "POST") }

    func previousTrack() async { await sendCommand(endpoint: "/previous", method: "POST") }
    
    func seek(to time: Double) async {
        let payload = ["seconds": time]
        await sendCommand(endpoint: "/seek-to", method: "POST", body: payload)
    }

    func setVolume(_ level: Double) async {
        let clampedLevel = max(0.0, min(1.0, level))
        let volumePercentage = Int(clampedLevel * 100)
        let payload = ["volume": volumePercentage]
        await sendCommand(endpoint: "/volume", method: "POST", body: payload)
    }
    func fetchShuffleState() async { await sendCommand(endpoint: "/shuffle", method: "GET", refresh: false) }
    func fetchRepeatMode() async { await sendCommand(endpoint: "/repeat-mode", method: "GET", refresh: false) }
    
    func toggleShuffle() async { await sendCommand(endpoint: "/shuffle", method: "POST") }
    func toggleRepeat() async { await sendCommand(endpoint: "/switch-repeat", method: "POST") }

    nonisolated func isActive() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == configuration.bundleIdentifier
        }
    }
    
    func updatePlaybackInfo() async {
        guard isActive() else {
            resetPlaybackState()
            return
        }
        
        do {
            let token = try await authenticate()
            let response = try await httpClient.getPlaybackInfo(token: token)
            await updatePlaybackState(with: response)
            // Fetch like state if supported
            do {
                let likeResp = try await httpClient.getLikeState(token: token)
                // DISLIKE has no UI of its own, so it reads as not favourited.
                playbackState.isFavorite = likeResp.state?.uppercased() == "LIKE"
            } catch {
                // Don't treat it as an error if the like endpoint doesn't exist — just skip
            }
        } catch YouTubeMusicError.authenticationRequired {
            await invalidateToken()
        } catch {
            print("[YouTubeMusicController] Failed to update playback info: \(error)")
        }
    }
    
    // MARK: - Private Methods
    private func setupAppStateObserver() {
        appStateObserver = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    let launchNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.didLaunchApplicationNotification
                    )
                    
                    for await notification in launchNotifications {
                        await self?.handleAppLaunched(notification)
                    }
                }
                
                group.addTask {
                    let terminateNotifications = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.didTerminateApplicationNotification
                    )
                    
                    for await notification in terminateNotifications {
                        await self?.handleAppTerminated(notification)
                    }
                }
            }
        }
    }
    
    private func handleAppLaunched(_ notification: Notification) async {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == configuration.bundleIdentifier else {
            return
        }
        
        await initializeIfAppActive()
    }
    
    private func handleAppTerminated(_ notification: Notification) async {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == configuration.bundleIdentifier else {
            return
        }
        
        Task { @MainActor in
            stopPeriodicUpdates()
            appStateObserver?.cancel()
        }
        
        Task {
            await webSocketClient?.disconnect()
            webSocketClient = nil
        }
        
        resetPlaybackState()
    }
    
    private func initializeIfAppActive() async {
        guard isActive() else { return }
        
        do {
            let token = try await authenticate()
            await setupWebSocketIfPossible(token: token)
            await startPeriodicUpdates()
            await updatePlaybackInfo()
        } catch {
            print("[YouTubeMusicController] Failed to initialize: \(error)")
            await scheduleReconnect()
        }
    }
    
    private func setupWebSocketIfPossible(token: String) async {
        guard let wsURL = configuration.webSocketURL else {
            print("[YouTubeMusicController] Failed to build WebSocket URL")
            return
        }
        
        let client = YouTubeMusicWebSocketClient(
            onMessage: { [weak self] data in
                await self?.handleWebSocketMessage(data)
            },
            onDisconnect: { [weak self] in
                await self?.handleWebSocketDisconnect()
            }
        )
        
        do {
            try await client.connect(to: wsURL, with: token)
            webSocketClient = client
            stopPeriodicUpdates() // WebSocket will provide real-time updates
            reconnectDelay = configuration.reconnectDelay.lowerBound
        } catch {
            print("[YouTubeMusicController] WebSocket connection failed: \(error)")
            await scheduleReconnect()
        }
    }
    
    private func handleWebSocketMessage(_ data: Data) async {
        guard let message = WebSocketMessage(from: data) else {
            if let response = try? JSONDecoder().decode(PlaybackResponse.self, from: data) {
                await updatePlaybackState(with: response)
            }
            return
        }
        switch message.type {
        case .playerInfo, .videoChanged, .playerStateChanged:
            if let response = PlaybackResponse.from(websocketData: message.payload) {
                await updatePlaybackState(with: response)
            }

        case .positionChanged:
            let data = message.payload
            guard let newPosition = (data["position"] as? Double) ?? (data["elapsedSeconds"] as? Double) else { return }
            updateState { $0.currentTime = newPosition }

        case .repeatChanged:
            updateState {
                if let name = message.payload["repeat"] as? String, let mode = RepeatMode(youTubeMusicName: name) {
                    $0.repeatMode = mode
                }
            }

        case .shuffleChanged:
            let data = message.payload
            updateState {
                if let shuffle = (data["shuffle"] as? Bool) ?? (data["isShuffled"] as? Bool) { $0.isShuffled = shuffle }
            }

        case .volumeChanged:
            updateState {
                if let volume = message.payload["volume"] as? NSNumber { $0.volume = volume.doubleValue / 100.0 }
            }
        }
    }

    // Visor: each single-field websocket event stamped lastUpdated and
    // published only a changed copy; the four copies share this now.
    private func updateState(_ change: (inout PlaybackState) -> Void) {
        var copy = playbackState
        change(&copy)
        copy.lastUpdated = Date()
        if copy != playbackState { playbackState = copy }
    }
    
    private func handleWebSocketDisconnect() async {
        webSocketClient = nil
        await startPeriodicUpdates() // Fallback to polling
        await scheduleReconnect()
    }
    
    private func scheduleReconnect() async {
        try? await Task.sleep(for: .seconds(reconnectDelay))
        reconnectDelay = min(reconnectDelay * 2, configuration.reconnectDelay.upperBound)
        
        if isActive() {
            await initializeIfAppActive()
        }
    }
    
    private func startPeriodicUpdates() async {
        guard isActive() && webSocketClient == nil else { return }
        
        stopPeriodicUpdates()
        
        updateTimer = Timer.scheduledTimer(withTimeInterval: configuration.updateInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.updatePlaybackInfo()
            }
        }
    }
    
    private func stopPeriodicUpdates() {
        updateTimer?.invalidate()
        updateTimer = nil
    }

    func pollPlaybackState() async {
        if !isActive() {
            return
        }
        
        await fetchRepeatMode()
        await fetchShuffleState()
        await updatePlaybackInfo()
    }
    
    private func sendCommand(
        endpoint: String,
        method: String = "POST",
        body: (any Codable & Sendable)? = nil,
        refresh: Bool = true
    ) async {
        do {
            let token = try await authenticate()
            
            let data = try await httpClient.sendCommand(
                endpoint: endpoint,
                method: method,
                body: body,
                token: token
            )
            // Lightweight endpoint-specific parsing
            if endpoint == "/shuffle" {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let shuffleState = json["state"] as? Bool {
                    playbackState.isShuffled = shuffleState
                } else {
                    playbackState.isShuffled = !playbackState.isShuffled
                }
            } else if endpoint == "/repeat-mode" {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let mode = json["mode"] as? String { updateRepeatMode(mode) }
                }
            }  else if endpoint == "/switch-repeat" {
                playbackState.repeatMode = playbackState.repeatMode.next
            } else if refresh && webSocketClient == nil {
                try? await Task.sleep(for: .milliseconds(100))
                await updatePlaybackInfo()
            }
        } catch YouTubeMusicError.authenticationRequired {
            await invalidateToken()
        } catch {
            print("[YouTubeMusicController] Command failed: \(error)")
        }
    }
    
    private func updatePlaybackState(with response: PlaybackResponse) async {
        var newState = playbackState
        
        newState.isPlaying = !response.isPaused
        newState.title = response.title ?? newState.title
        newState.artist = response.artist ?? newState.artist
        newState.album = response.album ?? newState.album
        newState.currentTime = response.elapsedSeconds ?? newState.currentTime
        newState.duration = response.songDuration ?? newState.duration
        newState.lastUpdated = Date()
        newState.isShuffled = response.isShuffled ?? newState.isShuffled
        if let index = response.repeatMode, let mode = RepeatMode(youTubeMusicIndex: index) {
            newState.repeatMode = mode
        }
        newState.volume = response.volume.map { $0 / 100.0 } ?? newState.volume

        // Visor: lastUpdated is always new, so this branch runs on every poll
        // and websocket update; refetch the cover only when it changed (or
        // never arrived), not every 2 s, cancelling a slow download each time.
        if newState != playbackState {
            playbackState = newState

            guard response.imageSrc != lastArtworkURL || playbackState.artwork == nil else { return }
            lastArtworkURL = response.imageSrc
            artworkFetchTask?.cancel()
            artworkFetchTask = nil

            if let artworkURL = response.imageSrc,
               let url = URL(string: artworkURL) {
                artworkFetchTask = Task {
                    do {
                        let data = try await ImageService.shared.fetchImageData(from: url)
                        await MainActor.run { [weak self] in
                            self?.playbackState.artwork = data

                        }
                    } catch { /* ignore */ }
                }
            }
        }
    }
    
    @MainActor private func authenticate() async throws -> String {
        let task = authTask ?? Task { [httpClient] in try await httpClient.authenticate() }
        authTask = task
        do {
            return try await task.value
        } catch {
            authTask = nil
            throw error
        }
    }

    @MainActor private func invalidateToken() {
        authTask?.cancel()
        authTask = nil
    }

    private func resetPlaybackState() {
        playbackState = PlaybackState(
            bundleIdentifier: configuration.bundleIdentifier,
            isPlaying: false
        )
    }
    
    private func launchApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: configuration.bundleIdentifier) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func updateRepeatMode(_ name: String) {
        if let target = RepeatMode(youTubeMusicName: name), target != playbackState.repeatMode {
            playbackState.repeatMode = target
        }
    }
    
}
