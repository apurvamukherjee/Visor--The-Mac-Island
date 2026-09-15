# Phase 5 — Premium music surface

Four changes to the expanded music view: ambient art bleed (A), cursor
parallax on the art (C), play/pause art morph (F), vinyl fallback for art-less
tracks (H). Progress-as-bottom-lip (B) was scoped and cut before build — see
"Cut from this phase". Phase 6 (volume/brightness
HUD, full battery states) is scoped at the end of this file but not built here.

Constraint every task inherits: no audio buffer access exists, so nothing here
pretends to react to sound. §5.1b holds — never animate a layout property in a
loop; anything continuous is CALayer or it doesn't ship.

## Cut from this phase

**B (progress as the island's bottom lip) — cut by decision, not by blocker.**

Recording what was verified, so it doesn't need re-deriving if it comes back:
`MediaRemoteAdapter/TrackInfo.swift` exposes `durationMicros`,
`elapsedTimeMicros`, `timestampEpochMicros`, `playbackRate`, and a
`currentElapsedTime` helper; `MediaController` exposes `setTime(seconds:)`.
Position is an *anchor plus a rate*, so a lip could set one `CABasicAnimation`
with `duration = remaining/rate` and let the render server own the rest of the
song — no timer, no per-second store write, §5.1b intact. Seek is a real
command. Cheap whenever it's wanted; just not now.

Consequence for this phase: `NowPlayingInfo` is untouched, `NowPlayingService`
is untouched, and the only continuous animation introduced anywhere is H's
vinyl rotation.

## Correction to the brief

The Phase 5 brief said A could reuse "the Reduce Transparency fallback, same as
`.hudWindow`". There is no such fallback in the code. `NotchRootView.islandSurface`
documents that both an `NSVisualEffectView` material and a blurred outer bleed
were tried and reverted — the material washed grey against bright wallpaper, and
the blur smeared a halo onto real screen outside the silhouette. The rule
"pure black, hard-edged, in every state / nothing paints outside the silhouette"
is live.

A therefore **bends a standing rule on purpose**. It is allowed here only under
the guardrails in Task 1, and only in the expanded state — closed and compact
stay pure black, which is what the invisibility rule actually protects.

---

## Task 1 — Ambient art bleed (A)

**New:** `Visor/UI/AmbientArtBleed.swift`
**Edit:** `NotchRootView.islandSurface`

A downsampled, heavily blurred copy of the album art painted *inside* the shape,
under all content, at low opacity.

Rules it must not break:
- Clipped with `.clipShape(shape)` — the blur must never extend past the
  silhouette. This is the exact failure that killed the earlier attempt, so the
  blur is applied to the image *then* clipped, never to the shape itself.
- Expanded state only. `store.state == .expanded && store.nowPlaying != nil`.
  Closed/compact keep `.fill(.black)` untouched.
- Opacity ceiling `0.14`. Composited over black, on top of, not instead of, the
  black fill.
- Off entirely when `NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency`
  or `...ShouldIncreaseContrast` is true.
- Static. Crossfades on `trackIdentity` change with `Motion.artSwap`; never
  animates otherwise.

Blur via a pre-blurred `CIGaussianBlur` in `ArtworkCache` rather than SwiftUI
`.blur()` on a live view — SwiftUI's blur re-rasterises on every state change of
the island, and the island changes state constantly. Cache one blurred CGImage
per track alongside the existing decoded one.

**Verify:** bright white cover on a bright wallpaper — island must still read
black. Screenshot closed state before/after; pixels must be identical.

## Task 2 — Cursor parallax (C)

**Edit:** `NotchContentView` (add `.mouseMoved` to tracking options),
`NotchStore` (add `hoverPoint: CGPoint?`), `ExpandedMusicView.artworkView`

`mouseMoved` is event-driven; it fires only while the cursor is inside the
silhouette, which `hitTest` already gates. No global monitor, nothing running
when the pointer is elsewhere.

Store normalised (-1...1) position; art gets `rotation3DEffect` on both axes,
±6°, with the existing `perspective: 0.6`. Must compose with the flip's
`flipAngle` rather than fight it — parallax applies to the outer container, the
flip stays on the inner face, or a track change mid-hover will tear.

Off under Reduce Motion. Clear `hoverPoint` on `mouseExited` and spring back to
zero.

**Verify:** track change while the cursor sits still over the art — flip must
still read correctly, not mirrored or skewed.

## Task 3 — Play/pause art morph (F)

**Edit:** `ExpandedMusicView.artworkView`

On `info.isPlaying` false: `.saturation(0.65)` and `.scaleEffect(0.96)`, spring
back on true. One spring on transform + a filter, fired by a real user event.
`Motion.artSwap` is the right existing token — no new token needed.

Interaction with Task 2: both write transforms on the same view. Apply scale
before rotation so parallax doesn't amplify with scale.

**Verify:** pause/play rapidly — must not accumulate or stutter.

## Task 4 — Vinyl mode (H)

**New:** `Visor/UI/VinylDisc.swift`, `Visor/Support/Preferences.swift`
**Edit:** `ExpandedMusicView.artworkFace`, `SettingsView`, `SettingsWindowController`

**Changed from the original brief during build:** vinyl is a *Settings toggle*,
off by default — not an automatic fallback for art-less tracks. Swapping the
art out from under the user based on whether a podcast happened to ship a cover
made the island's appearance unpredictable, which is the opposite of clean. Now
it's a deliberate choice that applies to everything, and the art-less case keeps
its plain placeholder.

`Preferences.vinylMode` is a single `UserDefaults` bool, read in both places
through `@AppStorage` so the island updates live while the Settings window is
still open.

Disc construction: radial-gradient base, concentric groove hairlines, a tinted
centre label with a punched spindle hole (`fillRule = .evenOdd`), album art
inside the label at 0.85, and a *fixed* diagonal sheen that does not rotate —
so the spin reads as motion under a light rather than a dragged texture.

Two conflicts the toggle created, both resolved in `ExpandedMusicView`:
- The card's 12pt corner radius would crop a round disc flat, so the clip
  becomes a full circle in vinyl mode.
- The track-change card flip fights a record that is already turning, and a
  disc has no back face to reveal — vinyl takes the crossfade path instead.

Power rules, same as `PlaybackBars`: `CALayer` + `CABasicAnimation`, animation
*removed* rather than paused on pause/Reduce Motion, and `viewDidMoveToWindow`
tears it down when the view leaves the window.

## Post-integration pass (live feedback, 2026-09-16)

Three fixes and two tuning changes after running it on hardware.

**Bug — collapse popped square-cornered.** Two `.animation(_:value:)`
modifiers added for the bleed sat below `shape.fill(.black)` in
`NotchRootView`, so the one keyed on `store.state` captured the shape as well
as the wash. `bottomRadius` then animated on `Motion.contentOut` (0.14s)
instead of the controller's ambient `Motion.close` (0.34s) and finished ahead
of the frame. Fixed by wrapping the overlay in a `Group` and scoping both
animations to it. Rule worth keeping: `.animation(_:value:)` placed under a
shape will hijack that shape's own animatable data.

**Bug — pale slab above and below the island.** `AmbientArtBleed` uses
`scaledToFill` by design and relied on the caller's `.clipShape(shape)` to
bound it. Inside `.overlay`, before `body`'s `.frame(currentSize)`, both the
image and the clip resolved against the full canvas — which is taller and
wider than the visible island — so the wash painted outside the silhouette.
Fixed with an explicit `.frame(width:height:)` on the bleed ahead of the clip.
This is the §2.4b rule failing in practice, not in theory.

**Bug — vinyl sheen stacked every layout.** The sheen is a sibling of `disc`
(a child would rotate with the record), so `drawGrooves`' cleanup of
`disc.sublayers` could never reach it, and each layout pass added another
translucent gradient. Now held in a property and reused.

**Tuning — parallax made prominent.** 6° was real but unnoticeable; raised to
12° and added a 1.04 hover scale so the card leans toward the cursor rather
than only rotating under it. The pause shrink and the hover lift multiply, so
a paused card still responds.

**Tuning — vinyl grew and gained a tonearm.** Disc runs at 72pt against the
cover's 56pt (out of the music column's vertical slack — the island's own
168pt is unchanged), inset to 0.88 of its box so the tonearm's pivot has
somewhere to sit. The arm and its pivot dot are siblings of `disc`, swinging
between a parked 26° and a playing -6° on one `CATransaction` per play/pause —
no loop. It replaces `PlaybackBars` in vinyl mode, where a bottom-trailing
badge would have sat outside the circle, and it is what tells a still frame
whether the record is turning.

