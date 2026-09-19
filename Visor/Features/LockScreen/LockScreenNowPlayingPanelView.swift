import AppKit
import SwiftUI

/// The lock-screen media panel. Ported from the reference's
/// `LockScreenNowPlayingPanelView`, with its geometry kept exactly.
///
/// The window behind this covers the **whole screen**, and the card positions
/// itself inside it — that is why the constants below are offsets from the
/// screen's centre rather than a window frame. Placing a small window under
/// the notch instead, which is what a first pass at this did, puts the card in
/// the wrong place on every screen size.
///
/// There is no calendar here, by design: the reference's panel is music-only,
/// and the manager behind it only shows the panel at all when a track is
/// loaded.
struct LockScreenNowPlayingPanelView: View {
    static let panelSize = CGSize(width: 340, height: 180)

    private static let expandedPanelHeight: CGFloat = panelSize.height - 20
    private static let expandedArtworkSize: CGFloat = 500
    private static let expandedClockHeight: CGFloat = 76
    private static let panelCenterYOffset: CGFloat = (Self.panelSize.height / 2) + 80

    var store: NotchStore
    let info: NowPlayingInfo
    let artwork: CGImage?
    let isPresented: Bool

    @State private var onTapArtwork = false
    @State private var backgroundRotation: Double = 0
    @State private var backgroundScale: CGFloat = 1

    var body: some View {
        GeometryReader { screenProxy in
            let screenWidth = screenProxy.size.width
            let screenHeight = screenProxy.size.height

            ZStack {
                if onTapArtwork {
                    coverAndBackgroundPresentation
                        .ignoresSafeArea()
                        .transition(.opacity)

                    expandedClockView
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .offset(y: -screenHeight / 2 + 130)

                    expandedArtworkButton
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                        .offset(y: -42)
                }

                playerPanel
                    .offset(x: 0, y: playerPanelYOffset(screenHeight: screenHeight))
            }
            .frame(width: screenWidth, height: screenHeight)
        }
        .opacity(isPresented ? 1 : 0)
        .animation(.spring(response: 0.3), value: isPresented)
        .animation(.spring(response: 0.58, dampingFraction: 0.86), value: onTapArtwork)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .environment(\.controlActiveState, .active)
    }

    private var playerPanel: some View {
        LockScreenNowPlayingView(
            info: info,
            artwork: artwork,
            tint: store.nowPlayingTint,
            progress: store.nowPlayingProgress,
            commands: store.nowPlayingCommands,
            onTapArtwork: $onTapArtwork
        )
        // Fixed height in both states, so nothing inside can resize the card
        // when a track changes.
        .frame(
            width: Self.panelSize.width,
            height: onTapArtwork ? Self.expandedPanelHeight : Self.panelSize.height,
            alignment: .topLeading
        )
        .background { panelBackground }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .environment(\.colorScheme, .dark)
        .environment(\.controlActiveState, .active)
        .shadow(color: .black.opacity(0.24), radius: 26, x: 0, y: 14)
    }

    private var expandedArtworkButton: some View {
        Button {
            withAnimation(.spring(response: 0.65)) { onTapArtwork = false }
        } label: {
            expandedArtwork
                .shadow(color: .black.opacity(0.45), radius: 24, x: 0, y: 16)
        }
        .buttonStyle(PlaybackSourceButtonStyle())
    }

    @ViewBuilder
    private var expandedArtwork: some View {
        let side = Self.expandedArtworkSize
        if let artwork {
            Image(decorative: artwork, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(width: side, height: side)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 90))
                        .foregroundStyle(.white.opacity(0.4))
                }
        }
    }

    private var expandedClockView: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            LockScreenClockView(
                date: context.date,
                width: Self.expandedArtworkSize + 120,
                height: Self.expandedClockHeight
            )
        }
    }

    private func playerPanelYOffset(screenHeight: CGFloat) -> CGFloat {
        if onTapArtwork {
            screenHeight / 2 - 180
        } else {
            Self.panelCenterYOffset + CGFloat(LockScreenSettings.mediaPanelVerticalOffset())
        }
    }

    private var mediaPanelBackgroundStyle: LockScreenMediaPanelBackgroundStyle {
        LockScreenSettings.mediaPanelBackgroundStyle()
    }

    private var coverAndBackgroundPresentation: some View {
        GeometryReader { proxy in
            let diagonal = hypot(proxy.size.width, proxy.size.height)
            ZStack {
                Color.black

                if mediaPanelBackgroundStyle != .black {
                    NowPlayingArtworkBackground(
                        artworkImage: artworkImage,
                        blurRadius: 200,
                        darkeningOpacity: 0.6,
                        saturation: 1.45,
                        scale: mediaPanelBackgroundScale
                    )
                    .frame(width: diagonal, height: diagonal)
                    .rotationEffect(mediaPanelBackgroundRotation)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onAppear(perform: configureMediaPanelBackgroundAnimation)
            .onChange(of: mediaPanelBackgroundStyle) {
                configureMediaPanelBackgroundAnimation()
            }
        }
    }

    private var artworkImage: NSImage? {
        artwork.map { NSImage(cgImage: $0, size: .zero) }
    }

    private var mediaPanelBackgroundScale: CGFloat {
        mediaPanelBackgroundStyle == .animatedArtwork ? backgroundScale : 1
    }

    private var mediaPanelBackgroundRotation: Angle {
        mediaPanelBackgroundStyle == .animatedArtwork ? .degrees(backgroundRotation) : .zero
    }

    private func configureMediaPanelBackgroundAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            backgroundRotation = 0
            backgroundScale = 1
        }

        // Reduce Motion stops the drifting backdrop; the still artwork stays.
        guard mediaPanelBackgroundStyle == .animatedArtwork, !Motion.reduceMotion else { return }

        withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
            backgroundRotation = 360
        }

        withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
            backgroundScale = 2
        }
    }

    private var panelBackground: some View {
        LockScreenWidgetSurface(
            style: LockScreenSettings.widgetAppearanceStyle(),
            tintStyle: LockScreenSettings.widgetTintStyle(),
            brightness: LockScreenSettings.widgetBackgroundBrightness(),
            cornerRadius: 28,
            liquidGlassVariant: LockScreenSettings.liquidGlassVariant()
        )
    }
}
