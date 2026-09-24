# Visor — hardware checklist

The one list. Supersedes Phase 2 Task 10 (`~/.claude/plans/notchy-phase2-live-activities.md`,
outside the repo), Phase 3 Task 11 (`docs/superpowers/specs/2026-09-16-notch-content-layer-design.md`
§11) and the card stack's Task 7 list — all three are kept as history and
none is maintained any more.

**Ordered by machine state, not by phase.** The old lists made you plug the
charger in three times; this one groups by what has to be true, so each block
is set up once. Current as of **2.9.2 build 33**.

Corrections folded in from the 2026-09-24 audit: the expanded island has no
clock/battery row, the music card has no calendar column, and the mood chip
bar does not exist. Items testing those were deleted or rewritten.

---

## A. Idle — nothing playing, unplugged

- [ ] Idle CPU 0.0% in Activity Monitor → Energy, with the island closed.
- [ ] Closed island is **invisible** against the hardware notch. Regression
      guard — a material and a blurred bleed were both reverted for this.
- [ ] Menu bar items beside the notch are clickable while closed. (Overlap
      while expanded is accepted, RESEARCH §0.)
- [ ] 30s of rapid hover in and out: no glitches, no stuck state.
- [ ] Collapse releases the expanded area immediately — beside-the-notch
      clicks pass through with no delay.
- [ ] Hover opens to the agenda + date + timer presets. An empty agenda gives
      a *smaller* island, not the same island with black in it.
- [ ] Double-click the idle island: the wave easter egg fires once.

## B. Charger

- [ ] Plug in while silent: charging glyph peeks both wings ~2.5s, then back
      to closed.
- [ ] Plug in **while music plays**: the glyph interrupts the music wings for
      ~2.5s, then the music wings return. This is the two-tier priority
      resolution (RESEARCH §2.6).
- [ ] Unplug: no peek. Edge-triggered on plug-in only.
- [ ] Battery Low and Full alerts appear as their own expanded card.

## C. Music playing

- [ ] Wings appear within one `Motion.morph` beat, without hovering.
- [ ] Expanded card is the player and **nothing else** — no calendar column,
      no clock row.
- [ ] Transport (prev / play-pause / next) actually drives the source app.
- [ ] Scrub the seek bar; it thickens under the pointer.
- [ ] Track skip: art flips, text rises into place, **the transport row does
      not move.** A fixed `MarqueeText` width is what guarantees this.
- [ ] Swipe left/right on the expanded card changes track.
- [ ] Mute button reflects and drives system mute.
- [ ] Open lyrics: the island widens to 473, the second column appears.
- [ ] CPU under 0.5% while playing and expanded, hovering repeatedly for 30s.
- [ ] Vinyl mode: the disc turns, the tonearm stays inside its own bounds,
      no equaliser badge on the disc.

## D. Paused

- [ ] Pause: the island collapses to the bare notch after **5s**, not
      instantly. (2026-09-20 — a pause is usually a step toward a skip.)
- [ ] Opening it by hand after that collapse still finds a transport row
      with a working play button. The track is deactivated, not cleared.
- [ ] Paused artwork dims and settles back slightly.

## E. Paging — music playing, `islandPaging` on

The shared box with a track loaded is **421x193**. Every item below is about
that number not moving.

- [ ] Swipe down cycles agenda → home → usage → (shelf) → agenda, no dead end.
- [ ] Swipe up cycles the other way, same absence of a dead end.
- [ ] **The island never resizes while paging.** The single rule §2.6b exists
      for.
- [ ] A swipe up on a *closed* island does not open it (that belongs to
      `swipeDownOpens`, and only with that switch on).
- [ ] The agenda page shows at most 2 rows plus "+N more" — one fewer than
      the idle home screen, on purpose.
- [ ] Short screens are **vertically centred**, not pinned high: volume,
      alerts, timer, shelf, and the usage page with only Claude's row. (2.9.1
      — this replaced the `.usage`-only fix.)

## F. Card stack — `pagingStyle` = Card Stack

- [ ] Chins peek below the front card and read as cards *behind* it, not as a
      lip on one silhouette.
- [ ] Chins are short cards, not full-height ones — the deck must not read as
      a slab with two slivers. (The 2.8.0 fault.)
- [ ] Swipe up brings the **visible** chin forward, not the hidden one.
- [ ] Closing retracts the chins *fully* before the squash: **no hard
      horizontal cut** at the bottom edge mid-close, and no chin fading in
      mid-air. (The 2.9.0 fault — it had three causes.)
- [ ] No chin ever pokes out *above* the front card while closing.
- [ ] Gradient families (Charcoal / Midnight / Ember / Slate and the four
      added in 2.8.0) each read against a bright **and** a dark wallpaper.
- [ ] Reveal slider at 0: chins appear immediately. At 1500: a beat and a half.
- [ ] Deck shows while music plays and the transport row is unmoved.
- [ ] One page reachable (idle island, paging on): no chins, no extra height.
- [ ] Reduce Motion: the deck does not animate depth changes.
- [ ] **Cross-fade selected: everything is exactly as it was**, including the
      island's height. This is the "nothing changes by default" guarantee.

