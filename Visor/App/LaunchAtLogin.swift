import ServiceManagement

/// Login-item registration for the app itself. `SMAppService.mainApp` is the
/// whole implementation — no helper bundle, no `LSSharedFileList`.
@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// macOS refuses to register a login item for an app running out of a
    /// build directory or a mounted disk image — it has to live in
    /// /Applications first. Worth saying out loud, because the error macOS
    /// returns for it is just "Operation not permitted".
    static var isInstalled: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications")
    }

    /// Throws whatever `SMAppService` throws; the caller reverts the toggle
    /// rather than showing a checkbox that lies about the real state.
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
