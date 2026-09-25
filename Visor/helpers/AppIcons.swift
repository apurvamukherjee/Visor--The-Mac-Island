//
//  AppIcons.swift
//  
//
//  Created by Apurva   on 16/08/24.
//

import SwiftUI
import AppKit

// Visor: the generic application icon when the bundle ID has no app.
func AppIcon(for bundleID: String) -> Image {
    Image(nsImage: AppIconAsNSImage(for: bundleID) ?? NSWorkspace.shared.icon(for: .applicationBundle))
}

func AppIconAsNSImage(for bundleID: String) -> NSImage? {
    let workspace = NSWorkspace.shared
    
    if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleID) {
        let appIcon = workspace.icon(forFile: appURL.path)
        appIcon.size = NSSize(width: 256, height: 256)
        return appIcon
    }
    return nil
}

