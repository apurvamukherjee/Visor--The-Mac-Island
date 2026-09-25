//
//  TemporaryFileStorageService.swift
//  
//
//  Created by Apurva on 2025-09-24.
//

import Foundation
import AppKit
import UniformTypeIdentifiers

enum TempFileType {
    case data(Data, suggestedName: String?)
    case text(String)
}

class TemporaryFileStorageService {
    static let shared = TemporaryFileStorageService()
    
    // MARK: - Public Interface
    
    func removeTemporaryFileIfNeeded(at url: URL) {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())

        guard url.path.hasPrefix(tempDirectory.path) else {
            print("Attempted to remove temporary file outside temp directory: \(url.path)")
            return
        }

        let folderURL = url.deletingLastPathComponent()

        do {
            try FileManager.default.removeItem(at: url)
            print("Deleted file: \(url.path)")

            let contents = try FileManager.default.contentsOfDirectory(atPath: folderURL.path)
            if contents.isEmpty {
                try FileManager.default.removeItem(at: folderURL)
                print("Folder was empty, deleted folder: \(folderURL.path)")
            } else {
                print("Folder not deleted — it still contains \(contents.count) item(s).")
            }

        } catch {
            print("Error: \(error.localizedDescription)")
        }
    }
    
    // Visor: was a sync twin behind an async withCheckedContinuation wrapper.
    /// Creates a temporary file and tracks it for manual cleanup
    func createTempFile(for type: TempFileType) async -> URL? {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let uuid = UUID().uuidString
        let data: Data
        let filename: String
        switch type {
        case .data(let fileData, let suggestedName):
            data = fileData
            filename = suggestedName ?? ".dat"
        case .text(let string):
            data = Data(string.utf8)
            filename = "\(uuid).txt"
        }

        let dirURL = tempDir.appendingPathComponent(uuid, isDirectory: true)
        let fileURL = dirURL.appendingPathComponent(filename)
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
            try data.write(to: fileURL)
            return fileURL
        } catch {
            print("Error: \(error)")
            return nil
        }
    }
    
    func createZip(from urls: [URL]) async -> URL? {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let uuid = UUID().uuidString
        let workingDir = tempDir.appendingPathComponent("zip_\(uuid)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: workingDir, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create zip working directory: \(error)")
            return nil
        }

        // Helper to run zip process
        func runZip(arguments: [String], currentDirectory: URL) -> Bool {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            proc.arguments = arguments
            proc.currentDirectoryURL = currentDirectory
            do {
                try proc.run()
                proc.waitUntilExit()
                return proc.terminationStatus == 0
            } catch {
                print("❌ Failed to run zip: \(error)")
                return false
            }
        }

        // Single-item optimization: do not copy contents into the working dir.
        if urls.count == 1, let src = urls.first {
            let isDir = (try? src.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            let baseName = src.lastPathComponent
            let archiveURL = workingDir.appendingPathComponent("\(baseName).zip")
            // Visor: run from the parent; -r stores a folder as the top-level entry, -j stores a file without its path.
            let args = [isDir ? "-r" : "-j", "-q", archiveURL.path, baseName]
            return runZip(arguments: args, currentDirectory: src.deletingLastPathComponent()) ? archiveURL : nil
        }

        // Multi-item: copy items into working dir (so their relative structure is preserved), zip, then remove copies.
        for src in urls {
            let dest = workingDir.appendingPathComponent(src.lastPathComponent)
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    // Avoid collision by appending a suffix
                    let unique = "\(UUID().uuidString)_\(src.lastPathComponent)"
                    try FileManager.default.copyItem(at: src, to: workingDir.appendingPathComponent(unique))
                } else {
                    try FileManager.default.copyItem(at: src, to: dest)
                }
            } catch {
                print("⚠️ Failed to copy \(src.path) to working dir: \(error)")
            }
        }

        let archiveURL = workingDir.appendingPathComponent("Archive.zip")
        let args = ["-r", "-q", archiveURL.path, "."]
        let ok = runZip(arguments: args, currentDirectory: workingDir)
        if ok {
            // Remove the copied (uncompressed) items so the temp folder contains only the archive
            do {
                let contents = try FileManager.default.contentsOfDirectory(at: workingDir, includingPropertiesForKeys: nil)
                for file in contents {
                    if file.standardizedFileURL != archiveURL.standardizedFileURL {
                        try FileManager.default.removeItem(at: file)
                    }
                }
            } catch {
                print("⚠️ Failed to cleanup working directory after zip: \(error)")
            }
            return archiveURL
        } else {
            return nil
        }
    }
    
}
