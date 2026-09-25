//
//  FullscreenMediaDetection.swift
//  
//
//  Created by Apurva on 06/09/2024.
//

import AppKit
import Combine
import Defaults

@MainActor
final class FullscreenMediaDetector: ObservableObject {
    static let shared = FullscreenMediaDetector()
    
    @Published var fullscreenStatus: [String: Bool] = [:]
    
    private var spaces: [String: [String]]?
    
    // Visor: replaces MacroVisionKit's FullScreenMonitor stream with the same
    // two triggers. The package registered the screen-parameters observer on
    // NSWorkspace's center, where AppKit never posts it; it is on the default
    // center here, so plugging in a display updates the status too. A
    // singleton never removes its observers.
    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in FullscreenMediaDetector.shared.refresh() }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in FullscreenMediaDetector.shared.refresh() }
        }
        // Deferred like the package's first yield, so shared is set before
        // updateStatus reads MusicManager.
        Task { @MainActor in refresh() }
    }
    
    private func refresh() {
        let current = FullScreenSpaces.current()
        guard current != spaces else { return }
        spaces = current
        updateStatus(with: current)
    }
    
    private func updateStatus(with spaces: [String: [String]]) {
        var newStatus: [String: Bool] = [:]
        
        for (uuid, runningApps) in spaces {
            let shouldDetect: Bool
            if Defaults[.hideNotchOption] == .nowPlayingOnly, let musicSourceBundle = MusicManager.shared.bundleIdentifier  {
                shouldDetect = runningApps.contains(musicSourceBundle)
            } else {
                shouldDetect = true
            }
            newStatus[uuid] = shouldDetect
        }
        
        self.fullscreenStatus = newStatus
    }
}
