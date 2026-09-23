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
    /// The resting size displaced only by the collapse squash. The swipe no
    /// longer squeezes the island: shrinking it mid-gesture made changing
    /// track look like the notch was being dragged about, when all that is
    /// happening is the next song starting. The island holds still.
    var currentSize: CGSize {
        let base = restingSize
        return CGSize(
            width: max(0, base.width + store.squashWidth),
            height: max(0, base.height + store.squashHeight)
        )
    }

    /// The front card's own height. `chinReveal` is added to the expanded
    /// size so the *window* is tall enough to hold the protruding chins —
    /// the front card must give that space back, or it grows by exactly the
    /// amount the chins were meant to peek out by and covers every one of
    /// them. That is why the deck looked like a single slab.
    var cardSize: CGSize {
        guard store.state == .expanded else { return currentSize }
        return CGSize(
            width: currentSize.width,
            height: max(0, currentSize.height - store.layout.chinReveal)
        )
    }

    /// The closed state takes no shoulder, whatever the feature asks for:
    /// material outside the physical cutout would make it visible.
    var radii: NotchRadii {
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
            // The front card's own colour, off by default and only ever
            // reached with the deck on. Drawn from the same family as the
            // chins at depth 0, so the stack reads as one material rather
            // than a black card sitting on coloured ones.
            .overlay {
                if frontCardTintEnabled, store.isCardStacked, store.state == .expanded {
                    shape.fill(
                        (ChinGradient(rawValue: chinGradient) ?? .charcoal)
                            .fill(depth: 0, page: store.islandPage)
                    )
                    .opacity(0.55)
                }
            }
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

    /// Whether the chins have slid out yet. `@State` rather than store state
    /// because nothing outside this view has any business knowing.
    @State var isStackRevealed = false

    @AppStorage(NewFeatures.islandStackTint.key) private var frontCardTintEnabled = false
    @AppStorage(Preferences.chinGradientKey) var chinGradient = ChinGradient.charcoal.rawValue
    @AppStorage(NewFeatures.visibleDropZones.key) private var showsDropZones = false
    @AppStorage(NewFeatures.lyrics.key) private var lyricsEnabled = false
    @AppStorage(Preferences.strokeEnabledKey) private var strokeEnabled = false
    @AppStorage(Preferences.strokeWidthKey) private var storedStrokeWidth = 1.0
    @AppStorage(Preferences.strokeOpacityKey) private var storedStrokeOpacity = 0.25

    private var strokeWidth: CGFloat {
        CGFloat(min(max(storedStrokeWidth, 0.5), 4))
    }

    private var strokeOpacity: Double {
        strokeEnabled ? min(max(storedStrokeOpacity, 0), 1) : 0
    }

    /// Today's island, unchanged: the black surface, its content, and the
    /// clip that keeps anything from painting outside the silhouette. Named
    /// so the deck can wrap it without any of it moving.
    var islandCard: some View {
        islandSurface
            .frame(width: cardSize.width, height: cardSize.height)
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
            // No blur on the gesture. The squeeze alone is the feedback —
            // blurring the content as well made a swipe read as the island
            // going out of focus rather than being pushed, and it smeared
            // the artwork and text for the whole gesture.
            // Enforces the rule the surface comment states: nothing paints
            // outside the silhouette. It also lets content keep its resting
            // width while the squash narrows the shape around it.
            // Drawn over whatever the island was showing rather than beside
            // it: a drag is a mode, and for the length of it the island has
            // one job.
            .overlay(alignment: .top) {
                if showsDropZones, store.isDropTargeted, store.state == .expanded {
                    DropZonesView(
                        size: restingSize,
                        topInset: store.closedSize.height + IslandSpacing.cameraClearance
                    )
                    .transition(.opacity)
                }
            }
            .clipShape(shape)
    }

    var body: some View {
        stackedCard
            .frame(width: canvasSize.width, height: canvasSize.height, alignment: .top)
            // Drop an image on the notch and it becomes the current catch —
            // the same thing a fresh screenshot becomes. Holding Option
            // while dropping sends the files via AirDrop instead, which is
            // the one gesture that can tell the two apart without a mode
            // switch the user has to remember — or, with the drop zones
            // showing, by which half of the island the file lands on.
            .dropDestination(for: URL.self) { urls, location in
                guard let first = urls.first else { return false }
                let zone = DropZone.resolve(
                    location: location,
                    canvasWidth: canvasSize.width,
                    zonesVisible: showsDropZones && store.state == .expanded,
                    optionHeld: NSEvent.modifierFlags.contains(.option)
                )
                switch zone {
                case .airDrop: store.airDropCommands?.send(urls)
                case .stash: store.screenshotCommands?.adopt(first)
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
        } else if store.isPaletteOpen {
            ExpandedPaletteView(
                query: store.paletteQuery,
                results: store.paletteResults,
                selection: store.paletteSelection,
                windowStart: store.paletteWindowStart,
                shortcuts: store.paletteShortcuts,
                showsShortcuts: store.isPaletteShortcutModeActive
            )
        } else {
            // Keyed on the page so a swipe cross-fades one screen for the
            // next. Without the identity SwiftUI treats them as one view
            // whose contents changed, and the agenda's rows visibly become
            // the player's controls in place.
            //
            // The same `.island` transition the island opens and closes with,
            // rather than a bare opacity fade. The box no longer moves under
            // a swipe, so a straight cross-fade had nothing to soften the
            // swap and the new screen simply appeared; the blur and the small
            // scale give the change somewhere to happen.
            pagedContent
                .id(store.islandPage)
                .transition(.island)
        }
    }

    /// The three screens, in the order they sit on the swipe axis.
    @ViewBuilder
    private var pagedContent: some View {
        switch store.islandPage {
        // A row shorter than the home screen and with no timer presets, so
        // the page fits the box the player measures — see
        // `agendaPageContent`, which sizes the island from the same numbers.
        case .agenda:
            ExpandedIdleView(
                events: store.calendarEvents,
                rowLimit: IslandLayout.maxPagedEventRows
            )
        case .shelf:
            // The same view the home page used to draw when `.screenshot`
            // outranked music. It is a screen now, so a catch no longer
            // costs you the player.
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
        case .home:
            expandedActivityContent
        case .usage:
            // The box is sized to cover every page reachable by swipe, so with
            // only one row (Codex not yet run) it is taller than this screen's
            // own content. Center rather than let the shared top alignment
            // pin the rows high with the leftover space stranded below.
            ExpandedUsageView(
                usage: store.aiUsage,
                claudeBudget: Preferences.dailyTokenBudget(for: .claude),
                codexBudget: Preferences.dailyTokenBudget(for: .codex)
            )
            .frame(maxHeight: .infinity, alignment: .center)
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
        case .nowPlaying, .pausedTrack:
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
        // `.lock` is compact-only, like the peeks beside it here.
        case .charging, .deviceBattery, .wave, .greeting, .focus, .lock, nil:
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
                hoverPoint: store.hoverPoint,
                bleed: store.nowPlayingBleed,
                volume: store.volume,
                volumeCommands: store.volumeCommands,
                lyrics: store.lyrics,
                isLyricsOpen: store.isLyricsOpen,
                onToggleLyrics: lyricsEnabled ? { store.isLyricsOpen.toggle() } : nil
            )
        }
    }
}