## Second post-integration pass (2026-09-16)

**Bug — the wash expanded before the notch.** Distinct from the slab bug
above, and the one the user described precisely. `expand()` sets the panel
frame instantly (`setFrame`, unanimated) and animates only `store.state`, so
`state == .expanded` is true from frame one and the wash is already at full
size while the black shape is still growing. Given its own
`.animation(value: store.state)` it faded in on `Motion.contentOut` (0.14s)
against the shape's `Motion.open` (0.45s) and won the race — a pale box
appearing, then the notch catching up over it. Fixed by dropping that
modifier and giving the bleed `.transition(.island)`, the same delayed-in
(`contentIn`, 0.08s delay) / fast-out curve the expanded content already
uses. This is the "shape leads, content follows" rule; the wash is content.

**Screenshot chip now clears on drop.** `.draggable(shot.url)` has no
completion callback, so a dragged-out catch stayed in the notch with nothing
left to offer. Replaced with `.onDrag` + an `NSItemProvider` whose
`registerFileRepresentation` load handler dismisses the catch once a receiver
actually takes the file. A cancelled drag never reaches the handler, so the
chip survives to be tried again.

**Tonearm rebuilt from real turntable geometry.** The first version was a
straight stick, which is wrong in four ways. Sources: Fluance's tonearm guide
and Audio-Technica's setup docs for the parts, Analog Planet / thegrooveman
for the geometry. Now has:
- a **counterweight** behind the pivot (without the mass behind it, an arm
  reads as a stick glued to the deck)