## G. Catches — screenshot, AirDrop, download

- [ ] Take a screenshot **while music is playing**: the player keeps the
      island, the catch peeks in the wings, and the shelf is reachable by
      swipe. (The 2.9.0 fix — a catch used to end the music card outright.)
- [ ] The shelf page is absent when nothing is on it — a swipe never lands on
      an empty screen.
- [ ] Drag a file out of the shelf into Finder; it leaves the shelf.
- [ ] Drop an image file **onto** the island: it becomes the current catch.
- [ ] Option-drop: it goes out via AirDrop instead.
- [ ] Drop zones on (`visibleDropZones`): the halves are labelled and the
      landing half decides, with no modifier.
- [ ] **Known to fail:** dragging an image straight out of a browser. That
      vends TIFF/PNG data, not a file URL. Confirm it still fails, then it
      gets fixed.

## H. Volume

- [ ] Volume keys: the island appears with the bar, glyph and percentage,
      **centred** in the card.
- [ ] Works on the **built-in speakers, Bluetooth and an external DAC/HDMI**.
      (The `'vmvc'` fix, 2026-09-22 — already confirmed, re-check after the
      centring change.)
- [ ] Drag the bar: it thickens and the system volume follows.
- [ ] **Known gap:** at 0% and 100% nothing appears. macOS changes nothing at
      the rail, so CoreAudio fires nothing. Confirm, do not treat as new.

## I. Palette — ⌃⌥K

- [ ] ⌃⌥K opens it over any app, without stealing focus.
- [ ] Typing filters; no SwiftUI focus is needed because there is no
      `TextField`.
- [ ] Rows 1-4 fire on their number keys **only while the query is empty**.
- [ ] A bound letter key fires its command, same empty-query rule, and the row
      badge only advertises a key that would actually work.
- [ ] No command is offered that cannot act right now (`PaletteContext`).
- [ ] **Launch Groups:** configure one in Settings → Shortcuts, fire it, and
      confirm every app opens — including one that is already running (it
      should activate, not relaunch).
- [ ] An unconfigured launch-group slot never appears in the palette.
- [ ] Stash Clipboard: copy a file → stashed where it lives; copy an image →
      written to a file (PNG, not the enormous TIFF).

## J. Lock screen

- [ ] Lock: the padlock appears **in the notch**, above the real lock shield.
      The highest-uncertainty item in the whole project.
- [ ] With a track loaded and **playing**, the media panel appears, centred
      from the screen's own centre — not under the notch.
- [ ] Paused: no media panel.
- [ ] Unlock: the widget leaves immediately, with no ~1s linger.

## K. AI usage badge — `aiUsageTracker` on

- [ ] Badge renders beside the notch with today's Claude total. (Confirmed
      2026-09-23 against an independent count.)
- [ ] **Hides while music owns the island, returns when it does not.** Never
      verified.
- [ ] Not present on the lock screen.
- [ ] **Codex row against real data.** Run a real Codex session first —
      `threads.tokens_used` was empty when this was written, so the figure is
      schema-verified only.
- [ ] Set a daily budget in Settings → a percentage appears. No budget → no
      percentage, never a made-up denominator.

## L. Accessibility

- [ ] **Reduce Transparency** on: solid black fill, no material, no bleed, in
      every state.
- [ ] **Reduce Motion** on: no springs anywhere — open, close, art swap, deck
      depth, marquee scroll.
- [ ] **Increase Contrast** on: playback bars go white regardless of album
      colour.
- [ ] Both fallbacks fire on the activity-driven *and* hover-driven paths.

## M. Permissions and one-offs

- [ ] **Calendar denied:** revoke access → the island shows the music/idle
      layout with no nag and no blank crash.
      *Blocked until `DEVELOPMENT_TEAM` is set in `project.yml` — ad-hoc
      signing gives every build a new cdhash, so TCC re-prompts forever.*
- [ ] `DeviceBatteryService`: connect AirPods, confirm the peek. Never
      verified. The probe:
      `ioreg -r -c AppleDeviceManagementHIDEventService -l | grep -i BatteryPercent`
- [ ] Bluetooth connect/disconnect alerts fire, with **no** Bluetooth
      permission prompt at launch. (The payload is read from the
      notification; `IOBluetoothDevice.pairedDevices()` aborted the process.)
- [ ] Focus on/off and VPN up/down each produce their alert.
- [ ] Screen recording start/stop is caught (`CGSRegisterNotifyProc`,
      `dlsym`-resolved — a missing symbol must degrade, not crash).

## N. Multi-display, spaces, sleep

- [ ] Second display attached: the island lands on the chosen screen, and the
      layout is right on a screen **with no cutout** (capsule branch).
- [ ] Fullscreen app: the island hides if `fullscreenHide` is on.
- [ ] Sleep and wake: nothing ticks while the display is asleep; the greeting
      fires once on wake.
- [ ] Notch trim sliders (±16pt / ±4pt) move the geometry live.
