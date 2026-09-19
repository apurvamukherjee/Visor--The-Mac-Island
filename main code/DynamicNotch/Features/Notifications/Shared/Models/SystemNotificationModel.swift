//
//  SystemNotificationModel.swift
//  DynamicNotch
//

internal import AppKit
import ApplicationServices
import Foundation

struct SystemNotificationModel: Identifiable, Equatable, @unchecked Sendable {
    let id: String
    let appName: String
    let title: String
    let subtitle: String?
    let body: String?
    let bundleIdentifier: String?
    let appIcon: NSImage?
    let receivedDate: Date
    let axElement: AXUIElement?

    init(
        id: String,
        appName: String,
        title: String,
        subtitle: String? = nil,
        body: String? = nil,
        bundleIdentifier: String? = nil,
        appIcon: NSImage? = nil,
        receivedDate: Date = Date(),
        axElement: AXUIElement? = nil
    ) {
        self.id = id
        self.appName = appName
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.bundleIdentifier = bundleIdentifier
        self.appIcon = appIcon
        self.receivedDate = receivedDate
        self.axElement = axElement
    }

    static func == (lhs: SystemNotificationModel, rhs: SystemNotificationModel) -> Bool {
        lhs.id == rhs.id &&
        lhs.appName == rhs.appName &&
        lhs.title == rhs.title &&
        lhs.subtitle == rhs.subtitle &&
        lhs.body == rhs.body &&
        lhs.bundleIdentifier == rhs.bundleIdentifier &&
        lhs.receivedDate == rhs.receivedDate
    }
}

#if DEBUG
extension SystemNotificationModel {
    static let debugPreview = SystemNotificationModel(
        id: "debug-telegram-1",
        appName: "Telegram",
        title: "Pavel Durov",
        subtitle: "Telegram News",
        body: "Dynamic Notch universal notification interceptor is now active on macOS!",
        bundleIdentifier: "ru.keepcoder.Telegram",
        appIcon: NSWorkspace.shared.icon(forFile: "/Applications/Telegram.app"),
        receivedDate: Date()
    )

    static let debugPreviewSlack = SystemNotificationModel(
        id: "debug-slack-1",
        appName: "Slack",
        title: "#development",
        subtitle: "Alice",
        body: "Build 2.4.0 passed all automated CI tests and is ready for release.",
        bundleIdentifier: "com.tinyspeck.slackmacgap",
        appIcon: NSWorkspace.shared.icon(forFile: "/Applications/Slack.app"),
        receivedDate: Date()
    )
}
#endif