- an **S-shaped tube** — two arcs, which is what distinguishes an S-arm from
  a J-arm, not one bend
- a **headshell** canted at the **offset angle**, ~22° on a typical 9" arm,
  the cant that puts the cartridge tangent to the groove
- rest and play angles that mean something: parked at 30° on the rest, down
  at 3° in the **lead-in groove at the outer edge**, which is where a real arm
  starts a side — the old -6° put it over the middle of the record
- a 0.55s cueing swing, because a real cue lever lowers the arm deliberately

The arm holds at the lead-in rather than tracking inward: without playback
position (B was cut) we don't know how far through a track we are, and an arm
creeping on a guess would be a lie. Honest limitation, noted here in case B
ever lands.

**Animation-timing audit.** Swept every `.animation(_:value:)` in `Visor/UI`
and `Visor/Window` for the class of bug that bit twice. All remaining ones are
pre-existing and benign. One latent case worth recording, not fixed because it
is not mine and does not currently misfire: `NotchRootView`'s
`.animation(Motion.layout, value: store.nowPlaying == nil)` sits on the
outermost view, and when music stops `currentSize` changes (168 -> 186pt), so
`Motion.layout` — not the controller's animation — drives that resize. It only
fires when the controller is not simultaneously animating, so it is currently
invisible.

**Rule for the file:** a `.animation(_:value:)` placed anywhere beneath the
island's shape, or on a view whose size depends on island state, will hijack
the shape's own animation away from the controller's ambient `withAnimation`.
Scope such modifiers to the subview that needs them.

## Measured on the running app (2026-09-16)

Debug build, idle with the island closed, pid sampled for 5s at 1ms:

- **CPU: 0.0%**, flat across six 2s samples, no drift
- **Physical footprint: 13.6 MB** (peak 56.8 MB) — RSS reads ~76 MB but that
  is mostly shared framework pages. Budget in §5.1 is < 60 MB.
- **Zero frames** in `CA::Transaction::flush_as_runloop_observer` and zero in
  `NSHostingView.layout()` — the two symbols from the §5.1b regression
- All 4292 main-thread samples in `mach_msg2_trap`, i.e. blocked in the
  kernel waiting for events. Fully event-driven, nothing polling.

## Third pass — the wash became a halo (2026-09-16)

**Cut the panel-wide wash.** Live verdict: it "looked cheap all over". At
panel scale a blurred cover is a gradient smeared across the island; it fights
the black surface and undoes the thing that makes the island read as part of
the hardware. Task 1's premise was wrong, not just its tuning.

**Replaced with a halo behind the artwork only.** `AmbientArtBleed` now takes
the cover's `side`, draws at 1.9x that, and is masked by a radial gradient so
it fades to nothing before its own bounds — the mask is what stops it being a
blurred square with an edge, which is how the panel version failed. It sits in
the card's `.background`, outside the clip, or it would be cropped back into
the square it exists to soften. `.plusLighter` at 0.55 so it adds light rather
than greying the surface.

**The island surface is pure black again in every state**, and RESEARCH's
decision-table rule is unconditional once more. §2.4b was rewritten from
"ambient art bleed" to "album halo" with the narrower constraints; the
Phase 5 entry in CLAUDE.md describes the wash and should be read against this
section.

Re-measured after the rework: idle CPU 0.0%, flat across four samples.

## Review fixes (2026-09-16)

