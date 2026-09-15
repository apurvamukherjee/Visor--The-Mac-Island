import SwiftUI

struct NotchRootView: View {
    var store: NotchStore
    var canvasWidth: CGFloat

    private var currentSize: CGSize {
        switch store.state {
        case .expanded: NotchGeometry.expandedSize(hasNowPlaying: store.nowPlaying != nil)
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
                        // Everything clears the camera housing in one place.
                        // The cutout hides the island's top-centre 185x33pt,
                        // so per-column clearance just moved the bug around.
                        .padding(.top, store.closedSize.height + 6)
                        .transition(.island)
                } else if store.state == .compact, store.currentActivity != nil {
                    CompactActivityView(store: store)
                        .frame(width: compactSize.width, height: compactSize.height)
                        .transition(.island)
                }
            }
            .frame(width: canvasWidth, height: NotchGeometry.expandedSize.height, alignment: .top)
            // NSHostingView centres its root view in its bounds; if the canvas
            // is ever taller than the island, that drops the island below the
            // notch. Pin it to the top.
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(Motion.resolved(Motion.layout), value: store.nowPlaying?.trackIdentity)
            .animation(Motion.resolved(Motion.layout), value: store.nowPlaying == nil)
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
            ExpandedIdleView(events: store.calendarEvents)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
        }
    }
}
