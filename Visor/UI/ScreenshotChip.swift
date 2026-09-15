import SwiftUI

/// A caught screenshot, offered for as long as it lasts. Two sizes: a chip
/// for the compact wing and a preview for the expanded state.
struct ScreenshotChip: View {
    let shot: ScreenshotCatch
    var height: CGFloat
    var showsLabel = false
    var onOpen: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            thumbnail
            if showsLabel {
                VStack(alignment: .leading, spacing: 1) {
                    Text(shot.url.deletingPathExtension().lastPathComponent)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text("Drag it out, or click to open")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
        }
        .foregroundStyle(.white)
        // The file can be moved or deleted while the catch is still on screen.
        .onTapGesture {
            if exists {
                onOpen()
            }
        }
        .draggable(shot.url)
    }

    private var thumbnail: some View {
        Group {
            if let image = shot.thumbnail {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: height * 0.6))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height * 0.2))
        // A screenshot of a white window would otherwise dissolve into the
        // island's black.
        .overlay(
            RoundedRectangle(cornerRadius: height * 0.2)
                .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
        )
    }

    private var exists: Bool {
        FileManager.default.fileExists(atPath: shot.url.path)
    }
}
