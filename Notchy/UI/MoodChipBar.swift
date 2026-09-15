import SwiftUI

/// Docked under the expanded island while playback is active. Selection is
/// a stub — tapping logs and nothing else, per the Phase 3 spec.
struct MoodChipBar: View {
    @State private var selected: String?

    private static let moods = ["Party", "Feel good", "Relax", "Sleep", "Work out", "Commute"]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Self.moods, id: \.self) { mood in
                    chip(mood)
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.never)
        .frame(height: NotchGeometry.chipBarHeight)
    }

    private func chip(_ mood: String) -> some View {
        let isSelected = selected == mood
        return Button {
            selected = mood
            Log.app.info("Mood chip selected: \(mood, privacy: .public)")
        } label: {
            Text(mood)
                .font(.system(.caption2, design: .rounded).weight(.medium))
                .foregroundStyle(isSelected ? .black : .white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background {
                    Capsule()
                        .fill(isSelected ? .white : .white.opacity(0.12))
                }
                .overlay {
                    Capsule().stroke(.white.opacity(isSelected ? 0 : 0.25), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}
