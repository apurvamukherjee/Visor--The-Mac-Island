//
//  SkyLightOperator.swift
//
//  From SkyLightWindow 1.0.0 (github.com/Lakr233/SkyLightWindow),
//  MIT License, Copyright (c) 2025 Lakr Aream.
//

import AppKit

// Visor: vendored from the SkyLightWindow package, which Visor used only for
// this. It moves a window into a private SkyLight space that draws above the
// lock screen. The calls are the package's; a missing symbol now leaves the
// window where it is instead of crashing.
final class SkyLightOperator {
    static let shared = SkyLightOperator()

    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias SpaceCreate = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsAndRemoveFromSpaces = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    private typealias RemoveWindowsFromSpaces = @convention(c) (Int32, CFArray, CFArray) -> Int32

    // kSLSSpaceAbsoluteLevelNotificationCenterAtScreenLock
    private static let aboveLockScreenLevel: Int32 = 400

    private let connection: Int32
    private let space: Int32?
    private let addWindows: AddWindowsAndRemoveFromSpaces?
    private let removeWindows: RemoveWindowsFromSpaces?

    private init() {
        let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW)
        func symbol<T>(_ name: String, as _: T.Type) -> T? {
            guard let skyLight, let pointer = dlsym(skyLight, name) else { return nil }
            return unsafeBitCast(pointer, to: T.self)
        }

        addWindows = symbol("SLSSpaceAddWindowsAndRemoveFromSpaces", as: AddWindowsAndRemoveFromSpaces.self)
        removeWindows = symbol("SLSRemoveWindowsFromSpaces", as: RemoveWindowsFromSpaces.self)

        guard let mainConnectionID = symbol("SLSMainConnectionID", as: MainConnectionID.self),
              let spaceCreate = symbol("SLSSpaceCreate", as: SpaceCreate.self),
              let setAbsoluteLevel = symbol("SLSSpaceSetAbsoluteLevel", as: SpaceSetAbsoluteLevel.self),
              let showSpaces = symbol("SLSShowSpaces", as: ShowSpaces.self)
        else {
            connection = 0
            space = nil
            return
        }

        connection = mainConnectionID()
        let created = spaceCreate(connection, 1, 0)
        _ = setAbsoluteLevel(connection, created, Self.aboveLockScreenLevel)
        _ = showSpaces(connection, [created] as CFArray)
        space = created
    }

    func delegateWindow(_ window: NSWindow) {
        guard let space, let addWindows else { return }
        _ = addWindows(connection, space, [window.windowNumber] as CFArray, 7)
    }

    func undelegateWindow(_ window: NSWindow) {
        guard let space, let removeWindows else { return }
        _ = removeWindows(connection, [window.windowNumber] as CFArray, [space] as CFArray)
    }
}
