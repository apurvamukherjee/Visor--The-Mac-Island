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

    /// Pure black, hard-edged, in every state. Two things were tried here and
    /// both broke the closed state's "invisible against the hardware notch"
    /// rule: an `NSVisualEffectView` material (washed the surface out to grey
    /// against a bright wallpaper) and a blurred outer bleed (a blur extends
    /// *past* its shape, so it smeared a dark halo onto real screen either
    /// side of the notch). Nothing may paint outside the silhouette.
    private var islandSurface: some View {
        shape.fill(.black)
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

    /// No clock/battery row here any more: the agenda and music columns need
    /// the full height, and a row of their own pushed the content past the
    /// shape's bottom edge. Time is already in the menu bar, and battery
    /// lives in the compact wings.
    @ViewBuilder
    private var expandedContent: some View {
        if let info = store.nowPlaying {
            ExpandedMusicView(
                info: info,
                artwork: store.nowPlayingArtwork,
                commands: store.nowPlayingCommands,
                events: store.calendarEvents
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        } else {
            ExpandedIdleView(events: store.calendarEvents, housingHeight: store.closedSize.height)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
    }
}