Three no-ship findings, all real, all fixed:

**Release artifacts could be overwritten** (`make-dmg.sh`). Adding the
timestamp dropped the old `-2`/`-3` collision loop, so two builds of the same
commit inside one minute resolved to the same permanent path and `cp` silently
replaced the earlier artifact. Stamp is now seconds-resolution, and an
existing release path is a hard failure rather than an overwrite — these files
are history.

**A stale drag could dismiss a newer screenshot.** The provider's load handler
called a generic `onDismiss` that always cleared the store. A provider outlives
the chip that made it, so a receiver loading an old drag after a newer catch
arrived would wipe the catch the user was looking at. Added
`NotchStore.dismissScreenshot(_:)`, which clears only if the named catch is
still current, plus a dedicated `onDropCompleted` callback so the ordinary
close button keeps its unconditional behaviour.

**The halo was penned into a cover-sized slot.** It was attached via
`card.background`, and a background is sized to the view it backs — so a glow
drawn at 1.9x the cover had nowhere to go. (The reviewer's stronger claim, that
`card`'s internal `.clipShape` masked the background, is not how SwiftUI
composes a background; the sizing was the real defect.) Now a ZStack sibling
behind the card, with an explicit `.frame(side)` on the stack so the decoration
cannot claim layout space and shove the title column sideways.

**One simplification declined.** A review suggested folding `flipAngle` and
`tilt.x` into a single Y-axis `rotation3DEffect`. They share an axis but cannot
be summed: the flip depends on hitting exactly ±90°, the edge-on frame where
the card has no width and the image swaps unseen. Adding a live tilt puts that
frame at 78° or 102°, where the card is still visible and the swap becomes a
glitch. Left as three modifiers with a comment recording why.

Remaining cuts from that review (tonearm, disc sheen, base gradient, label
artwork, the `nowPlayingBleed` pipeline) all change the rendered UI, which the
brief for this pass explicitly ruled out. Not taken.

Re-verified after the fixes: build, 46/46 tests, swiftformat, swiftlint 0
serious, idle CPU 0.0%.

## Task 5 — Verification pass

- `xcodegen generate`
- `xcodebuild -scheme Visor -configuration Debug build | xcbeautify`
- `xcodebuild -scheme Visor test | xcbeautify` — existing 34 must stay green
- `swiftformat .` && `swiftlint`
- New unit tests (pure logic only, per CLAUDE.md):
  - blurred-artwork cache keying by trackIdentity, and that a nil/greyscale
    cover yields no bleed
  - parallax normalisation maths (centre = 0, corners clamp to ±1)

Idle CPU must return to 0.0% in all four states: closed, compact, expanded
paused, expanded playing.

## Manual checklist (needs real hardware)

1. Closed state pixel-identical to pre-Phase-5 — the invisibility regression guard
2. Bright cover + bright wallpaper: island still reads black
3. Reduce Transparency on: bleed gone entirely
4. Reduce Motion on: no parallax, no vinyl spin, flip falls back to crossfade
5. Increase Contrast on: bleed gone, bars white
6. Track change mid-hover with parallax active
7. Podcast (no art) → vinyl; `sample` after collapse shows nothing running
8. Space switch and sleep/wake with music playing — animations resume correctly

---

# Phase 6 — scoped, not built

## Volume / brightness HUD

`AudioObjectAddPropertyListener` on `kAudioHardwareServiceDeviceProperty_VirtualMainVolume`
for volume. Brightness has no public notification on 14.0 — `NSScreen` posts no
backlight change; the usual route is the private `DisplayServices` framework.
**Unverified — needs a spike before it's planned.** Ship volume first; brightness
only if a public path exists.

Revives `ActivityKind.hud`, which `Activity.swift` already documents as
"modelled ahead of the phase that produces it". Suppressing the system HUD is a
separate question (and may not be possible without private API) — if it can't
be suppressed, we'd be showing two HUDs, which is worse than none. Resolve that
before building.

## Full battery states

`BatteryService` already has the IOKit run-loop source and a peek mechanism.
Add: 20%/10% low thresholds firing `schedulePeek()` with a warning treatment,
Low Power Mode via `ProcessInfo.processInfo.isLowPowerModeEnabled` +
`.NSProcessInfoPowerStateDidChange`, yellow tint on the battery glyph.
Fire each threshold once per discharge cycle — latch and reset on charge, or a
battery hovering at 20% will peek on every IOPS notification.

~30-40 lines, no new plumbing. This is the cheapest item in either phase and
should ship first.
