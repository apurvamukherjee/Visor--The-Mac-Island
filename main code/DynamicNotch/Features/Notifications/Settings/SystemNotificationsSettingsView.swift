//
//  SystemNotificationsSettingsView.swift
//  DynamicNotch
//

internal import AppKit
import SwiftUI

struct SystemNotificationsSettingsView: View {
    @ObservedObject var settings: NotificationsSettingsStore
    @ObservedObject var permissionController: SettingsPermissionController

    private var notificationDurationRange: ClosedRange<Double> {
        Double(SettingsStoreBase.notificationDurationRange.lowerBound)...Double(SettingsStoreBase.notificationDurationRange.upperBound)
    }

    var body: some View {
        SettingsPageScrollView {
            systemNotificationsActivity
            systemNotificationsDuration
        }
        .onAppear {
            permissionController.refresh()
        }
    }

    private var systemNotificationsActivity: some View {
        SettingsCard(title: "settings.notifications.card.activity") {
            SettingsToggleRow(
                title: "settings.notifications.system.enabled",
                description: "settings.notifications.system.enabled.description",
                systemImage: "bell.badge.fill",
                color: .red,
                isOn: systemNotificationsBinding,
                accessibilityIdentifier: "settings.notifications.system.toggle"
            )

            Divider()
                .opacity(0.6)
                .padding(.leading, 43)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

            SettingsToggleRow(
                title: "settings.notifications.system.hideNative.title",
                description: "settings.notifications.system.hideNative.desc",
                systemImage: "eye.slash.fill",
                color: .black,
                isOn: $settings.isSystemNotificationsHideNativeEnabled,
                accessibilityIdentifier: "settings.notifications.system.hideNative"
            )

            if !permissionController.isAccessibilityTrusted {
                Divider()
                    .opacity(0.6)
                    .padding(.leading, 43)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)

                SettingsButtonRow(
                    title: "settings.permissions.accessibility.title",
                    description: "settings.notifications.system.accessibility.description",
                    systemImage: "hand.raised.fill",
                    iconSize: 20,
                    iconColor: .orange,
                    color: .clear,
                    buttonTitle: "settings.permissions.action.grantAccess",
                    accessibilityIdentifier: "settings.notifications.system.grantAccessibility",
                    action: {
                        permissionController.performAction(for: .accessibility)
                    }
                )
            }
        }
    }

    private var systemNotificationsDuration: some View {
        SettingsCard(title: "settings.notifications.card.duration") {
            SettingsSliderRow(
                title: "settings.notifications.system.duration.title",
                description: "settings.notifications.system.duration.desc",
                range: notificationDurationRange,
                step: 1,
                fractionLength: 0,
                suffix: "s",
                accessibilityIdentifier: "settings.notifications.system.duration",
                value: Binding(
                    get: { Double(settings.systemNotificationDuration) },
                    set: { settings.systemNotificationDuration = Int($0.rounded()) }
                )
            )
            .disabled(!settings.isSystemNotificationsEnabled)
            .opacity(settings.isSystemNotificationsEnabled ? 1 : 0.5)
        }
    }

    private var systemNotificationsBinding: Binding<Bool> {
        Binding(
            get: {
                settings.isSystemNotificationsEnabled
            },
            set: { newValue in
                if newValue && !permissionController.isAccessibilityTrusted {
                    permissionController.performAction(for: .accessibility)
                }
                settings.isSystemNotificationsEnabled = newValue
            }
        )
    }
}
