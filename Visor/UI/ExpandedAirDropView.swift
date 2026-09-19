import SwiftUI

/// The outgoing AirDrop card.
///
/// No progress ring. macOS reports a send as started and then finished, with
/// nothing in between, so a ring here could only animate a number nobody
/// knows — see `AirDropTransfer`. The glyph carries the state instead.
struct ExpandedAirDropView: View {
    let transfer: AirDropTransfer

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.pulse, isActive: transfer.status == .sending && !Motion.reduceMotion)

            Text(transfer.title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(statusLabel)
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var symbolName: String {
        switch transfer.status {
        case .sending: "airplayaudio"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch transfer.status {
        case .sending: .blue
        case .completed: .green
        case .failed: .orange
        }
    }

    private var statusLabel: String {
        switch transfer.status {
        case .sending: "Sending via AirDrop…"
        case .completed: "Sent"
        case let .failed(message): message
        }
    }
}
