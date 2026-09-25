//
//  FullScreenSpaces.swift
//
//  From MacroVisionKit 0.2.0 (github.com/TheBoredTeam/MacroVisionKit),
//  MIT License, Copyright (c) 2024 github.com/theboringhumane.
//

import AppKit

// Visor: vendored from the MacroVisionKit package, which Visor used only for
// this. It reads which displays show a full-screen space and which apps fill
// it. The CGS calls are the package's, resolved at runtime: if macOS drops
// one, no space reads as full screen, where a link-time binding would stop
// Visor from launching.
enum FullScreenSpaces {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let calls: (mainConnectionID: MainConnectionID, copySpaces: CopyManagedDisplaySpaces)? = {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let mainConnectionID = dlsym(defaultHandle, "CGSMainConnectionID"),
              let copySpaces = dlsym(defaultHandle, "CGSCopyManagedDisplaySpaces")
        else { return nil }
        return (
            unsafeBitCast(mainConnectionID, to: MainConnectionID.self),
            unsafeBitCast(copySpaces, to: CopyManagedDisplaySpaces.self)
        )
    }()

    /// The bundle IDs filling each display's current full-screen space, keyed
    /// by display UUID. Displays showing a normal space are absent.
    static func current() -> [String: [String]] {
        guard let calls,
              let displaySpaces = calls.copySpaces(calls.mainConnectionID())?.takeRetainedValue() as? [NSDictionary]
        else { return [:] }

        var result: [String: [String]] = [:]
        for displayDict in displaySpaces {
            guard let currentSpaceDict = displayDict["Current Space"] as? [String: Any],
                  let spacesList = displayDict["Spaces"] as? [[String: Any]],
                  let displayID = displayDict["Display Identifier"] as? String
            else { continue }

            let activeSpaceID = currentSpaceDict["ManagedSpaceID"] as? Int ?? -1
            guard let activeSpace = spacesList.first(where: { ($0["ManagedSpaceID"] as? Int) == activeSpaceID }),
                  let tileLayoutManager = activeSpace["TileLayoutManager"] as? [String: Any]
            else { continue }

            // The space's own app first, then any split-view tiles
            let tiles = tileLayoutManager["TileSpaces"] as? [[String: Any]] ?? []
            var runningApps: [String] = []
            for pid in [activeSpace["pid"]] + tiles.map({ $0["pid"] }) {
                if let pid = pid as? Int32,
                   let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                   !runningApps.contains(bundleID) {
                    runningApps.append(bundleID)
                }
            }
            result[displayID] = runningApps
        }
        return result
    }
}
