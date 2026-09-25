//
//  QuickLookService.swift
//  
//
//  Created by Apurva on 2025-10-07.
//

import Foundation
import UniformTypeIdentifiers
import SwiftUI
import QuickLookUI
import AppKit

@MainActor
final class QuickLookService: ObservableObject {
    @Published var urls: [URL] = []
    @Published var selectedURL: URL?

    @Published var isQuickLookOpen: Bool = false

    private var previewPanel: QLPreviewPanel?
    private var accessingURLs: [URL] = []

    func show(urls: [URL]) {
        guard !urls.isEmpty else { return }
        stopAccessingCurrentURLs()
        accessingURLs = urls.filter { url in
            if url.isFileURL {
                return url.startAccessingSecurityScopedResource()
            }
            return true
        }
        self.urls = accessingURLs
        self.isQuickLookOpen = true
        self.selectedURL = accessingURLs.first
        // Observe the shared Quick Look preview panel closing so we can relinquish security scope.
        // Visor: stopAccessingCurrentURLs above already removed the previous observer.
        let panel = QLPreviewPanel.shared()
        previewPanel = panel
        NotificationCenter.default.addObserver(self, selector: #selector(previewPanelWillClose(_:)), name: NSWindow.willCloseNotification, object: panel)
    }

    private func stopAccessingCurrentURLs() {
        NSLog("Stopping access to \(accessingURLs.count) URLs")
        for url in accessingURLs where url.isFileURL {
            url.stopAccessingSecurityScopedResource()
        }
        accessingURLs.removeAll()
        // If Quick Look panel was closed externally, also remove observer and clear reference
        if let panel = previewPanel {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: panel)
            previewPanel = nil
        }
    }
    
    func updateSelection(urls: [URL]) {
        guard isQuickLookOpen else { return }
        show(urls: urls)
    }
}

extension QuickLookService {
    @objc private func previewPanelWillClose(_ notification: Notification) {
        guard let panel = notification.object as? QLPreviewPanel, panel === previewPanel else { return }
        // Ensure cleanup happens on main actor
        Task { @MainActor in
            stopAccessingCurrentURLs()
            selectedURL = nil
            urls.removeAll()
            isQuickLookOpen = false
        }
    }
}
