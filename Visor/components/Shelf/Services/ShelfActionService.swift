//
//  ShelfActionService.swift
//  
//
//  Created by Apurva on 2025-10-07.
//

import AppKit
import Foundation

/// A service providing common actions for `ShelfItem`s, such as opening, revealing, or copying paths.
@MainActor
enum ShelfActionService {

    static func open(_ item: ShelfItem) {
        switch item.kind {
        case .file(let bookmark):
            _ = Bookmark(data: bookmark).resolveURL()?.accessSecurityScopedResource { NSWorkspace.shared.open($0) }
        case .link(let url):
            NSWorkspace.shared.open(url)
        case .text(let string):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        }
    }
}

