# Visor feature program — design

Date: 2026-09-22. Covers everything scoped in the session of 2026-09-22:
the repo audit, the competitor research (Alcove, NotchNook, NotchBox,
MediaMate, MewNotch, Atoll, boring.notch, Notchy, DynamicLake), the
interaction findings against Visor's own code, and the 33-row feature matrix
the user supplied.

Three phases. Nothing here is implemented; each phase gets its own
implementation plan before any code.

## 1. Goal and constraints

Close the feature gap with the paid notch apps without becoming one of them.
The user's framing, verbatim: *"let it consume more resources, but lets keep
it to the minimum or lesser than the ones out there, but not compromise on
performance or UI feel."*

Standing constraints from CLAUDE.md that still hold everywhere they are not
explicitly suspended below:

- Event-driven only. No polling loops. No global mouse monitors.
- Nothing animates or ticks when not visible, not playing, or display asleep.
- No third-party Swift packages without approval.
- Single source of truth: `NotchStore`. Views read, services write.
- A feature never imports another feature.
- All animation from `Motion` tokens; all spacing from `IslandSpacing`.

## 2. Decisions taken

The user selected "poll only while open", "full polling", and "take the
Accessibility prompt" together. The first two conflict, so they are read
per-feature — the only reading under which both are true:

| Decision | Resolution |
|---|---|
| Clipboard history | **Full polling.** `NSPasteboard` exposes only `changeCount`; history that records only while the island is open is not history. Ships **off by default** so the idle number survives for anyone who does not opt in. |
| Live system stats | **Poll only while the island is open.** A CPU graph nobody is looking at is waste, and gating costs the feature nothing. |
| Accessibility permission | **Accepted.** One prompt unlocks window snapping, menu-bar icon hiding, and text expansion. This reverses the stance that cut the media-key HUD; RESEARCH §6 must be updated to say so and why. |

Consequence to record honestly: the README's `idle CPU 0.0%` badge becomes
"0.0% idle at default settings", with clipboard history's cost measured and
stated separately. **Confirmed by the user, 2026-09-22.**

## 2.1 Governing rule — nothing changes by default

**Every behavioural change in this program ships as a toggle in a new
"New Features" tab in Settings, defaulting to today's behaviour.** The
island someone is using right now must look and act exactly the same after
each phase unless they opt in.

This applies to the interaction fixes as much as to the features. Three of
them are things this design argues *should* be on — the close-intent delay,
the visible drop zones, the swipe-down open — and they still ship off, with
a recommendation, not a default.

Exceptions, narrowly:

- **Pure deletions** (§4a) change no behaviour by definition and need no
  toggle.
- **Outright bugs** are fixed in place, no toggle — the precedent is the
  volume fix of 2026-09-22, where the island simply never appeared on a
  Bluetooth output. A toggle for "show the volume island correctly" would be
  absurd.
- **`Dwell` tokens** (§4b) are an internal refactor: every service keeps its
  *current* value, now under a name instead of a literal, so the visible
  timing is unchanged on day one. Tiering them is Phase 8's job — see §9.4
  for why three tiers cannot be reconciled with this rule.

Consequences for the build:

1. A `NewFeatures` settings tab and a matching preferences group, added in
   Phase 6 before the first toggle needs it.
2. Each toggle is a key in `Preferences` and belongs in `resettableKeys`.
3. Each toggle's default is the *current* behaviour, so "Restore defaults"
   returns the app to today's Visor, not to the new program.
4. Features that are new surfaces rather than changes (palette, shelf tabs,
   stats, clipboard) default **off** — an island that grows new panels
   unasked is the same violation as one that changes its hover behaviour.

## 3. Already shipped — do not rebuild

The supplied matrix lists these as gaps. They exist:

Now Playing controls · device battery (mouse/keyboard) · AirPods connected
reveal · download finished alerts · calendar widget · lock screen widgets ·
volume HUD (brightness missing) · swipe gestures · capsule mode on
non-notch screens · hide-in-fullscreen · display selection · five animation
speeds · screenshot shelf · AirDrop · timer · focus/network/Bluetooth peeks.

**Synced lyrics is a special case:** `LyricsFetcher`, `TrackLyrics`,
`LyricLine` and `LyricsPanelView` are fully written and wired to nothing —
the audit found them unreachable. This is a re-connection job, not a build.

