import AppKit
import SwiftUI

/// Compact indicator, shown whenever the notch has a live activity but
/// isn't hovered. The left wing shows whichever activity won
/// `resolveCurrentActivity` — switched on that single resolution rather
/// than re-deriving it from the store's data — and the battery reading
/// always sits on the right. Controls and artist text live only in the
/// expanded (hover) view.
struct CompactActivityView: View {
    let store: NotchStore

    @State private var waveBounce = 0

    var body: some View {
        HStack {
            leading
            Spacer(minLength: 0)
            if let battery = store.battery {
                batteryGlyph(battery)
            }
        }
        .foregroundStyle(.white)
        .animation(Motion.resolved(Motion.catchIn), value: store.shelf)
        // Without this the wing's `.transition`s never run: swapping which
        // branch of `leading` is built is an identity change, and an identity
        // change only animates inside a transaction. This is what carries the
        // unlock handoff — `.lock` deactivating to `.nowPlaying` dissolves the
        // latch out and resolves the cover and bars in.
        .animation(Motion.resolved(Motion.contentIn), value: store.currentActivity?.kind)
        // NotchShape's bottom corners round away with the compact radius —
        // at x=0/width exactly, the shape's fill stops short of the full
        // height, so edge-flush content pokes outside it. Inset past the
        // curve to stay inside the fill at any vertical position.
        .padding(.horizontal, NotchRadii.compact.bottom + 2)
    }

    @ViewBuilder
    private var leading: some View {
        switch store.currentActivity?.kind {
        case .lock:
            // Drawn by `LockScreenNotchWindowManager` in its own window above
            // the lock shield, not here: this panel is pinned *below* the
            // shield, so while locked it is invisible. The activity still
            // exists so the island reserves the wing's width.
            LockScreenNotchView(isLocked: store.isLocked, style: LockScreenSettings.style())
        case .screenshot:
            shelfChips
        case .wave:
            Image(systemName: "hand.wave.fill")
                .symbolEffect(.bounce, value: waveBounce)
                .onAppear {
                    if !Motion.reduceMotion {
                        waveBounce += 1
                    }
                }
        case .network:
            label("wifi.slash", "No Internet", tint: .green)
        case .batteryAlert:
            if let alert = store.batteryAlert {
                label(alert.symbolName, alert.compactLabel, tint: alert.tint)
            }
        case .deviceBattery:
            // Glyph and figure only. The product name ("Apurva's AirPods
            // Pro") does not fit a wing beside the battery reading, and the
            // glyph already says which device woke up.
            if let device = store.deviceBattery {
                label(device.symbolName, "\(device.percentage)%", tint: device.tint)
            }
        case .volume:
            if let volume = store.volume {
                label(
                    VolumeGlyph.symbolName(level: volume.level, isMuted: volume.isMuted),
                    "\(volume.percentage)%",
                    tint: .white
                )
            }
        case .timer:
            timerLabel
        case .greeting:
            if let greeting = store.greetingText {
                label(greeting.symbolName, greeting.message, tint: .white)
            }
        case .bluetooth:
            if let alert = store.bluetoothAlert {
                label(alert.symbolName, alert.detail, tint: alert.tint)
            }
        case .focus:
            label(store.isFocusOn ? "moon.fill" : "moon", store.isFocusOn ? "Focus on" : "Focus off", tint: .purple)
        case .airDrop:
            if let transfer = store.airDropTransfer {
                label(airDropSymbol(transfer.status), transfer.title, tint: .blue)
            }
        case .download:
            downloadLabel
        case .screenRecording:
            recordingLabel
        case .pausedTrack:
            pausedDot
        // `.charging` shows nothing extra on the left: the battery glyph on
        // the right wing is the whole point of that peek.
        case .nowPlaying, .charging, nil:
            nowPlayingGlyphs
        }
    }

    /// A paused track, after the island has collapsed: one dot, tinted from
    /// the album so it reads as *this* track rather than a generic
    /// indicator. Deliberately not the artwork and bars `.nowPlaying` shows
    /// — the island has already said it is done with this track, and the dot
    /// is only the handle to get back to it.
    private var pausedDot: some View {
        Circle()
            .fill(store.nowPlayingTint ?? .white.opacity(0.45))
            .frame(width: 6, height: 6)
            .transition(.island)
    }

