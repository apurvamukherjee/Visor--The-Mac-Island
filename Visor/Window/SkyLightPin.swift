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
/// There is no teardown: the space and the connection belong to this process
/// and die with it, and the only caller pins once at launch.
enum SkyLightPin {
    /// Absolute levels are documented only by observation. 0 is the ordinary
    /// desktop set. 100 is the lowest level above it, which is what we want:
    /// above every normal window, but below the security agent (200) and the
    /// screen lock (300), so the island cannot paint over a locked screen.
    private static let aboveDesktopLevel: Int32 = 100

    /// The 7 is a flag whose meaning isn't documented; it is the value every
    /// known caller passes to move a window between spaces.
    private static let moveWindowFlags: Int32 = 7

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"

    /// The window must already be on screen — `windowNumber` is only valid
    /// once it has been ordered front.
    @discardableResult
    static func pin(_ window: NSWindow) -> Bool {
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
        let space = unsafeBitCast(createSymbol, to: SLSSpaceCreate.self)(connection, 1, 0)
        guard space != 0 else {
            Log.window.error("SkyLight space creation failed")
            return false
        }
        _ = unsafeBitCast(levelSymbol, to: SLSSpaceSetAbsoluteLevel.self)(
            connection, space, aboveDesktopLevel
        )
        _ = unsafeBitCast(showSymbol, to: SLSShowSpaces.self)(connection, [space] as CFArray)

        let moved = unsafeBitCast(moveSymbol, to: SLSSpaceAddWindowsAndRemoveFromSpaces.self)(
            connection, space, [window.windowNumber] as CFArray, moveWindowFlags
        )
        guard moved == 0 else {
            Log.window.error("SkyLight window move failed: \(moved)")
            return false
        }
        return true
    }
}
