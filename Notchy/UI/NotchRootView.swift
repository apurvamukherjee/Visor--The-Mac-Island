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

    private var shape: NotchShape {
        NotchShape(topRadius: topRadius, bottomRadius: bottomRadius)
    }

    /// 1.0 at closed keeps the island pure black so it stays invisible
    /// against the hardware notch (a Phase 1 acceptance criterion); the
    /// material only reads through once the shape has grown past the real
    /// cutout. Reduce Transparency pins it opaque in every state.
    private var blackOverlayOpacity: Double {
        if store.reduceTransparency {
            return 1
        }
        switch store.state {
        case .closed: return 1
        case .compact: return 0.55
        case .expanded: return 0.15
        }
    }

    private var islandSurface: some View {
        ZStack {
            if !store.reduceTransparency {
                // Soft outer bleed so the edge doesn't hard-cut against the
                // wallpaper. Behind everything, low opacity, blurred.
                shape
                    .fill(.black)
                    .blur(radius: 8)
                    .opacity(0.35)
                VisualEffectBackground()
                    .clipShape(shape)
            }
            shape
                .fill(.black)
                .opacity(blackOverlayOpacity)
        }
    }

    var body: some View {
        islandSurface
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
            .overlay(alignment: .bottom) { chipBarDock }
            .frame(width: canvasWidth, height: NotchGeometry.expandedSize.height, alignment: .top)
            .animation(Motion.resolved(Motion.layout), value: store.nowPlaying?.trackIdentity)
            .animation(Motion.resolved(Motion.layout), value: store.nowPlaying == nil)
    }

    private var showChipBar: Bool {
        store.state == .expanded && store.nowPlaying?.isPlaying == true
    }

    @ViewBuilder
    private var chipBarDock: some View {
        if showChipBar {
            MoodChipBar()
                .offset(y: NotchGeometry.chipBarHeight + NotchGeometry.chipBarGap)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top)
                            .combined(with: .opacity)
                            .animation(Motion.resolved(Motion.chipBarIn)),
                        removal: .move(edge: .top)
                            .combined(with: .opacity)
                            .animation(Motion.resolved(Motion.chipBarOut))
                    )
                )
        }
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
                ExpandedMusicView(
                    info: info,
                    artwork: store.nowPlayingArtwork,
                    commands: store.nowPlayingCommands,
                    events: store.calendarEvents
                )
            } else {
                ExpandedIdleView(events: store.calendarEvents)
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
