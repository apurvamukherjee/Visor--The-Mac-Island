import SwiftUI

struct NotchRootView: View {
    var store: NotchStore
    var canvasWidth: CGFloat

    private var currentSize: CGSize {
        switch store.state {
        case .expanded: NotchGeometry.expandedSize
        case .compact: compactSize
        case .closed: store.closedSize
        }
    }

    private var compactSize: CGSize {
        CGSize(width: store.closedSize.width + NotchGeometry.compactExtraWidth, height: store.closedSize.height)
    }

    private var topRadius: CGFloat {
        switch store.state {
        case .expanded: NotchShape.expandedTopRadius
        case .compact: NotchShape.compactTopRadius
        case .closed: NotchShape.closedTopRadius
        }
    }

    private var bottomRadius: CGFloat {
        switch store.state {
        case .expanded: NotchShape.expandedBottomRadius
        case .compact: NotchShape.compactBottomRadius
        case .closed: NotchShape.closedBottomRadius
        }
    }

    var body: some View {
        NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
            .fill(.black)
            .frame(width: currentSize.width, height: currentSize.height)
            .overlay(alignment: .top) {
                if store.state == .expanded {
                    expandedContent
                        .padding(.top, 4)
                        .transition(.island)
                } else if store.state == .compact, store.currentActivity != nil {
                    CompactActivityView(store: store)
                        .frame(width: compactSize.width, height: compactSize.height)
                        .transition(.island)
                }
            }
            .frame(width: canvasWidth, height: NotchGeometry.expandedSize.height, alignment: .top)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // topRow's height matches store.closedSize.height (the real
            // hardware safe area) so Clock/Battery flank the camera housing
            // instead of sitting below a blank gap the width of the whole
            // shape — the Spacer between them keeps both clear of the
            // housing horizontally, same as the housing itself keeps them
            // clear vertically.
            topRow
                .frame(height: store.closedSize.height)
            if let info = store.nowPlaying {
                ExpandedNowPlayingView(info: info, artwork: store.nowPlayingArtwork, commands: store.nowPlayingCommands)
            } else {
                SignatureGlow()
            }
        }
        .padding(.horizontal, 12)
    }

    private var topRow: some View {
        HStack {
            ClockPlaceholderView()
            Spacer(minLength: 0)
            if let battery = store.battery {
                ExpandedBatteryRow(info: battery)
            }
        }
    }
}

/// Personal touch shown in place of Now Playing when nothing's playing.
/// The glow only pulses while this view exists in the hierarchy — expanded
/// (hovering) and idle — so it never animates off-screen or while closed.
private struct SignatureGlow: View {
    @State private var isGlowing = false

    private static let maroon = Color(red: 0.5, green: 0, blue: 0)

    var body: some View {
        Text("By Apurva")
            .font(.system(.title3, design: .rounded).weight(.semibold))
            .foregroundStyle(Self.maroon)
            .shadow(color: Self.maroon, radius: isGlowing ? 14 : 4)
            .frame(maxWidth: .infinity)
            .onAppear {
                withAnimation(Motion.resolved(Motion.pulse)) {
                    isGlowing = true
                }
            }
    }
}
