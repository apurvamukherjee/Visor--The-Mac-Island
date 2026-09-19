//
//  SystemNotificationsInterceptor.swift
//  DynamicNotch
//

internal import AppKit
import ApplicationServices
import Combine
import Foundation
import os.log

@MainActor
final class SystemNotificationsInterceptor {
    private let logger = Logger(subsystem: "com.dynamicnotch", category: "SystemNotificationsInterceptor")
    private let notificationCenterBundleID = "com.apple.notificationcenterui"

    var onNotificationReceived: ((SystemNotificationModel) -> Void)?

    private var observer: AXObserver?
    private var runLoopSource: CFRunLoopSource?
    private var targetPID: pid_t = 0
    private var isMonitoring = false
    private var processedNotificationIDs: [String: Date] = [:]
    private var workspaceCancellables = Set<AnyCancellable>()

    var isEnabled: Bool = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }

    var hideNativeBanners: Bool = true

    init() {
        setupWorkspaceListeners()
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        guard isEnabled else { return }
        guard AXIsProcessTrusted() else {
            logger.debug("Accessibility access is not granted. Interceptor will not start yet.")
            return
        }

        guard let ncApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == notificationCenterBundleID
        }) else {
            logger.debug("NotificationCenter process not found.")
            return
        }

        let pid = ncApp.processIdentifier
        if isMonitoring && targetPID == pid {
            return
        }

        stopMonitoring()
        attachObserver(to: pid)
    }

    func stopMonitoring() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
            self.runLoopSource = nil
            self.observer = nil
        }
        targetPID = 0
        isMonitoring = false
    }

    private func setupWorkspaceListeners() {
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .filter { [weak self] app in app.bundleIdentifier == self?.notificationCenterBundleID }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] app in
                self?.logger.debug("NotificationCenter launched with PID \(app.processIdentifier)")
                self?.startMonitoring()
            }
            .store(in: &workspaceCancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)
            .compactMap { $0.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication }
            .filter { [weak self] app in app.bundleIdentifier == self?.notificationCenterBundleID }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.logger.debug("NotificationCenter terminated")
                self?.stopMonitoring()
            }
            .store(in: &workspaceCancellables)
    }

    // MARK: - AXObserver Setup

    private func attachObserver(to pid: pid_t) {
        var newObserver: AXObserver?
        let callback: AXObserverCallback = { (observer, element, notification, refcon) in
            guard let refcon else { return }
            let interceptor = Unmanaged<SystemNotificationsInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            let notifName = notification as String
            DispatchQueue.main.async {
                interceptor.handleAXEvent(notification: notifName, element: element)
            }
        }

        let error = AXObserverCreate(pid, callback, &newObserver)
        guard error == .success, let newObserver else {
            logger.error("Failed to create AXObserver for PID \(pid), error: \(error.rawValue)")
            return
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let appElement = AXUIElementCreateApplication(pid)

        let notificationsToObserve = [
            kAXWindowCreatedNotification,
            kAXCreatedNotification,
            kAXLayoutChangedNotification
        ]

        for notif in notificationsToObserve {
            _ = AXObserverAddNotification(newObserver, appElement, notif as CFString, refcon)
        }

        let source = AXObserverGetRunLoopSource(newObserver)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)

        self.observer = newObserver
        self.runLoopSource = source
        self.targetPID = pid
        self.isMonitoring = true
        logger.notice("SystemNotificationsInterceptor successfully attached to NotificationCenter (PID: \(pid))")
    }

    // MARK: - Event Handling

    private func handleAXEvent(notification: String, element: AXUIElement) {
        guard isEnabled else { return }

        // Clean stale processed IDs older than 30 seconds
        let now = Date()
        processedNotificationIDs = processedNotificationIDs.filter { now.timeIntervalSince($0.value) < 30 }

        // 1. If element itself is a window, hide it offscreen
        let role: String = copyAttribute(kAXRoleAttribute, from: element) ?? ""
        if role == (kAXWindowRole as String) && hideNativeBanners {
            hideWindowOffscreen(element)
        }

        // 2. Look for banners in the event element
        let elementBanners = findBanners(in: element)
        for banner in elementBanners {
            processBanner(banner)
        }

        // 3. Also check all application windows
        let appElement = AXUIElementCreateApplication(targetPID)
        if let windows: [AXUIElement] = copyAttribute(kAXWindowsAttribute, from: appElement) {
            for window in windows {
                if hideNativeBanners {
                    hideWindowOffscreen(window)
                }
                inspectWindowForBanners(window)
            }
        }
    }

    private func hideWindowOffscreen(_ window: AXUIElement) {
        var offscreenPoint = CGPoint(x: 50000, y: 50000)
        if let axVal = AXValueCreate(.cgPoint, &offscreenPoint) {
            _ = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, axVal)
        }
    }

    private func inspectWindowForBanners(_ element: AXUIElement) {
        let banners = findBanners(in: element)
        for banner in banners {
            processBanner(banner)
        }
    }

    private func findBanners(in element: AXUIElement) -> [AXUIElement] {
        var result: [AXUIElement] = []
        let subrole: String = copyAttribute(kAXSubroleAttribute, from: element) ?? ""
        if subrole.contains("Banner") || subrole.contains("Alert") {
            result.append(element)
        }

        if let children: [AXUIElement] = copyAttribute(kAXChildrenAttribute, from: element) {
            for child in children {
                result.append(contentsOf: findBanners(in: child))
            }
        }
        return result
    }

    private func processBanner(_ banner: AXUIElement) {
        let bannerID: String = copyAttribute(kAXIdentifierAttribute, from: banner) ?? UUID().uuidString
        if processedNotificationIDs[bannerID] != nil {
            return
        }
        processedNotificationIDs[bannerID] = Date()

        // Extract title, subtitle, body from children
        var title: String = ""
        var subtitle: String?
        var body: String?

        if let children: [AXUIElement] = copyAttribute(kAXChildrenAttribute, from: banner) {
            for child in children {
                let id: String = copyAttribute(kAXIdentifierAttribute, from: child) ?? ""
                let val: String = copyAttribute(kAXValueAttribute, from: child) ?? ""
                switch id {
                case "title":
                    title = val
                case "subtitle":
                    subtitle = val.isEmpty ? nil : val
                case "body":
                    body = val.isEmpty ? nil : val
                default:
                    break
                }
            }
        }

        // Extract app name from description or attributed description
        let rawDesc: String = copyAttribute(kAXDescriptionAttribute, from: banner) ?? ""
        var appName = parseAppName(from: rawDesc, title: title)

        if appName.isEmpty {
            appName = title
        }

        if title.isEmpty && !appName.isEmpty {
            title = appName
        }

        // Check if app was dispatched via script runner (osascript, Script Editor, Terminal)
        let scriptRunners = [
            "редактор скриптов", "script editor", "osascript", "терминал", "terminal"
        ]
        let isScriptRunner = scriptRunners.contains(where: { appName.localizedCaseInsensitiveCompare($0) == .orderedSame })

        var bundleID: String?
        var icon: NSImage?

        // 1. If sent via script runner and title matches a real app (e.g. "Telegram", "Slack", "Safari"):
        if isScriptRunner {
            let candidateApp = resolveAppInfo(named: title)
            if candidateApp.icon != nil {
                appName = title
                title = subtitle ?? appName
                subtitle = nil
                bundleID = candidateApp.bundleID
                icon = candidateApp.icon
            }
        }

        // 2. Normal resolution for appName
        if icon == nil {
            let resolved = resolveAppInfo(named: appName)
            bundleID = resolved.bundleID
            icon = resolved.icon
        }

        // 3. Fallback: if appName failed to find an icon, try resolving via title
        if icon == nil && !title.isEmpty && title.caseInsensitiveCompare(appName) != .orderedSame {
            let fallbackResolved = resolveAppInfo(named: title)
            if fallbackResolved.icon != nil {
                bundleID = fallbackResolved.bundleID
                icon = fallbackResolved.icon
            }
        }

        let model = SystemNotificationModel(
            id: bannerID,
            appName: appName,
            title: title,
            subtitle: subtitle,
            body: body,
            bundleIdentifier: bundleID,
            appIcon: icon,
            receivedDate: Date(),
            axElement: banner
        )

        logger.notice("Captured system notification: [\(appName)] \(title) - \(subtitle ?? ""): \(body ?? "")")
        onNotificationReceived?(model)
    }

    private func parseAppName(from description: String, title: String) -> String {
        guard !description.isEmpty else { return title }
        let parts = description.components(separatedBy: ", ")
        if let first = parts.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty {
            return first
        }
        return title
    }

    private static let knownAppAliases: [String: String] = [
        "telegram": "ru.keepcoder.Telegram",
        "телеграм": "ru.keepcoder.Telegram",
        "slack": "com.tinyspeck.slackmacgap",
        "слэк": "com.tinyspeck.slackmacgap",
        "chrome": "com.google.Chrome",
        "google chrome": "com.google.Chrome",
        "хром": "com.google.Chrome",
        "safari": "com.apple.Safari",
        "сафари": "com.apple.Safari",
        "почта": "com.apple.mail",
        "mail": "com.apple.mail",
        "сообщения": "com.apple.MobileSMS",
        "messages": "com.apple.MobileSMS",
        "календарь": "com.apple.iCal",
        "calendar": "com.apple.iCal",
        "напоминания": "com.apple.reminders",
        "reminders": "com.apple.reminders",
        "заметки": "com.apple.Notes",
        "notes": "com.apple.Notes",
        "музыка": "com.apple.Music",
        "music": "com.apple.Music",
        "подкасты": "com.apple.podcasts",
        "podcasts": "com.apple.podcasts",
        "настройки": "com.apple.systempreferences",
        "системные настройки": "com.apple.systempreferences",
        "system settings": "com.apple.systempreferences",
        "settings": "com.apple.systempreferences",
        "редактор скриптов": "com.apple.ScriptEditor2",
        "script editor": "com.apple.ScriptEditor2",
        "terminal": "com.apple.Terminal",
        "терминал": "com.apple.Terminal",
        "whatsapp": "net.whatsapp.WhatsApp",
        "ватсап": "net.whatsapp.WhatsApp",
        "discord": "com.hnc.Discord",
        "дискорд": "com.hnc.Discord",
        "notion": "notion.id",
        "ноушен": "notion.id",
        "zoom": "us.zoom.xos",
        "зум": "us.zoom.xos",
        "xcode": "com.apple.dt.Xcode",
        "finder": "com.apple.finder",
        "файлы": "com.apple.finder",
        "app store": "com.apple.AppStore"
    ]

    private func resolveAppInfo(named name: String) -> (bundleID: String?, icon: NSImage?) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return (nil, nil) }

        // 1. Check running applications by localized name
        for app in NSWorkspace.shared.runningApplications {
            if let locName = app.localizedName, locName.localizedCaseInsensitiveCompare(cleanName) == .orderedSame {
                let icon = app.icon
                icon?.size = NSSize(width: 128, height: 128)
                return (app.bundleIdentifier, icon)
            }
        }

        // 2. Check running applications by bundle identifier
        for app in NSWorkspace.shared.runningApplications {
            if let bid = app.bundleIdentifier, bid.localizedCaseInsensitiveCompare(cleanName) == .orderedSame {
                let icon = app.icon
                icon?.size = NSSize(width: 128, height: 128)
                return (bid, icon)
            }
        }

        // 3. Known aliases dictionary
        if let bundleID = Self.knownAppAliases[cleanName.lowercased()] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 128, height: 128)
                return (bundleID, icon)
            }
        }

        // 4. NSWorkspace urlForApplication withBundleIdentifier directly
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: cleanName) {
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 128, height: 128)
            let bundle = Bundle(url: url)
            return (bundle?.bundleIdentifier ?? cleanName, icon)
        }

        // 5. Standard app directories
        let searchDirectories = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]

        for directory in searchDirectories {
            let appURL = directory.appendingPathComponent("\(cleanName).app")
            if FileManager.default.fileExists(atPath: appURL.path) {
                let bundle = Bundle(url: appURL)
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                icon.size = NSSize(width: 128, height: 128)
                return (bundle?.bundleIdentifier, icon)
            }
        }

        // 6. Case-insensitive directory scan
        for directory in searchDirectories {
            if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                for fileURL in files where fileURL.pathExtension == "app" {
                    let baseName = fileURL.deletingPathExtension().lastPathComponent
                    if baseName.localizedCaseInsensitiveCompare(cleanName) == .orderedSame {
                        let bundle = Bundle(url: fileURL)
                        let icon = NSWorkspace.shared.icon(forFile: fileURL.path)
                        icon.size = NSSize(width: 128, height: 128)
                        return (bundle?.bundleIdentifier, icon)
                    }
                }
            }
        }

        return (nil, nil)
    }

    // MARK: - Actions

    func open(notification: SystemNotificationModel) {
        // 1. Try AXPress on the banner element if available
        if let elem = notification.axElement {
            _ = AXUIElementPerformAction(elem, kAXPressAction as CFString)
        }

        // 2. Ensure application is focused
        if let bundleID = notification.bundleIdentifier {
            if let runningApp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
                activateApp(runningApp)
            } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
            }
        } else {
            for app in NSWorkspace.shared.runningApplications {
                if let locName = app.localizedName, locName.caseInsensitiveCompare(notification.appName) == .orderedSame {
                    activateApp(app)
                    break
                }
            }
        }
    }

    private func activateApp(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: .activateIgnoringOtherApps)
        }
    }

    func dismiss(notification: SystemNotificationModel) {
        guard let elem = notification.axElement else { return }
        var actionsRef: CFArray?
        guard AXUIElementCopyActionNames(elem, &actionsRef) == .success, let actions = actionsRef as? [String] else {
            return
        }

        let dismissKeywords = [
            "закрыть", "close", "dismiss", "clear", "fermer", "schließen",
            "cerrar", "chiudi", "sluiten", "zamknij", "stäng", "lukk",
            "sulje", "fechar", "zavřít", "bezárás", "kapat", "отклонить"
        ]

        if let closeAction = actions.first(where: { action in
            let lower = action.lowercased()
            return dismissKeywords.contains(where: { lower.contains($0) })
        }) {
            _ = AXUIElementPerformAction(elem, closeAction as CFString)
        }
    }

    // MARK: - AX Helper

    private func copyAttribute<T>(_ attribute: String, from element: AXUIElement) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let val = value else { return nil }
        return val as? T
    }
}