    /// Two thumbnails at wing size, then a count for the rest — four tiles
    /// do not fit beside the battery reading.
    @ViewBuilder
    private var shelfChips: some View {
        let shown = store.shelf.prefix(2)
        HStack(spacing: 5) {
            ForEach(shown) { shot in
                ScreenshotChip(
                    shot: shot,
                    height: 18,
                    onOpen: { open(shot) },
                    onDismiss: { store.removeFromShelf(shot) },
                    onDropCompleted: { store.removeFromShelf(shot) }
                )
                .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
            if store.shelf.count > shown.count {
                Text("+\(store.shelf.count - shown.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    /// The count while several are arriving, the file's own name while one
    /// is — a "1" on its own says nothing a glyph doesn't.
    @ViewBuilder
    private var downloadLabel: some View {
        if store.downloads.count == 1, let only = store.downloads.first {
            label("arrow.down.circle.fill", only.displayName, tint: .blue)
        } else if !store.downloads.isEmpty {
            label("arrow.down.circle.fill", "\(store.downloads.count) downloads", tint: .blue)
        }
    }

    /// Ticks only while on screen, like the timer wing below it.
    @ViewBuilder
    private var recordingLabel: some View {
        if let recording = store.screenRecording {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                label(
                    "record.circle.fill",
                    ScreenRecording.formatted(recording.elapsed(at: context.date)),
                    tint: .red
                )
            }
        }
    }

    private func airDropSymbol(_ status: AirDropTransfer.Status) -> String {
        switch status {
        case .sending: "airplayaudio"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.circle.fill"
        }
    }

    /// `TimelineView` schedules only while it is on screen, so the wing
    /// ticks while visible and a closed island runs nothing.
    private var timerLabel: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let timer = store.timer {
                let remaining = timer.remaining(at: context.date)
                label(
                    remaining <= 0 ? "timer" : (timer.isPaused ? "pause.fill" : "timer"),
                    remaining <= 0 ? "Time's up" : IslandTimer.format(remaining),
                    tint: .orange
                )
            }
        }
    }

    private var nowPlayingGlyphs: some View {
        HStack(spacing: 6) {
            if let artwork = store.nowPlayingArtwork {
                Image(decorative: artwork, scale: 1)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            if let info = store.nowPlaying {
                PlaybackBars(isPlaying: info.isPlaying, height: 11, tint: store.nowPlayingTint)
            }
        }
        // Resolves in rather than appearing. This is the receiving half of
        // the unlock handoff: the padlock dissolves in its own window above
        // the shield, `.lock` deactivates, and the cover and bars firm up
        // here through the same `Materialize` the latch faded out through.
        // The two cannot cross-fade as one view — they live in different
        // windows — so they are sequenced to read as one.
        .transition(.island)
    }

    /// Every text label in the wing, clamped to the wing.
    ///
    /// The clamp is the fix for a whole class of bug rather than one label:
    /// nothing stopped the row running across the cutout, so a long enough
    /// string was drawn *behind the camera housing*. Truncating is visible
    /// and honest; disappearing is neither. Only the text labels are clamped
    /// — the shelf's chips and the padlock are sized by their own layouts.
    private func label(_ systemName: String, _ text: String, tint: Color) -> some View {
        HStack(spacing: CompactLabel.spacing) {
            Image(systemName: systemName)
                .font(.system(size: CompactLabel.glyphSize))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(.caption2, design: .rounded).monospacedDigit())
                .lineLimit(1)
        }
        .frame(maxWidth: wingWidth, alignment: .leading)
    }

    /// The island is symmetric about the cutout, so the left wing is half
    /// the extra width, less the padding the row already carries.
    private var wingWidth: CGFloat {
        max(0, store.layout.compactExtraWidth / 2 - (NotchRadii.compact.bottom + 2))
    }

    private func open(_ shot: ScreenshotCatch) {
        NSWorkspace.shared.open(shot.url)
        store.removeFromShelf(shot)
    }

    private func batteryGlyph(_ info: BatteryInfo) -> some View {
        HStack(spacing: 3) {
            Image(systemName: BatteryGlyph.symbolName(percentage: info.percentage, isCharging: info.isCharging))
                .foregroundStyle(BatteryGlyph.tint(percentage: info.percentage, isCharging: info.isCharging))
                .contentTransition(.symbolEffect(.replace))
                // Driven by `BatteryService`'s own tick rather than this
                // view's mount/onChange timing: the glyph can also appear
                // because of an unrelated compact peek (screenshot, wave,
                // greeting), and that must never borrow a charge bounce it
                // didn't earn.
                .symbolEffect(.bounce, value: store.batteryBounceTick)
            Text("\(info.percentage)%")
                .font(.system(.caption2, design: .rounded).monospacedDigit())
                // Digits roll rather than pop when the charge moves.
                .contentTransition(.numericText(value: Double(info.percentage)))
                .animation(Motion.resolved(Motion.textSwap), value: info.percentage)
        }
    }
}
