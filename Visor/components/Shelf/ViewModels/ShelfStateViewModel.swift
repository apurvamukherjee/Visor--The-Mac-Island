//
//  ShelfStateViewModel.swift
//  
//
//  Created by Apurva on 2025-10-09.

import Foundation
import AppKit

@MainActor
final class ShelfStateViewModel: ObservableObject {
    static let shared = ShelfStateViewModel()

    @Published private(set) var items: [ShelfItem] = [] {
        didSet { ShelfPersistenceService.shared.save(items) }
    }


    var isEmpty: Bool { items.isEmpty }

    // Queue for deferred bookmark updates to avoid publishing during view updates
    private var pendingBookmarkUpdates: [ShelfItem.ID: Data] = [:]
    private var updateTask: Task<Void, Never>?

    private init() {
        items = ShelfPersistenceService.shared.load()
    }


    func add(_ newItems: [ShelfItem]) {
        guard !newItems.isEmpty else { return }
        var merged = items
        // Deduplicate by identityKey while preserving order (existing first)
        var seen: Set<String> = Set(merged.map { $0.identityKey })
        for it in newItems {
            let key = it.identityKey
            if !seen.contains(key) {
                merged.append(it)
                seen.insert(key)
            }
        }
        items = merged
    }

    func remove(_ item: ShelfItem) {
        item.cleanupStoredData()
        items.removeAll { $0.id == item.id }
    }

    func updateBookmark(for item: ShelfItem, bookmark: Data) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        if case .file = items[idx].kind {
            items[idx].kind = .file(bookmark: bookmark)
        }
    }

    private func scheduleDeferredBookmarkUpdate(for item: ShelfItem, bookmark: Data) {
        pendingBookmarkUpdates[item.id] = bookmark
        
        // Cancel existing task and schedule a new one
        updateTask?.cancel()
        updateTask = Task { @MainActor [weak self] in
            await Task.yield()
            
            guard let self = self else { return }
            
            for (itemID, bookmarkData) in self.pendingBookmarkUpdates {
                if let idx = self.items.firstIndex(where: { $0.id == itemID }),
                   case .file = self.items[idx].kind {
                    self.items[idx].kind = .file(bookmark: bookmarkData)
                }
            }
            
            self.pendingBookmarkUpdates.removeAll()
        }
    }


    func load(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        Task { [weak self] in
            let dropped = await ShelfDropService.items(from: providers)
            await MainActor.run {
                self?.add(dropped)
            }
        }
    }

    func cleanupInvalidItems() {
        Task { [weak self] in
            guard let self else { return }
            let snapshot = self.items
            var keep: [ShelfItem] = []
            for item in snapshot {
                switch item.kind {
                case .file(let data):
                    let bookmark = Bookmark(data: data)
                    if await bookmark.validate() {
                        keep.append(item)
                    } else {
                        item.cleanupStoredData()
                    }
                default:
                    keep.append(item)
                }
            }
            // Visor: assigning unconditionally re-saved the shelf to disk and
            // re-rendered it on every shelf open, even with nothing removed.
            guard keep.count != snapshot.count else { return }
            await MainActor.run { self.items = keep }
        }
    }


    /// Resolves a file item's URL, deferring a stale-bookmark refresh so it
    /// is safe to call during a view update.
    func resolveFileURL(for item: ShelfItem) -> URL? {
        resolve(item, refresh: scheduleDeferredBookmarkUpdate)
    }

    /// Resolves a file item's URL and stores a refreshed bookmark at once,
    /// for user-initiated actions.
    func resolveAndUpdateBookmark(for item: ShelfItem) -> URL? {
        resolve(item, refresh: updateBookmark)
    }

    // Visor: the two public resolvers differed only in how they stored a
    // refreshed bookmark.
    private func resolve(_ item: ShelfItem, refresh: (ShelfItem, Data) -> Void) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let result = Bookmark(data: bookmarkData).resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            refresh(item, refreshed)
        }
        return result.url
    }

}
