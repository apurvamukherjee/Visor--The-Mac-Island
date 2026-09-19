import MediaRemoteAdapter
import SwiftUI

/// Shuffle and repeat flank the scrub bar rather than sit in the transport
/// row below it — the same split the reference flow uses, and the only one
/// that leaves `ExpandedMusicView`'s existing `controls` row untouched.
struct MusicSeekRow: View {
    let shuffleMode: TrackInfo.ShuffleMode
    let repeatMode: TrackInfo.RepeatMode
    let progress: NowPlayingProgress
    @Binding var showLyrics: Bool
    var commands: NotchStore.NowPlayingCommands?

    var body: some View {
        HStack(spacing: 4) {
            miniButton("shuffle", isOn: shuffleMode != .off) {
                commands?.toggleShuffle()
            }
            NowPlayingSeekBar(progress: progress, onSeek: { commands?.seek($0) })
            miniButton(repeatGlyph, isOn: repeatMode != .off) {
                commands?.cycleRepeat()
            }
            miniButton("text.quote", isOn: showLyrics) {
                showLyrics.toggle()
            }
        }
    }

    private var repeatGlyph: String {
        repeatMode == .one ? "repeat.1" : "repeat"
    }

    private func miniButton(_ symbol: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isOn ? .white : .white.opacity(0.35))
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
