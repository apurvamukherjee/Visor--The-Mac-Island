import AppKit
import os

// Mirrors of the C declarations:
//   int  SLSMainConnectionID(void);
//   int  SLSSpaceCreate(int cid, int one, int zero);
//   CGError SLSSpaceSetAbsoluteLevel(int cid, int sid, int level);
//   CGError SLSShowSpaces(int cid, CFArrayRef spaces);
//   CGError SLSSpaceAddWindowsAndRemoveFromSpaces(int cid, int sid, CFArrayRef windows, int flags);
private typealias SLSMainConnectionID = @convention(c) () -> Int32
private typealias SLSSpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
private typealias SLSSpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
private typealias SLSShowSpaces = @convention(c) (Int32, CFArray) -> Int32
private typealias SLSSpaceAddWindowsAndRemoveFromSpaces = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
private typealias CGSCopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

/// Moves the island's panel into a private SkyLight space so it stops being a
/// desktop window.
///
/// `.canJoinAllSpaces` only makes a window *present* on every desktop — it
/// still belongs to the desktop layer, so a four-finger Space swipe drags it
/// along with the wallpaper instead of leaving it welded to the notch. A
/// space created with a non-zero absolute level sits outside the desktop set
/// entirely, the way the menu bar does: the desktops slide underneath it.
///
/// Every symbol here is private SkyLight API, resolved at runtime. If any
/// lookup fails — a future macOS renames or drops one — `pin` returns false
/// and the app keeps working as it otherwise would, minus the pinning.
/// Verified present on macOS 26.6; re-check after each major release.
///
/// There is no teardown: the spaces and the connection belong to this process
/// and die with it, and each caller pins once at launch.
enum SkyLightPin {
    /// Absolute levels are documented only by observation. 0 is the ordinary
    /// desktop set. 100 is the lowest level above it, which is what the main
    /// island wants: above every normal window, but below the security agent
    /// (200) and the screen lock (300), so it cannot paint over a locked
    /// screen. The lock-screen widget wants the opposite — it exists only
    /// while the shield is up — so it pins above 300 instead.
    enum Level: Int32 {
        /// The island proper: above the desktop, below the lock shield.
        case aboveDesktop = 100
        /// The lock-screen widget panel, above the shield.
        case aboveLockShield = 301
        /// The lock-screen notch mirror, above the widget.
        case aboveLockShieldNotch = 302
    }

    /// The 7 is a flag whose meaning isn't documented; it is the value every
    /// known caller passes to move a window between spaces.
    private static let moveWindowFlags: Int32 = 7

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"

    /// One space per level, created lazily and reused: a second space at the
    /// same level would be a second sibling the window server has to order,
    /// for no gain.
    private nonisolated(unsafe) static var spacesByLevel: [Level: Int32] = [:]

    /// The window must already be on screen — `windowNumber` is only valid
    /// once it has been ordered front.
    @discardableResult
    static func pin(_ window: NSWindow, level: Level = .aboveDesktop) -> Bool {
        guard
            let handle = dlopen(frameworkPath, RTLD_NOW),
            let connectionSymbol = dlsym(handle, "SLSMainConnectionID"),
            let createSymbol = dlsym(handle, "SLSSpaceCreate"),
            let levelSymbol = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
            let showSymbol = dlsym(handle, "SLSShowSpaces"),
            let moveSymbol = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else {
            Log.window.notice("SkyLight unavailable; island stays a desktop window")
            return false
        }
        let connection = unsafeBitCast(connectionSymbol, to: SLSMainConnectionID.self)()
        let space: Int32
        if let existing = spacesByLevel[level] {
            space = existing
        } else {
            let created = unsafeBitCast(createSymbol, to: SLSSpaceCreate.self)(connection, 1, 0)
            guard created != 0 else {
                Log.window.error("SkyLight space creation failed")
                return false
            }
            _ = unsafeBitCast(levelSymbol, to: SLSSpaceSetAbsoluteLevel.self)(
                connection, created, level.rawValue
            )
            _ = unsafeBitCast(showSymbol, to: SLSShowSpaces.self)(connection, [created] as CFArray)
            spacesByLevel[level] = created
            space = created
        }

        let moved = unsafeBitCast(moveSymbol, to: SLSSpaceAddWindowsAndRemoveFromSpaces.self)(
            connection, space, [window.windowNumber] as CFArray, moveWindowFlags
        )
        guard moved == 0 else {
            Log.window.error("SkyLight window move failed: \(moved)")
            return false
        }
        return true
    }

    /// True when the given screen is currently showing a full-screen space.
    ///
    /// Same private-framework risk class as `pin` above, and it fails the
    /// same way: an unavailable symbol or an unrecognised reply returns
    /// false, which is "not full screen" — the island stays visible, which
    /// is the behaviour anyone who has not turned the setting on already
    /// gets. Space type 4 is full screen; the value is documented only by
    /// observation, like the levels.
    static func isFullscreenSpaceActive(on screen: NSScreen) -> Bool {
        guard
            let handle = dlopen(frameworkPath, RTLD_NOW),
            let connectionSymbol = dlsym(handle, "SLSMainConnectionID"),
            let spacesSymbol = dlsym(handle, "CGSCopyManagedDisplaySpaces")
            ?? dlsym(handle, "SLSCopyManagedDisplaySpaces"),
            let displayIdentifier = screen.displayUUIDString
        else {
            return false
        }
        let connection = unsafeBitCast(connectionSymbol, to: SLSMainConnectionID.self)()
        guard
            let spaces = unsafeBitCast(spacesSymbol, to: CGSCopyManagedDisplaySpaces.self)(connection)?
            .takeRetainedValue() as? [[String: Any]],
            let entry = spaces.first(where: {
                ($0["Display Identifier"] as? String)?
                    .caseInsensitiveCompare(displayIdentifier) == .orderedSame
            }),
            let current = entry["Current Space"] as? [String: Any],
            let type = current["type"] as? NSNumber
        else {
            return false
        }
        return type.intValue == fullscreenSpaceType
    }

    /// Space "type" for a full-screen space. Observed, not documented.
    private static let fullscreenSpaceType = 4
}

extension NSScreen {
    /// The display's UUID string, which is how SkyLight names displays in
    /// `CGSCopyManagedDisplaySpaces` — `NSScreenNumber` is not.
    var displayUUIDString: String? {
        guard
            let displayID = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
            let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
        else {
            return nil
        }
        return (CFUUIDCreateString(nil, uuid) as String).uppercased()
    }

    var isBuiltInDisplay: Bool {
        guard let displayID = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return false
        }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    /// True on a screen with no physical cutout, where the island has to draw
    /// itself as a free-floating capsule rather than hiding its top edge
    /// behind hardware. `safeAreaInsets.top` is 0 on such a screen; on a
    /// notched one it is the menu bar's height.
    var isDynamicIsland: Bool {
        safeAreaInsets.top == 0
    }
}
