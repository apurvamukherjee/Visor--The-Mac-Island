import AppKit
import SwiftUI

struct NotchRootView: View {
    var store: NotchStore
    var canvasSize: CGSize

    /// The state's size with no squash applied. Content is laid out against
    /// this, not `currentSize`: reflowing text every frame of a 100ms squash
    /// both looks wrong and re-runs the layout pass in a loop.
    private var restingSize: CGSize {
        store.restingSize(for: store.state)
    }

    /// The resting size displaced by the two additive offsets: the collapse
    /// squash and the in-progress swipe squeeze. Both ride their own springs
    /// — that is the whole point of them being additive rather than extra
    /// curves on the frame.
    private var currentSize: CGSize {
        let base = restingSize
        let squeeze = Motion.SwipeFeedback.compression(for: base.width) * store.swipeProgress
        return CGSize(
            width: max(0, base.width + store.squashWidth - squeeze),
            height: max(0, base.height + store.squashHeight)
        )
    }

    /// The closed state takes no shoulder, whatever the feature asks for:
    /// material outside the physical cutout would make it visible.
    private var radii: NotchRadii {
        switch store.state {
        case .expanded: store.layout.expandedRadii
        case .compact: store.layout.compactRadii
        case .closed: .closed
        }
    }

    private var shape: NotchShape {
        var radii = radii
        // The stretch bleeds into the radius so the island bulges under the
        // squash instead of merely scaling.
        radii.bottom += store.squashHeight * Motion.squashRadiusFraction
        return NotchShape(radii, isCapsule: store.isCapsule)
    }

    /// Pure black, hard-edged, in every state. Two things were tried here and
    /// both broke the closed state's "invisible against the hardware notch"
    /// rule: an `NSVisualEffectView` material (washed the surface out to grey
    /// against a bright wallpaper) and a blurred outer bleed (a blur extends
    /// *past* its shape, so it smeared a dark halo onto real screen either
    /// side of the notch). Nothing may paint outside the silhouette.
    private var islandSurface: some View {
        shape
            .fill(.black)
            // Nothing paints outside the silhouette: the ring is the shape's
            // own outline, clipped back to the shape so only its inner half
            // survives. Not a glow around the island.
            .overlay {
                shape
                    .stroke(.white.opacity(store.isDropTargeted ? 0.55 : 0), lineWidth: 3)
                    .clipShape(shape)
            }
            // The user's own outline, off by default. Clipped the same way
            // and skipped entirely while closed — an outline on the closed
            // island is exactly what "invisible against the cutout" forbids.
            .overlay {
                if strokeOpacity > 0, store.state != .closed {
                    shape
                        .stroke(.white.opacity(strokeOpacity), lineWidth: strokeWidth)
                        .clipShape(shape)
                }
            }
            .animation(Motion.resolved(Motion.strokeVisibility), value: store.isDropTargeted)
    }

    @AppStorage(Preferences.strokeEnabledKey) private var strokeEnabled = false
    @AppStorage(Preferences.strokeWidthKey) private var storedStrokeWidth = 1.0
    @AppStorage(Preferences.strokeOpacityKey) private var storedStrokeOpacity = 0.25

    private var strokeWidth: CGFloat {
        CGFloat(min(max(storedStrokeWidth, 0.5), 4))
    }

    private var strokeOpacity: Double {
        strokeEnabled ? min(max(storedStrokeOpacity, 0), 1) : 0
    }

