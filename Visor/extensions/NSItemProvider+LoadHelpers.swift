//
//  NSItemProvider+LoadHelpers.swift
//  
//
//  Created by Apurva on 2025-09-24.
//


import AppKit
import Foundation
import UniformTypeIdentifiers

extension NSItemProvider {
    
    func extractItem() async -> URL? {
        return await loadFileURL(typeIdentifier: UTType.item.identifier)
    }

    
    /// Detects if this is a file dragged from the filesystem
    func extractFileURL() async -> URL? {
        if hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await loadFileURL(typeIdentifier: UTType.fileURL.identifier)
        }
        return nil
    }
    
    /// Loads raw data for the given type identifier
    func loadData() async -> Data? {
        NSLog(String(describing: self.registeredTypeIdentifiers))
        guard hasItemConformingToTypeIdentifier(UTType.data.identifier) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            loadItem(forTypeIdentifier: UTType.data.identifier, options: nil) { item, error in
                if let error = error {
                    print("Error loading data for type \(UTType.data.identifier): \(error.localizedDescription)")
                    cont.resume(returning: nil)
                    return
                }
                // Visor: checked before reading, so dropping a large ordinary file
                // no longer loads all of it into memory only to return nil.
                if let url = item as? URL, !url.absoluteString.contains("com.apple.SwiftUI.filePromises") {
                    cont.resume(returning: nil)
                    return
                }
                if let url = item as? URL, let data = try? Data(contentsOf: url) {
                    self.suggestedName = self.suggestedName ?? url.lastPathComponent
                    
                    let fileManager = FileManager.default
                    let folderURL = url.deletingLastPathComponent()

                    do {
                        // Delete the file first
                        try fileManager.removeItem(at: url)
                        print("Deleted file: \(url.path)")

                        // Check folder contents
                        let contents = try fileManager.contentsOfDirectory(atPath: folderURL.path)
                        if contents.isEmpty {
                            try fileManager.removeItem(at: folderURL)
                            print("Folder was empty, deleted folder: \(folderURL.path)")
                        } else {
                            print("Folder not deleted — it still contains \(contents.count) item(s).")
                        }

                    } catch {
                        print("Error: \(error.localizedDescription)")
                    }
                    
                    cont.resume(returning: data)
                } else if let data = item as? Data {
                    cont.resume(returning: data)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// Attempts to extract a URL (web link) from the provider
    func extractURL() async -> URL? {
        guard hasItemConformingToTypeIdentifier(UTType.url.identifier),
              let url = await loadFileURL(typeIdentifier: UTType.url.identifier),
              url.scheme != nil
        else { return nil }
        return url
    }

    func extractText() async -> String? {
        let textTypes = [UTType.utf8PlainText.identifier, UTType.plainText.identifier]

        for typeIdentifier in textTypes where self.hasItemConformingToTypeIdentifier(typeIdentifier) {
            if let text = await loadText(typeIdentifier: typeIdentifier) {
                return text
            }
        }

        return nil
    }

    /// Loads a file URL from the provider for the given type identifier.
    func loadFileURL(typeIdentifier: String) async -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            self.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if let error = error {
                    print("❌ Error loading item for type \(typeIdentifier): \(error.localizedDescription)")
                    cont.resume(returning: nil)
                    return
                }
                if let url = item as? URL {
                    cont.resume(returning: url)
                    return
                }
                // Some providers hand out a UTF-8 file URL string, others a bookmark. Prefer parsing string first.
                let data = item as? Data
                let string = (item as? String) ?? data.flatMap { String(data: $0, encoding: .utf8) }
                let parsed = string.flatMap { URL(string: $0) ?? ($0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil) }
                cont.resume(returning: parsed ?? data.flatMap { Bookmark(data: $0).resolveURL() })
            }
        }
    }

    /// Loads text from the provider for the given type identifier.
    func loadText(typeIdentifier: String) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            self.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                if error != nil {
                    cont.resume(returning: nil)
                    return
                }

                if let string = item as? String {
                    cont.resume(returning: string)
                } else if let data = item as? Data,
                          let string = String(data: data, encoding: .utf8) {
                    cont.resume(returning: string)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}