## 4. Phase 6 — the palette and the commands it runs

The palette is the spine. Every "free win" below is a *command*; without a
palette each needs its own surface in an island that has no room for one.

### 4a. Groundwork — deletions from the audit

Pure removal, no behaviour change. Done first so 25 features are not added
on top of dead code.

| Cut | Detail |
|---|---|
| Dead ported views | `LightweightNowPlayingEqualizerView` (370), `LiquidGlassBackground` (324), `NowPlayingArtworkBackground` (157), `PlaybackSourceButton` (16), `NowPlayingSeekBar` (76) — zero call sites |
| One-shot scripts | `COMMITS.sh` (524), `COMMIT-PROMPTS.md` (123) — both say "delete this file afterwards" in their own headers |
| Dead config | `LockScreenSettings` sound keys (5 keys, 4 accessors, a legacy migration, nothing plays a sound) + their 4 `resettableKeys` entries |
| Dead environment | `notchScale` / `isDynamicIsland` are never written, making `Int.scaled(by:)`, `CGFloat.scaled(by:)` and both `isDynamicIsland ?:` branches in `LockScreenNotchView` dead |
| Dead tokens | `Motion.queuePacing`, `Motion.stretchReset`, `SkyLightPin.Level.aboveLockShield` |
| Duplication | Fold `SystemMute` into `VolumeService` (store already holds `volume.isMuted` + `volumeCommands.toggleMute`); collapse `NowPlayingEqualizer` into `PlaybackBars` |
| Dependency | Lottie → native `Text` reveal for the Welcome step. **Drops an SPM package**; CLAUDE.md already claims none was added |
| Stdlib | `mm:ss` hand-rolled in 3 places → `Duration.formatted(.time(pattern:))`; `GreetingService`'s `yyyy-MM-dd` `DateFormatter` → `Calendar.isDateInToday` |
| Hygiene | Drop the `Visor/UI/Player` swiftformat/swiftlint exclusion once the dead files are gone (3 live files remain); delete stale `docs/superpowers/plans/`; fix `README.md:119`, which advertises shuffle, repeat and a lyrics panel that `MusicSeekRow.swift:5` says are gone |

### 4b. Interaction optimizations

These set the feel that all 25 new features inherit, so they precede the
features. Per §2.1 every one of them ships as a **New Features** toggle,
default off. The recommendation column is advice, not a default.

| Change | Toggle | Recommended |
|---|---|---|
| Close-intent delay | `closeIntentDelay` | on |
| Visible drop zones | `visibleDropZones` | on |
| Swipe-down opens | `swipeDownOpens` | on |
| Hover delay value | `hoverIntentDelay` (slider) | 120ms, today's value |
| `Dwell` tokens | none — internal, §2.1 | n/a |

**Close-intent delay.** `NotchWindowController:27` filters *opening* through
a 120ms `hoverIntentDelay`; `handleMouseExited` (127-132) collapses with
zero delay. The island is deliberate about opening and twitchy about
closing — clipping the edge while reaching for the scrub bar slams it shut
mid-gesture. Mirror the existing pattern with a 150-200ms close delay,
cancelled on re-entry. Reuses machinery that already exists.

**`Dwell` tokens.** Peek durations have drifted to seven values across nine
services: 2.0 (Focus), 2.5 (Battery), 3.0 (Bluetooth), 3.5 (Greeting), 4.0
(DeviceBattery, Download linger), 5.0 (pause collapse), 6.0 (Battery alert),
1.6 (Volume), 3.0 (AirDrop linger). This is exactly the drift `IslandSpacing`
exists to prevent — its own comment: *"Features never see each other, so left
to themselves they drifted to their own numbers."* Same medicine: a `Dwell`
enum, every service reading from it. **One case per existing value, not three
tiers** — nine services hold seven distinct numbers, so tiering them now would
move timings that §2.1 says must not move (§9.4). Naming them is still what
makes Phase 8's configurable timing one file instead of nine.

