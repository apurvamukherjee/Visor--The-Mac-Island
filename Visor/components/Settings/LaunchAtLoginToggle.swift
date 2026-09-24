//
//  LaunchAtLoginToggle.swift
//  Visor
//

import os
import ServiceManagement
import SwiftUI

// Visor: replaces the LaunchAtLogin package, which wrapped this one call for
// a single toggle. Only `.enabled` counts as on, as it did in the package.
struct LaunchAtLoginToggle: View {
    private static let logger = Logger(subsystem: "com.apurvamukherjee.visor", category: "LaunchAtLogin")

    @State private var isEnabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at login", isOn: $isEnabled)
            .onChange(of: isEnabled) { _, enabled in
                apply(enabled)
            }
    }

    private func apply(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Self.logger.error("Could not \(enabled ? "enable" : "disable", privacy: .public) launch at login: \(error.localizedDescription, privacy: .public)")
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
