import AppKit
import os

// Mirrors of the C declarations, kept at file scope so they read as the
// foreign function signatures they are:
//   int  SLSMainConnectionID(void);
//   int  SLSSpaceCreate(int cid, int one, int zero);
//   CGError SLSSpaceDestroy(int cid, int sid);
//   CGError SLSSpaceSetAbsoluteLevel(int cid, int sid, int level);
//   CGError SLSShowSpaces(int cid, CFArrayRef spaces);
//   CGError SLSHideSpaces(int cid, CFArrayRef spaces);
//   CGError SLSSpaceAddWindowsAndRemoveFromSpaces(int cid, int sid, CFArrayRef windows, int flags);
//   CGError SLSRemoveWindowsFromSpaces(int cid, CFArrayRef windows, CFArrayRef spaces);
private typealias SLSMainConnectionID = @convention(c) () -> Int32
private typealias SLSSpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
private typealias SLSSpaceDestroy = @convention(c) (Int32, Int32) -> Int32
private typealias SLSSpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
private typealias SLSShowSpaces = @convention(c) (Int32, CFArray) -> Int32
private typealias SLSHideSpaces = @convention(c) (Int32, CFArray) -> Int32
private typealias SLSSpaceAddWindowsAndRemoveFromSpaces = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
private typealias SLSRemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32

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
/// and the app keeps working exactly as it does today, minus the pinning.
/// Verified present on macOS 26.6; re-check after each major release.
@MainActor
final class SkyLightPin {
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

    private struct Symbols {
        let mainConnectionID: SLSMainConnectionID
        let spaceCreate: SLSSpaceCreate
        let spaceDestroy: SLSSpaceDestroy
        let spaceSetAbsoluteLevel: SLSSpaceSetAbsoluteLevel
        let showSpaces: SLSShowSpaces
        let hideSpaces: SLSHideSpaces
        let addWindowsAndRemoveFromSpaces: SLSSpaceAddWindowsAndRemoveFromSpaces
        let removeWindowsFromSpaces: SLSRemoveWindowsFromSpaces

        init?(handle: UnsafeMutableRawPointer) {
            guard
                let connection = dlsym(handle, "SLSMainConnectionID"),
                let create = dlsym(handle, "SLSSpaceCreate"),
                let destroy = dlsym(handle, "SLSSpaceDestroy"),
                let setLevel = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
                let show = dlsym(handle, "SLSShowSpaces"),
                let hide = dlsym(handle, "SLSHideSpaces"),
                let add = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces"),
                let remove = dlsym(handle, "SLSRemoveWindowsFromSpaces")
            else {
                return nil
            }
            mainConnectionID = unsafeBitCast(connection, to: SLSMainConnectionID.self)
            spaceCreate = unsafeBitCast(create, to: SLSSpaceCreate.self)
            spaceDestroy = unsafeBitCast(destroy, to: SLSSpaceDestroy.self)
            spaceSetAbsoluteLevel = unsafeBitCast(setLevel, to: SLSSpaceSetAbsoluteLevel.self)
            showSpaces = unsafeBitCast(show, to: SLSShowSpaces.self)
            hideSpaces = unsafeBitCast(hide, to: SLSHideSpaces.self)
            addWindowsAndRemoveFromSpaces = unsafeBitCast(add, to: SLSSpaceAddWindowsAndRemoveFromSpaces.self)
            removeWindowsFromSpaces = unsafeBitCast(remove, to: SLSRemoveWindowsFromSpaces.self)
        }
    }

    private var handle: UnsafeMutableRawPointer?
    private var symbols: Symbols?
    private var connection: Int32?
    private var space: Int32?
    private var pinnedWindowNumber: Int?

    /// The window must already be on screen — `windowNumber` is only valid
    /// once it has been ordered front.
    @discardableResult
    func pin(_ window: NSWindow) -> Bool {
        guard pinnedWindowNumber == nil else { return true }
        guard let symbols = loadSymbols() else {
            Log.window.notice("SkyLight unavailable; island stays a desktop window")
            return false
        }
        let connection = connection ?? symbols.mainConnectionID()
        self.connection = connection

        let space = try? space ?? makeSpace(symbols: symbols, connection: connection)
        guard let space else { return false }
        self.space = space

        let result = symbols.addWindowsAndRemoveFromSpaces(
            connection,
            space,
            [window.windowNumber] as CFArray,
            Self.moveWindowFlags
        )
        guard result == 0 else {
            Log.window.error("SkyLight window move failed: \(result)")
            return false
        }
        pinnedWindowNumber = window.windowNumber
        return true
    }

    /// Hands the window back to the desktop layer and tears the space down.
    func unpin() {
        guard let symbols, let connection, let space else { return }
        if let pinnedWindowNumber {
            _ = symbols.removeWindowsFromSpaces(
                connection,
                [pinnedWindowNumber] as CFArray,
                [space] as CFArray
            )
        }
        _ = symbols.hideSpaces(connection, [space] as CFArray)
        _ = symbols.spaceDestroy(connection, space)
        pinnedWindowNumber = nil
        self.space = nil
        if let handle {
            dlclose(handle)
        }
        handle = nil
        self.symbols = nil
    }

    private struct SpaceCreationFailed: Error {}

    private func makeSpace(symbols: Symbols, connection: Int32) throws -> Int32 {
        let space = symbols.spaceCreate(connection, 1, 0)
        guard space != 0 else {
            Log.window.error("SkyLight space creation failed")
            throw SpaceCreationFailed()
        }
        _ = symbols.spaceSetAbsoluteLevel(connection, space, Self.aboveDesktopLevel)
        _ = symbols.showSpaces(connection, [space] as CFArray)
        return space
    }

    private func loadSymbols() -> Symbols? {
        if let symbols {
            return symbols
        }
        guard
            let handle = handle ?? dlopen(Self.frameworkPath, RTLD_NOW),
            let symbols = Symbols(handle: handle)
        else {
            return nil
        }
        self.handle = handle
        self.symbols = symbols
        return symbols
    }
}
