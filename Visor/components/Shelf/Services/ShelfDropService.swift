//
//  ShelfDropService.swift
//  
//
//  Created by Apurva on 2025-09-26.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

struct ShelfDropService {
    static func items(from providers: [NSItemProvider]) async -> [ShelfItem] {
        var results: [ShelfItem] = []

        for provider in providers {
            if let item = await processProvider(provider) {
                results.append(item)
            }
        }

        return results
    }
    
    private static func processProvider(_ provider: NSItemProvider) async -> ShelfItem? {
        if let actualFileURL = await provider.extractFileURL() {
            return await fileItem(for: actualFileURL)
        }
        
        if let url = await provider.extractURL() {
            if url.isFileURL {
                return await fileItem(for: url)
            }
            return await ShelfItem(kind: .link(url: url), isTemporary: false)
        }
        
        if let text = await provider.extractText() {
            return await ShelfItem(kind: .text(string: text), isTemporary: false)
        }
        
        if let data = await provider.loadData() {
            guard let tempDataURL = await TemporaryFileStorageService.shared.createTempFile(for: .data(data, suggestedName: provider.suggestedName)) else { return nil }
            return await fileItem(for: tempDataURL, isTemporary: true)
        }
        
        if let fileURL = await provider.extractItem() {
            return await fileItem(for: fileURL)
        }
        
        return nil
    }
    
    // Visor: every file source made the same bookmark-then-item pair.
    private static func fileItem(for url: URL, isTemporary: Bool = false) async -> ShelfItem? {
        guard let bookmark = try? Bookmark(url: url) else { return nil }
        return await ShelfItem(kind: .file(bookmark: bookmark.data), isTemporary: isTemporary)
    }
}
