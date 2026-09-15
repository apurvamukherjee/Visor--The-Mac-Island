import SwiftUI
import UniformTypeIdentifiers

/// A caught screenshot, offered for as long as it lasts. Two sizes: a chip
/// for the compact wing and a preview for the expanded state.
struct ScreenshotChip: View {
    let shot: ScreenshotCatch
    var height: CGFloat
    var showsLabel = false
    var onOpen: () -> Void
    var onDismiss: () -> Void
    /// Called once a receiver has taken the file. Separate from `onDismiss`
    /// because it fires from a provider that can outlive this chip, so the
    /// handler has to check the catch is still the current one.
    var onDropCompleted: () -> Void

    @State private var isHovering = false

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
        // `.onDrag`, not `.draggable`: the catch has done its job once the
        // file is somewhere else, and the provider's `loadHandler` is the
        // hook that tells us a receiver actually took it. `.draggable` leaves
        // the chip sitting in the notch afterwards with nothing left to do.
        .onDrag {
            let provider = NSItemProvider()
            provider.suggestedName = shot.url.lastPathComponent
            provider.registerFileRepresentation(
                forTypeIdentifier: UTType.fileURL.identifier,
                fileOptions: .openInPlace,
                visibility: .all
            ) { completion in
                completion(shot.url, true, nil)
                // The receiver has the file; the notch no longer needs to
                // offer it. A cancelled drag never reaches here, so the chip
                // survives to be tried again.
                Task { @MainActor in onDropCompleted() }
                return nil
            }
            return provider
        }
    }

    /// iOS's close badge: only while the pointer is over the chip, so the
    /// compact wing stays clean at a glance.
    private var dismissBadge: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: max(12, height * 0.28)))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.65))
        }
        .buttonStyle(.plain)
        .offset(x: 5, y: -5)
        .transition(.scale(scale: 0.5).combined(with: .opacity))
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
        .overlay(alignment: .topTrailing) {
            if isHovering {
                dismissBadge
            }
        }
        .onHover { hovering in
            withAnimation(Motion.resolved(Motion.contentIn)) { isHovering = hovering }
        }
    }

    private var exists: Bool {
        FileManager.default.fileExists(atPath: shot.url.path)
    }
}