**Drop zones made visible.** `NotchRootView:134` gates AirDrop on
`NSEvent.modifierFlags.contains(.option)` — documented in the README, which
is where features go when the UI cannot say them. NotchNook shows both
targets the moment a drag enters. Visor already tracks `isDropTargeted` and
draws a highlight ring; split it into two labelled zones (Stash / AirDrop)
on drag-enter. Same interaction, made visible. ⌥ keeps working.

**Swipe-down opens.** Currently swipe-down only restores a dismissed
activity, so it does nothing in the common case. NotchNook and Atoll both
use it as open. Already wired through `resolveAxis`.

**Hover delay as a setting.** 120ms stays the default; MewNotch exposes
this and it is the cheapest answer to "it opened when I didn't mean it to."

### 4c. The command palette

⌃⌥K via `RegisterEventHotKey` (Carbon), which needs **no permission** —
unlike a `CGEventTap`. This is why the palette is cheap and the text
expander (Phase 8) is not. Fuzzy-matched command list rendered inside the
island, in its own expanded layout via `IslandLayout`.

### 4d. The commands

Each is a `NotchService` plus a palette entry. No new UI surface each.

| Command | Mechanism | Permission |
|---|---|---|
| Caffeine toggle | `IOPMAssertionCreateWithName` | none |
| Audio output switcher | CoreAudio `kAudioHardwarePropertyDefaultOutputDevice` (write) | none |
| System-wide mic mute | CoreAudio input scope mute | none |
| Hide the notch | existing panel ordering | none |
| Quick notes | local file | none |
| Zip / unzip | `NSFileCoordinator` / Foundation | none |
| Image converter (HEIC/JPG/PDF) | ImageIO — already linked for artwork | none |
| Pomodoro | `TimerService` + preset cycle | none |
| **Synced lyrics (revive)** | existing dead `LyricsFetcher` / `TrackLyrics` / `LyricsPanelView` | network |

The audio switcher and mic mute reuse exactly the CoreAudio surface mapped
while fixing the volume bug on 2026-09-22 — same address/scope/element
helpers, already proven against Bluetooth, USB and built-in outputs.

## 5. Phase 7 — the shelf, the HUDs, the permissions

### 5a. Shelf program

Generalize `ScreenshotCatch` to any file; add persistence across restarts,
keep-until-dismissed (today: `visibleSeconds` sweeps at 60s), and the app
launcher tab. This is NotchNook's and NotchBox's entire product, built on a
UI that is already finished — 4-up chip row, drag-out providers that outlive
their chip, drop targeting, expanded shelf layout.

### 5b. HUD completion — **probe before promising**

| Item | Risk |
|---|---|
| Brightness HUD | No clean public API. RESEARCH §6.3 already lists it as "DisplayServices (private) / observed key events — varies". MewNotch ships it, so it is possible. Needs a standalone probe first, exactly like the volume fix |
| Stock HUD suppression | Without it a volume press draws **two** overlays — Visor's and macOS's. MewNotch offers "completely hide the stock macOS HUDs". Mechanism is OSDUIHelper territory and likely hacky; probe before committing |

### 5c. Permission-gated, each opt-in

Camera mirror (camera) · camera guard / camera-access alerts (camera
usage monitoring) · Apple Reminders capture (Reminders TCC — separate from
the calendar grant Visor already holds) · Run Apple Shortcuts.

### 5d. Free-standing

Privacy indicators (mic/camera in use — event-driven, fits the activity
ladder exactly, no new permission; highest value-to-risk on the whole
program) · per-display configuration (today Visor picks one display;
MewNotch and Atoll configure each) · minimal vs standard density mode (Atoll
and Alcove both have one) · battery time-remaining toggle · volume/brightness
step size · custom item ordering.

## 6. Phase 8 — power tools

Grouped so the cost lands in one place instead of bleeding through the app.

### 6a. Polling tier

- **Clipboard history** — full polling of `changeCount`, off by default.
- **OCR / searchable clipboard** — Vision framework, no permission, depends
  on clipboard history existing.
- **Live system stats** — CPU/RAM/network/disk, polled **only while the
  island is open**.
- **AI usage tracker (Claude / Codex / Cursor)** — **probe first.** These
  tools write usage to files on disk, so FSEvents may serve and this may
  escape the polling tier entirely. Visor already uses FSEvents for
  `DownloadService`.

### 6b. Accessibility tier — one prompt, three features

