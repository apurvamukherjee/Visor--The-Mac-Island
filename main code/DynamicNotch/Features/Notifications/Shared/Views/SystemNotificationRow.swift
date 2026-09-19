//
//  SystemNotificationRow.swift
//  DynamicNotch
//

internal import AppKit
import SwiftUI

@MainActor
struct SystemNotificationRow: View {
    let notification: SystemNotificationModel
    let onOpen: (SystemNotificationModel) -> Void

    private let avatarSize: CGFloat = 50
    private let avatarSpacing: CGFloat = 12

    private var displayName: String {
        let trimmedTitle = notification.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? notification.appName : trimmedTitle
    }

    var body: some View {
        Button(action: { onOpen(notification) }) {
            HStack(alignment: .center, spacing: avatarSpacing) {
                avatar

                VStack(alignment: .leading, spacing: 3) {
                    header
                    contentPreview
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlaybackSourceButtonStyle())
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(displayName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(notification.receivedDate, format: .dateTime.hour().minute())
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var contentPreview: some View {
        let trimmedSubject = notification.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedSummary = notification.body?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasSummary = !trimmedSummary.isEmpty

        if hasSummary && !trimmedSubject.isEmpty {
            VStack(alignment: .leading, spacing: 1.5) {
                Text(trimmedSubject)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(trimmedSummary)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.trailing, 5)
        } else {
            let displayText = !trimmedSubject.isEmpty
                ? trimmedSubject
                : (!trimmedSummary.isEmpty ? trimmedSummary : notification.appName)

            Text(displayText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(trimmedSubject.isEmpty && !hasSummary ? Color.secondary : Color.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .padding(.trailing, 5)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let icon = notification.appIcon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: avatarSize, height: avatarSize)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.white.opacity(0.14))

                Image(systemName: "bell.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: avatarSize, height: avatarSize)
        }
    }
}
