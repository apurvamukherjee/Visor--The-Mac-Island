//
//  OnboardingView.swift
//  
//
//  Created by Apurva on 2025-06-23.
//

import SwiftUI
import AVFoundation

enum OnboardingStep {
    case welcome
    case cameraPermission
    case calendarPermission
    case remindersPermission
    case accessibilityPermission
    case musicPermission
    case finished
}

private let calendarService = CalendarService()

struct OnboardingView: View {
    @State private var step: OnboardingStep = .welcome
    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            switch step {
            case .welcome:
                WelcomeView { go(.cameraPermission) }
                .transition(.opacity)

            case .cameraPermission:
                PermissionRequestView(
                    icon: Image(systemName: "camera.fill"),
                    title: "Enable Camera Access",
                    description: "Visor includes a mirror feature that lets you quickly check your appearance using your camera, right from the notch. Camera access is required only to show this live preview. You can turn the mirror feature on or off at any time in the app.",
                    privacyNote: "Your camera is never used without your consent, and nothing is recorded or stored.",
                    onAllow: {
                        Task {
                            _ = await AVCaptureDevice.requestAccess(for: .video)
                            go(.calendarPermission)
                        }
                    },
                    onSkip: { go(.calendarPermission) }
                )
                .transition(.opacity)

            case .calendarPermission:
                PermissionRequestView(
                    icon: Image(systemName: "calendar"),
                    title: "Enable Calendar Access",
                    description: "Visor can show all your upcoming events in one place. Access to your calendar is needed to display your schedule.",
                    privacyNote: "Your calendar data is only used to show your events and is never shared.",
                    onAllow: {
                        Task {
                            _ = try? await calendarService.requestAccess(to: .event)
                            go(.remindersPermission)
                        }
                    },
                    onSkip: { go(.remindersPermission) }
                )
                .transition(.opacity)

            case .remindersPermission:
                PermissionRequestView(
                    icon: Image(systemName: "checklist"),
                    title: "Enable Reminders Access",
                    description: "Visor can show your scheduled reminders alongside your calendar events. Access to Reminders is needed to display your reminders.",
                    privacyNote: "Your reminders data is only used to show your reminders and is never shared.",
                    onAllow: {
                        Task {
                            _ = try? await calendarService.requestAccess(to: .reminder)
                            go(.accessibilityPermission)
                        }
                    },
                    onSkip: { go(.accessibilityPermission) }
                )
                .transition(.opacity)
            
            case .accessibilityPermission:
                PermissionRequestView(
                    icon: Image(systemName: "hand.raised.fill"),
                    title: "Enable Accessibility Access",
                    description: "Accessibility access is required to replace system notifications with the Visor HUD. This allows the app to intercept media and brightness events to display custom HUD overlays.",
                    privacyNote: "Accessibility access is used only to improve media and brightness notifications. No data is collected or shared.",
                    onAllow: {
                        Task {
                            _ = await AccessibilityPermission.shared.ensure(promptIfNeeded: true)
                            go(.musicPermission)
                        }
                    },
                    onSkip: { go(.musicPermission) }
                )
                .transition(.opacity)
                
            case .musicPermission:
                MusicControllerSelectionView(
                    onContinue: {
                        withAnimation(.easeInOut(duration: 0.6)) {
                            VisorViewCoordinator.shared.firstLaunch = false
                            step = .finished
                        }
                    }
                )
                .transition(.opacity)

            case .finished:
                OnboardingFinishView(onFinish: onFinish, onOpenSettings: onOpenSettings)
            }
        }
        .frame(width: 400, height: 600)
    }

    private func go(_ next: OnboardingStep) {
        withAnimation(.easeInOut(duration: 0.6)) {
            step = next
        }
    }
}