Window snapping (drag to notch) · menu-bar icon hiding · text snippets /
expander. The expander is the reason the prompt is needed: it requires
watching every keystroke system-wide, which is the exact permission the
media-key HUD was cut to avoid.

### 6c. Heavy and deferred-by-design

- **Built-in terminal.**
- **Configurable expansion triggers** (MediaMate's model: expand on track
  change / play-pause / volume change, with dwell time). Held to Phase 8
  deliberately — four new settings for a preference most people set once, in
  a Settings window that already has five sections. Cheap only *after* the
  `Dwell` tokens of Phase 6 exist.
- **Two-stage expansion as a setting.** NotchNook's hover-peek / click-open
  is less intrusive than Visor's hover-opens-fully; Visor's is faster. Visor
  already has the three-state shape — the middle state is activity-driven,
  not hover-driven, so making hover land on `.compact` and requiring click or
  swipe-down for `.expanded` is nearly a one-line change to `scheduleExpand`.
  It changes the app's character, so it ships as a setting and is **not** the
  default until the user has lived with both.
- **Shortcut remapping.**

## 7. Probes required

Each of these is a throwaway CLI measured before any app code, following the
precedent of the volume HUD (2026-09-19) and the virtual-main-volume fix
(2026-09-22), both of which disproved a plausible assumption on contact.

1. Brightness — is there any non-private path to the *result* of a
   brightness change, as CoreAudio is for volume?
2. Stock HUD suppression — what actually silences macOS's own OSD, and does
   it survive a reboot and a macOS minor update?
3. AI usage tracker — do Claude/Codex/Cursor write usage somewhere FSEvents
   can watch, or is polling unavoidable?
4. Clipboard — measured idle cost of `changeCount` polling at the chosen
   interval, so the README's number is honest rather than asserted.

## 8. Cut, with reasons

- **iPhone-style call island.** There is no public API for iPhone call state
  on macOS; Continuity call handoff is not exposed. Not difficult — absent.
  Before believing a competitor's checkmark here, establish what their
  feature actually shows.
- **Localization to 134 languages.** Not a feature, a process: a permanent
  tax on every string change, and machine-translated UI in 134 locales is a
  checkbox rather than a benefit. **Assumption:** out of scope for these
  three phases. A real handful (5-10 hand-checked locales) is available if
  the user wants localization at all.

## 9. Resolved, 2026-09-22

All four were put to the user before Phase 6 began, and all four were
answered. Recorded here so a later pass does not reopen them.

1. Clipboard history ships **off by default**, and the README's idle-CPU
   badge gains "at default settings" rather than being dropped. **Confirmed.**
2. Localization is **out of scope** for phases 6-8. **Confirmed.**
3. **Settings becomes a `TabView`** — "Settings" (today's scrolling column,
   untouched) and "New Features". Settings has no tabs today, so §2.1's
   "New Features tab" needed one built; the alternative, a twelfth section
   at the bottom of an already-scrolling 560pt window, buries the toggles
   the rule exists to surface.
4. **`Dwell` is a set of named durations, not three tiers.** §4b asked for
   `acknowledge`/`read`/`alert` *and* for every service's current value to
   survive; nine services hold seven distinct values, so the two cannot both
   be true. The tokens therefore carry one case per real value — the drift
   becomes visible in one file and nothing moves on screen, which is what
   §2.1 requires. Collapsing them to three tiers is Phase 8's job, at the
   point where the timing becomes a user-facing knob and a change of value
   is the *point* rather than a regression.

## 10. Acceptance

Per phase, before it is called done: `xcodebuild build`, `xcodebuild test`
(currently 177 tests in 35 suites), `swiftformat .`, `swiftlint` — actual
output reported, not "should work". Every new service conforms to
`NotchService` with a `stop()` that releases processes, observers and
run-loop sources. Idle CPU re-measured with `sample` at the end of each
phase, against the phase's own default settings. RESEARCH.md updated
wherever a decision here changes one already recorded there — in particular
§5 (power) for the polling exception and §6 (permissions) for Accessibility.

Plus the §2.1 check, which a reviewer should run first: **with every New
Features toggle off, the island behaves exactly as it did before the
phase.** A test pins each toggle's default to today's value, so a default
cannot drift silently in a later pass.