    var body: some View {
        islandSurface
            .frame(width: currentSize.width, height: currentSize.height)
            .overlay(alignment: .top) {
                if store.state == .expanded {
                    expandedContent
                        // The gutter every feature lays out inside. It was
                        // 14/10 and read edge-to-edge: at the bottom corners
                        // the shape curves in by its 28-34pt radius, so
                        // content that clears the straight edge still runs
                        // into the curve. Widened here rather than per
                        // feature — one gutter is why no feature has to know
                        // the radius it is sitting in.
                        .padding(.horizontal, IslandSpacing.gutter)
                        .padding(.bottom, IslandSpacing.bottom)
                        // Everything clears the camera housing in one place.
                        // The cutout hides the island's top-centre 185x33pt,
                        // so per-column clearance just moved the bug around.
                        .padding(.top, store.closedSize.height + IslandSpacing.cameraClearance)
                        .frame(width: restingSize.width)
                        .transition(.island)
                } else if store.state == .compact, store.currentActivity != nil {
                    CompactActivityView(store: store)
                        .frame(width: restingSize.width, height: restingSize.height)
                        .transition(.island)
                }
            }
            // Content recedes behind the squeeze rather than being squashed
            // with it, so a swipe reads as pushing the island away.
            .blur(radius: Motion.SwipeFeedback.blurRadius * store.swipeProgress)
            .opacity(1 - Motion.SwipeFeedback.opacityReduction * store.swipeProgress)
            // Enforces the rule the surface comment states: nothing paints
            // outside the silhouette. It also lets content keep its resting
            // width while the squash narrows the shape around it.
            .clipShape(shape)
            .frame(width: canvasSize.width, height: canvasSize.height, alignment: .top)
            // Drop an image on the notch and it becomes the current catch —
            // the same thing a fresh screenshot becomes. Holding Option
            // while dropping sends the files via AirDrop instead, which is
            // the one gesture that can tell the two apart without a mode
            // switch the user has to remember.
            .dropDestination(for: URL.self) { urls, _ in
                guard let first = urls.first else { return false }
                if NSEvent.modifierFlags.contains(.option) {
                    store.airDropCommands?.send(urls)
                } else {
                    store.screenshotCommands?.adopt(first)
                }
                return true
            } isTargeted: { targeted in
                store.isDropTargeted = targeted
            }
            // NSHostingView centres its root view in its bounds; if the canvas
            // is ever taller than the island, that drops the island below the
            // notch. Pin it to the top.
            .frame(maxHeight: .infinity, alignment: .top)
            .animation(Motion.resolved(Motion.layout), value: store.nowPlaying?.trackIdentity)
            .animation(Motion.resolved(Motion.layout), value: store.nowPlaying == nil)
    }

    /// Switched on the resolved owner rather than on the store's data, so
    /// the view can never disagree with the layout the island was sized to.
    ///
    /// No clock/battery row here: the agenda and music columns need the full
    /// height, and a row of their own pushed content past the shape's bottom
    /// edge. Time is already in the menu bar, battery lives in the wings.
    @ViewBuilder
    private var expandedContent: some View {
        if let step = store.onboardingStep {
            ExpandedOnboardingView(step: step, commands: store.onboardingCommands)
        } else {
            expandedActivityContent
        }
    }

    @ViewBuilder
    private var expandedActivityContent: some View {
        switch store.expandedKind {
        case .screenshot:
            ExpandedShelfView(
                shelf: store.shelf,
                onOpen: { shot in
                    NSWorkspace.shared.open(shot.url)
                    store.removeFromShelf(shot)
                },
                onDismiss: { store.removeFromShelf($0) },
                onDropCompleted: { store.removeFromShelf($0) },
                onClearAll: { store.clearShelf() }
            )
        case .network:
            ExpandedNetworkView(onDismiss: { store.networkCommands?.dismiss() })
        case .batteryAlert:
            if let alert = store.batteryAlert {
                ExpandedBatteryAlertView(alert: alert)
            }
        case .bluetooth:
            if let alert = store.bluetoothAlert {
                ExpandedBluetoothView(alert: alert)
            }
        case .airDrop:
            if let transfer = store.airDropTransfer {
                ExpandedAirDropView(transfer: transfer)
            }
        case .download:
            ExpandedDownloadView(downloads: store.downloads)
        case .screenRecording:
            if let recording = store.screenRecording {
                ExpandedScreenRecordingView(recording: recording)
            }
        case .volume:
            if let volume = store.volume {
                ExpandedVolumeView(
                    volume: volume,
                    onScrub: { store.volumeCommands?.setLevel($0) },
                    onToggleMute: { store.volumeCommands?.toggleMute() }
                )
            }
        case .nowPlaying:
            musicContent
        case .timer:
            if let timer = store.timer {
                ExpandedTimerView(
                    timer: timer,
                    onTogglePause: { store.timerCommands?.togglePause() },
                    onCancel: { store.timerCommands?.cancel() }
                )
            }
        // `resolveExpandedKind` never returns the compact-only peeks, but
        // the switch has to be total over the enum.
        case .charging, .deviceBattery, .wave, .greeting, .focus, nil:
            ExpandedIdleView(
                events: store.calendarEvents,
                onStartTimer: store.timerCommands.map { commands in { commands.start($0) } }
            )
        }
    }

    @ViewBuilder
    private var musicContent: some View {
        if let info = store.nowPlaying {
            ExpandedMusicView(
                info: info,
                artwork: store.nowPlayingArtwork,
                tint: store.nowPlayingTint,
                commands: store.nowPlayingCommands,
                progress: store.nowPlayingProgress,
                events: store.calendarEvents,
                hoverPoint: store.hoverPoint,
                bleed: store.nowPlayingBleed
            )
        }
    }
}
