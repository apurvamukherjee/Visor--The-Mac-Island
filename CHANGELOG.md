# Changelog

All notable changes to Visor are recorded here. Versions follow
[Semantic Versioning](https://semver.org): `MAJOR.MINOR.PATCH`.

* **MAJOR** — a change that alters how the island behaves for someone who
  already uses it.
* **MINOR** — a new feature, backwards compatible.
* **PATCH** — a fix with no new feature.

Every release ships a `.dmg` in `new-releases/`, named
`Visor-<version>-build<n>-<date>-<time>-<commit>.dmg`. Those files are
permanent: new ones are added, **old ones are never deleted or overwritten**.
`scripts/make-dmg.sh` refuses to overwrite a release already on disk, and
rejects a `MARKETING_VERSION` that is not `MAJOR.MINOR.PATCH`.

Builds before 1.6.1 were named `Visor-1.5(11)-…`. They were renamed in place
to the scheme above when the convention was adopted; the bytes and the git
history are unchanged.

## [2.7.1] — 2026-09-23 (build 29)

### Fixed

- **The card stack did not work on the page it is most often seen on.**
  Measured, not guessed: with music playing the island is 421x193, and each
  card behind the front one was inset a flat 11pt — **2.6% per side** — while
  being drawn at the front card's full height to reveal 9pt of itself, so
  **95% of every card was hidden**. The deck rendered as one heavy slab with
  two slivers under it. Cards are now only as tall as the part that shows,
  and the inset is a proportion of the island's width, so the deck reads the
  same on the narrow idle island and the wide player.
- **The island changed size depending on whether music was playing** —
  421x193 with a track loaded, 366x190 without, a 55pt jump the moment
  playback started. Every screen is now measured against the player, so the
  card is one size always.
- **Swiping up reached the wrong card.** The card you can see peeking is the
  next one in the stack, but a swipe up was skipping past it to the one
  hidden behind. Up now brings the visible card forward.

### Changed

- **Cards behind the front one are dark gradients, not flat tints**, chosen
  from four families in Settings → New Features → Card colour: Charcoal,
  Midnight, Ember and Slate. Each card takes a lighter step of the family the
  further back it sits, so two adjacent cards stay distinct instead of
  merging into the black island above them. The old white/clear/orange tints
  gave the player page no colour at all.

### Removed

- Dead code found by an over-engineering audit: unused motion tokens kept
  alive only by their own tests, a write-only store field, an unused dwell
  constant and an unread command property. No behaviour change — with the
  paging style left on Cross-fade, this release is identical to 2.7.0.

### Not yet verified on hardware

- Which gradient family reads best against a bright wallpaper, and whether
  the retract beat before closing reads as deliberate or as lag. Both are one
  picker / one constant.

## [2.7.0] — 2026-09-23 (build 28)

### Added

- **Card stack paging.** An optional second way to draw the three expanded
  screens: the front card exactly as it was, and the two adjacent pages
  peeking below it as tinted chins that cycle endlessly in both directions.
  Chosen in Settings → New Features → Paging style. **Cross-fade remains
  the default** — the stack is off until it is selected.
- **Chin reveal delay**, a slider beside the hover delay (0–1500 ms,
  default 600). The island opens showing one clean card and the deck slides
  out a beat later; 0 ms shows the chins straight away.
- **Tint the front card**, a New Features switch. Off by default: only the
  chins carry colour, because the front card is also the colour the island
  *closes* in. On, the whole island takes the current screen's tint (the
  player stays black — it is the page with no accent of its own).

### Changed

- With the card stack selected, a swipe past the last screen wraps to the
  first instead of stopping. Cross-fade still clamps at both ends, exactly
  as before.
- Closing the island retracts the chins before the frame shrinks. This is
  correctness, not polish: the window frame must never be smaller than what
  is drawn, or the bottom edge is cut off in a hard horizontal line
  mid-close.

### Fixed

- Nothing. This release adds a feature and changes no existing behaviour —
  with the paging style left on Cross-fade, including the island's height,
  the app is identical to 2.6.2.

### Deliberately left out

- **Dragging the stack with the pointer.** Scrolling reaches every screen in
  at most one step, and a drag that follows the finger and rubber-bands is a
  second gesture system competing with the existing track-change swipe.
- **Tapping a chin to jump to it.** The panel is non-activating and a chin is
  9 pt tall.
- **Per-page tint customisation.** Three tints, each chosen to match what its
  page already shows.

### Not yet verified on hardware

- Whether 9 pt of visible chin is enough to read a tint against a bright
  wallpaper, and whether the retract beat before closing reads as deliberate
  or as lag. Both are single constants and tunable in one place.

## [2.6.2] — 2026-09-23 (build 27)

### Fixed

- **The usage page read as pinned high, with dead space below.** The box
  every paged screen shares is sized to cover whichever page needs the most
  height (§2.6b), so a usage screen with only Claude's row (~1 row) was
  shorter than the box driving its size — and the page's inherited
  top-alignment stranded it high instead of centering it. Only visible
  before Codex has also run today, since its row closes most of the gap.
  `.usage` now centers its content vertically; the shared top-alignment other
  pages rely on is unchanged.

## [2.6.1] — 2026-09-23 (build 26)

Paging stops resizing the notch, the shelf stops refusing files, and four
bugs are fixed. No new user-facing feature, so a patch release.

### Added

- **Stash Clipboard**, in the palette. A copied *file* is stashed where it
  already lives — duplicating a file the user chose the location of would
  leave two of them. Image data copied out of an app that never wrote a
  file is written to one, because the shelf holds URLs: a chip is dragged
  out *as a file*, and a bare image cannot be dropped into Finder.

  PNG is preferred over TIFF. Both are on the pasteboard after a
  <kbd>⌃</kbd><kbd>⌘</kbd><kbd>⇧</kbd><kbd>4</kbd>, and the TIFF is the
  lossless-but-enormous one macOS puts there itself.

  The row is **absent** when the clipboard holds neither, the same rule
  every other command follows. `NSPasteboard` is injectable, so the tests
  use a scratch board and never read the user's real clipboard.

### Changed

- **Turning a page no longer resizes the notch.** Every screen the swipe can
  reach resolves to one box, and the player measures it — so the player is a
  constant 421x193 and the agenda and the usage figures are drawn inside that
  same shape. A swipe cross-fades content; the outline holds still.

  The trade, measured rather than guessed: the agenda **page** shows two
  events and no timer presets, against the idle **home** screen's three
  events with presets. Three rows plus the overflow line is 178pt of extra
  height against the player's 160, so either cut put back would make the
  island taller than the card it opens on and the player's height would
  track how many meetings you have. The row the page gives up is counted by
  the "+N more" line rather than lost. Detail: RESEARCH §2.6b.

- **The page swap blurs.** It was a bare opacity fade, which was right while
  the shape moved under it and wrong once the shape held still — with
  nothing to soften the change the new screen simply appeared. Now the same
  `.island` transition open and close already use. No new curve, no new
  `Motion` token.

- **The shelf holds any file, not only images.** `adopt` rejected anything
  that was not an image and logged it, so a video, a PDF or a zip dropped on
  the island vanished with no sign anything had happened. The thumbnail
  pipeline already fell back to a glyph for whatever ImageIO cannot decode.
  (AirDrop was never affected — `AirDropService` has no type filter, so
  images and videos both went through it before this.)

- **New Features and Shortcuts are grouped `Form`s**, like the other three
  panes. They were hand-rolled `ScrollView`/`VStack`/`Divider` columns, so
  one settings window held two panes that looked like inset cards and two
  that looked like a plain document, a click apart. The hover slider now
  reuses the existing `LabeledSlider` rather than re-implementing it, and
  the dead "Nothing to try yet" empty state is gone — the feature list has
  seven entries and cannot be empty.

- **`PaletteCommand.Availability` is one case carrying a key path** in place
  of nine near-identical cases and a nine-arm switch that did nothing but
  name the `PaletteContext` field to read. Every new gate used to cost a
  case, an arm and a point of cyclomatic complexity; the clipboard gate
  tripped the limit on the tenth. The reason each gate exists moved onto the
  field it reads.

### Fixed

- **A swipe *up* opened a closed island.** Paging routed both directions
  through the same "open it if it isn't up" path, so turning paging on
  granted a behaviour that belongs to the *Swipe down to open* switch —
  which was off. Opening stays one direction, one switch. Landing is
  unchanged: every open still arrives on the player.

- **"Restore original settings" left Launch Groups behind.**
  `launchGroupsKey` was declared beside `paletteShortcutsKey` and never
  added to `resettableKeys`, so a restore wiped the shortcut *keys* and kept
  the ten named groups. `PreferencesRestoreTests` could not catch it: it
  iterates `resettableKeys`, so a key missing from that list is invisible to
  it.

- **A double rule in Shortcuts** — two consecutive `Divider()` under the
  gesture list. Gone with the `Form` conversion.

### Left out, deliberately

- **Dragging an image straight out of a browser onto the island** still does
  nothing. That vends TIFF/PNG *data*, not a file URL, and the drop target
  is `dropDestination(for: URL.self)`. Adding a second drop target for
  `Data` is not something SwiftUI does cleanly, and *Stash Clipboard* covers
  the same need for anything already copied. Revisit if it comes up in use.

- **A dedicated clipboard hotkey.** The palette already carries a bindable
  letter per command through *Settings → Shortcuts*, so a second hotkey
  registration would buy one keystroke and cost a new surface and a
  collision to handle.

## [2.6.0] — 2026-09-23 (build 25)

Rebuilds Settings as a sidebar window, and adds two palette commands for
when an app has stopped responding.

### Added

- **Force Quit Frontmost App**, in the palette. The row names the app, so
  you read what you are about to kill before you press the key. Cost is a
  synthesised keystroke, not ending a process — macOS has always let an app
  terminate another the same user is running, so this needs no new
  permission.

  Gated out where there is nothing sensible to quit:

  - **Visor itself.** The palette's panel is `.nonactivatingPanel`, so Visor
    is never frontmost while it is open — which is exactly why the read
    returns the right app. The guard is explicit rather than relying on it.
  - **Finder.** Force-quitting it is what Apple's own window renames to
    "Relaunch". It comes straight back, so the row would describe something
    that doesn't happen.

- **Open Activity Monitor**, via `NSWorkspace.openApplication` — the same
  call `openScreenshotTool` and Launch Groups already make, so no probe was
  needed. Never gated. Its keywords include "force quit", so it surfaces on
  that search too.

  Both are reachable by <kbd>⌃</kbd><kbd>⌥</kbd><kbd>K</kbd> then a letter
  bound in *Settings → Shortcuts*, like any other command. No new hotkey
  code.

### Changed

- **Settings is a sidebar window**, 760x500 and resizable, in place of one
  340x560 scrolling column. Five panes:

  | Pane | Holds |
  | --- | --- |
  | General | Name, animation speed, launch at login, replay tour, restore, quit, version |
  | Appearance | Display, hide in full screen, outline + width/opacity, width/height trims |
  | Now Playing | Vinyl, progress colour, equaliser, lock padlock + style |
  | New Features | Unchanged |
  | Shortcuts | Palette keys, launch groups, and the gesture sheet that used to sit mid-column |

  `SettingsSection` and its hand-rolled `Divider` stack are gone: `Form` +
  `Section` + `.formStyle(.grouped)` gives the right-aligned labels, grouped
  boxes and section footers natively. Explanatory text that floated between
  controls is now a proper section footer. The 361-line view became five
  files, none over 110 lines.

- **Restore defaults rebuilds the pane rather than reassigning each value.**
  Each pane owns its own `@AppStorage` now, so the old "clear the keys, then
  assign all fourteen values back by hand" trick cannot reach across four
  views. Restore clears the keys and bumps a token applied as the detail
  pane's `.id`; SwiftUI rebuilds the pane, `@AppStorage` re-reads, and an
  absent key shows its default. `Motion.preset` and the store's trim are
  still refreshed by hand, because they are caches of those keys rather than
  readers of them.

- **The gesture sheet's swipe line was wrong.** It read "Swipe up to
  dismiss, down to bring it back", which stopped being true when paging
  landed in 2.5.0. Now "Swipe up and down to turn between screens".

- **Two files split at the 400-line lint ceiling**, following the precedent
  `SystemCommands+Files.swift` set: `PaletteMatch` out of
  `PaletteCommand.swift` (416 -> 346), and the island's derived geometry out
  of `NotchStore.swift` into `NotchStore+Layout.swift` (464 -> 393). Every
  member moved is computed, so nothing left `@Observable`'s reach.

### Fixed

- **`titles("quit").first` answered "Force Quit Frontmost App".** Scores tie
  and the tiebreak is declaration order, and the new command had been
  inserted ahead of Quit Visor. Both moved to the end of
  `PaletteCommand.all`, so typing "quit" answers with the command whose
  title is that word again. Now pinned by a test, since the ordering is
  load-bearing and invisible.

### Notes

- The maximal-context availability test needed the new field, or
  `everything.count` would have quietly stopped meaning "everything".
- Settings was **not** seen on screen before release: launching a second
  Debug instance would have fought the running copy for the notch and the
  lock windows. Everything in *Changed* above is unverified by eye.

## [2.5.0] — 2026-09-23 (build 24)

Turns the usage screen into a pager, and fixes two bugs it exposed.

### Added

- **Swipe between screens.** The expanded island now turns between three
  screens on the vertical axis, and the player sits in the **middle** —
  it is the only one of the three with controls on it, so the thing you
  operate is the resting position and the common case needs no swipe at all.

  ```
  agenda  ↑   the quick look up
  player  ●   home — the only screen with controls
  usage   ↓   the quick look down
  ```

  Opt-in: *Settings → New Features → Swipe between screens* (renamed from
  "Swipe down for agent usage"; the stored key is unchanged, so an existing
  toggle stays on). With it off, swipe-to-dismiss behaves exactly as it
  always did.

### Fixed

- **Music vanished after a few swipes.** Swipe-up still called
  `dismissCurrentActivity()` while the paging branch had taken swipe-down
  outright — so `restoreDismissedActivity()`, the only route back, had
  become unreachable. Two swipes up threw the player away permanently.
  Paging now never deactivates anything; dismiss and restore survive only on
  the toggle's off path. `pagingAwayAndBackAlwaysFindsThePlayerAgain` pins
  it.

- **The island grew before it closed.** `collapseFromExpanded` cleared the
  page first, which re-resolved `store.layout` from the usage screen to the
  player's larger card *while the island was still open* — so you watched it
  expand, then shut. The reset moved into `expand()`, where the island is
  still closed and there is nothing on screen to morph. That also buys
  "opens on the player" for free, in one line rather than two.

- **Collapsing from the usage screen settled at the wrong wing.** Paging
  changes only the *expanded* island: `NotchStore.paged(_:wings:)` takes the
  expanded size from the page and `compactExtraWidth` from the activity,
  always. Without it a collapse from usage settled at its 160pt wing and
  then jumped to the activity's — visible on `pausedTrack`, whose wing is 22.

### Changed

- **`isUsagePanelOpen: Bool` became `islandPage: IslandPage`.** Raw values
  −1 / 0 / +1 are positions on the axis rather than labels, so stepping and
  clamping fall out of the type instead of being rewritten at each call
  site. `.above` and `.below` return `self` at the ends: no wraparound, so a
  run of swipes settles rather than cycling.
- Content cross-fades on `.id(store.islandPage)` with `Motion.contentIn`
  while the shape morphs on `Motion.morph` — shape leads, content follows,
  as the rule requires.
- **2.4.0's §2.1 exception is withdrawn.** That release made swipe-up stop
  closing the island for everyone; paging restores the old behaviour on the
  toggle's off path, so the program is back to changing nothing by default.

### Known

With nothing playing, `.home` resolves to the idle agenda — so the top and
middle screens are the same view, and swiping up fires haptics without
visibly changing anything. Harmless, and it self-corrects the moment a track
loads. A two-position pager for the empty-player case is the fix if it reads
as broken.

### Not verified on hardware

The pager is unexercised on a real notch. By hand: swipe up and down
repeatedly and confirm the player is still there at the end; hold at each
end and confirm it stops rather than wrapping; collapse from the agent
screen and watch for growth before the close; mouse out and hover back and
confirm it returns on the player.

## [2.4.0] — 2026-09-23 (build 23)

### Added

- **The usage screen.** A two-finger swipe down on the island opens today's
  Claude Code and Codex figures in full: the vendor mark, tool name, model,
  a live context bar and the day's tokens. Swipe up to step back out.
  Opt-in: *New Features → Swipe down for agent usage*.

  It is a **mode**, resolved after onboarding and the palette and never in
  the activity ladder — the same shape onboarding and the lock screen
  already use. `NotchStore.isUsagePanelOpen` and `usageRows` drive it,
  `IslandLayout.usage(rows:)` sizes it (`Block.usageRow` 60, `Column.usage`
  280, at most 2 rows).

- **The live context window, newly read.** `AIUsageContext` pairs the last
  turn's token count with its model and resolves the window that model
  actually has — 200K, or 1M for a `[1m]` model. Anything unrecognised
  returns nil and **draws no bar rather than a bar against a guess**.

  `contextTokens` is the deliberate mirror of the daily total, and both are
  right because they answer different questions: cache reads are **in** the
  context figure (the window holds them) and **out** of the day's total
  (they measure context length, not work done); output tokens are the
  reverse — produced, but never seen by the model. `ClaudeUsageReader.parse`
  now returns the context alongside the total from the same pass, so the
  second figure costs no second read.

### Changed

- **A swipe up no longer closes the island** — it only changes what is
  shown. The pointer leaving is once again the sole thing that collapses it,
  as it was before the gesture existed.

  **This is a deliberate exception to §2.1's "nothing changes by default",
  and the only one in the program so far.** It is not gated behind a toggle
  because the old behaviour was not a preference but a conflict: the
  vertical axis meant two things at once, so one swipe both changed what was
  on screen *and* shut the screen it had just changed to. Paging between
  states was impossible and every gesture ended in the notch. A toggle would
  have preserved the ability to opt into a gesture that fights itself.

  Swipe down opens the usage screen once asked for, and otherwise restores a
  dismissed activity exactly as it did. The usage screen takes the gesture
  outright rather than sharing it — a binding that depends on whether
  something happens to be dismissed is one nobody can predict.

### Not verified on hardware

The usage screen and the context bar are unexercised on a real notch. The
AI badge itself was confirmed on hardware in 2.3.0.

## [2.3.0] — 2026-09-23 (build 22)

### Added

- **AI usage tracker.** Today's token count for Claude Code and Codex CLI,
  in a badge beside the notch. Opt-in: *New Features → AI usage tracker*.

  Claude Code is read from its own session transcripts —
  `~/.claude/projects/<escaped-cwd>/<session>.jsonl`, one append-only file
  per session — summing `message.usage` on every `assistant` line. The CLI
  and the VS Code extension are the same engine writing the same files, so
  one tree covers both and there is no extension fallback path. Append-only
  is what makes it cheap: each file's parsed byte offset is remembered, so a
  folder event re-reads only what was appended rather than re-parsing a 2MB
  session. Verified against a real 2,660-line transcript.

  Codex keeps no transcripts — it keeps SQLite at `~/.codex/state_5.sqlite`
  in WAL mode, with `tokens_used` on a `threads` table. Schema read off the
  real file (`codex-cli 0.154.0`), opened **read-only** and never written to.
  One honest imprecision is recorded in the source: `tokens_used` is a
  running per-thread total.

  **It gets its own window, not a slot in the island.** `IslandLayout`'s
  sizes are tight deltas from the measured cutout, so a permanent extra
  element in the wings would mean moving numbers that are already tuned.
  Nothing in it touches `NotchShape`, `IslandLayout` or the island's panel.
  Pinned at the island's own SkyLight level (100) — above ordinary windows,
  below the lock shield, so a token count never sits on a locked screen.
  With nothing playing the badge is up; while music owns the island it
  hides, and returns when the island is expanded, where there is room for
  both.

- **Global hotkeys that fire a command directly**, without opening the
  palette first. Bound in *Settings → Shortcuts*, alongside the single-key
  shortcuts 2.2.0 added.

- **Launch groups.** A user-named set of apps opened together from one
  palette command. Bundle identifiers are stored and resolved at launch
  time, so an app moving inside `/Applications` does not break the group;
  the display name is cached only so the Shortcuts tab can list a group
  without resolving anything. Entirely user-authored — no preloaded presets.
  A named group with no apps, or apps with no name, is not offered
  (`whileGroupConfigured`).

- **File commands on the shelf**: compress, expand, and convert an image to
  JPEG, acting on whatever the island is already holding.

### Changed

- `SystemCommands` split, with the file operations moving to
  `SystemCommands+Files.swift`.

### Not verified on hardware

Unexercised on a real notch, as with 2.1.0 and 2.2.0. The probes behind
these mechanisms are in `docs/RESEARCH.md` §6.4 — including the one that
matters most: a probe launched from a shell inherits the terminal's TCC
grant and will falsely report `AXIsProcessTrusted == true`. Launch it with
`open`.

## [2.2.0] — 2026-09-23 (build 21)

Closes the rest of Phase 6: the commands the palette was built to run, the
lyrics panel that had been written and wired to nothing since September, and
the documentation the phase owed.

### Added

- **Lyrics panel, revived.** `LyricsFetcher`, `TrackLyrics`, `LyricLine` and
  `LyricsPanelView` had been complete and unreachable — the audit found
  `LyricsFetcher` with exactly one reference, its own declaration. A button
  on the scrub row opens a column beside the player. New `LyricsService`
  fetches from LRCLIB **only while the panel is open**, so a track playing
  with it shut never makes a request. Opt-in: *New Features → Lyrics panel*.
- **Six more palette commands**, taking it to 24: Switch Audio Output
  (cycles; offered only with more than one output device), New Quick Note,
  Compress Shelf File, Expand Shelf File, Convert Shelf Image to JPEG, and
  Hide or Show the Island. The file commands act on whatever the island is
  already holding, which is what makes them mean anything from a palette
  with no file picker.
- **Single-key shortcuts in the palette, and a Shortcuts tab to set them.**
  ⌃⌥K, then one key. Rows 1–4 are always numbered and need no setting up;
  *Settings → Shortcuts* binds a letter to any of the 24 commands.
  **Keys fire only while the query is empty** — after the first letter every
  key types, which is what lets `d` run Dark Mode without costing you the
  ability to search for "downloads". The row badges are drawn from the same
  flag the key handler reads, so the island can never show a key that would
  not work. Assigning a taken letter steals it, a key bound to a command the
  palette has decided cannot act is unreachable, and junk in the stored
  dictionary is dropped rather than fatal.
- **Your name is a setting.** *Settings → General → Your name*. The daily
  greeting was hardcoded to one person; it now defaults to the first word of
  the account's full name and can be anything.

### Fixed

- **The greeting was half-hidden behind the camera housing.** The compact
  wing was a flat 160pt — 64 of it usable — while "Good afternoon, Apurva"
  measures 130.2pt, so a third of the sentence was drawn where there is no
  screen. Two fixes: every compact text label is now clamped to the wing, so
  nothing can cross the cutout again, and the wing is sized from its own
  label. "No Internet" was clipping by 5pt for the same reason.
- **`VolumeService` retained itself.** Both CoreAudio listener blocks put
  `[weak self]` on the inner `Task` rather than on the block CoreAudio holds,
  so the weak capture was decorative and the service kept itself alive.
- **`MarqueeText` polled at 20Hz, unbounded**, waiting for a `PreferenceKey`
  that may never arrive, and scrolled with `.repeatForever` regardless of
  Reduce Motion. Bounded to 2s, and it now honours the setting.
- A generic CoreAudio read handed a raw pointer to an unconstrained `T`.
  Constrained to `BitwiseCopyable`, which is what it always required.

### Changed

- `IslandLayout` split: the token vocabulary stays, the layouts move to
  `IslandLayout+Resolution.swift`.
- **The build is warning-free.** It was not before: four compiler warnings,
  three of which were the bugs above.

### Deliberately left out, each with a measured reason

- **Empty Trash.** `~/.Trash` is not listable without Full Disk Access —
  measured, nil contents. Same wall as the notification mirroring cut in
  September.
- **Night Shift.** `CBBlueLightClient` loads, but driving it needs a
  hand-declared ObjC interface for a headerless class to pass a `BOOL` — the
  brittle binding style this project already replaced once.
- **`screencapture -i`.** Works, but the Screen Recording prompt could land
  on Visor's name. Take Screenshot opens Apple's Screenshot.app instead,
  which owns its own permission; the shelf catches the result either way.
- **A palette row per audio device.** The command list is a static value;
  dynamic rows mean string identifiers and the end of the exhaustive switch
  that makes adding a command safe. Cycling covers the real case.

### Not verified on hardware

Everything in 2.1.0 and 2.2.0 is unexercised on a real notch. The probes are
recorded in `docs/RESEARCH.md` §6.4, including the one that matters most: a
probe launched from a shell inherits the terminal's TCC grant and will
falsely report `AXIsProcessTrusted == true`. Launch it with `open`.

## [2.1.0] — 2026-09-23 (build 20)

### Added
- **A command palette on ⌃⌥K.** 18 commands — transport (play/pause, next,
  previous), mute, keep-awake, lock screen, sleep display, toggle dark mode,
  toggle microphone, screenshot, copy/search the current track, open
  Downloads, 5- and 25-minute timers, settings, replay welcome, quit. Each
  declares its own availability (`always`, `whilePlaying`,
  `whileVolumeExists`, `whileMicrophoneExists`), so the list shows what can
  actually be run right now rather than greyed-out rows.

  The hotkey is `RegisterEventHotKey`, **not** a `CGEventTap`. A tap sees
  every keystroke on the machine and needs Accessibility — the permission
  the media-key HUD was cut to avoid. Carbon registers one combination with
  the window server and is handed only that one. Measured before the feature
  was written, on an ad-hoc-signed `LSUIElement` bundle launched through
  LaunchServices so it carried its own TCC identity rather than the
  terminal's: `AXIsProcessTrusted() == false`, `RegisterEventHotKey`
  returned `noErr`, and **no prompt appeared**.

  ⌃⌥ deliberately, avoiding ⌘ and ⇧ entirely: that is where app shortcuts
  live, and a palette that steals one is worse than no palette. The
  registration follows the *setting*, not the launch — turning the palette
  off hands the combination back to whatever else wanted it, driven by
  `UserDefaults.didChangeNotification` (an observer, not a poll).

- **Drop zones on the island.** The island splits into two drop targets:
  stash to the shelf, or AirDrop. `DropZone` is pure and unit-tested —
  getting the split backwards AirDrops somebody's file to whoever is nearby
  instead of putting it on the shelf, which is not a bug worth finding by
  trying it.

- **Hover slide and a close delay**, so the island does not snap shut the
  instant the cursor leaves an edge.

- **Greetings**, with their own compact wing and label layout
  (`CompactLabel`, `CompactWingTests`).

- **A New Features screen** listing what each addition does, which are
  recommended, and a toggle per feature — every new behaviour in this
  release is opt-in-visible rather than silently switched on.

### Changed
- **Every transient dwell time moved into one `Dwell` file.** Thirteen
  sleeps across nine services had drifted to ten different numbers for the
  same job — the same drift `IslandSpacing` exists to prevent, in the time
  dimension. One constant per site, named for the site, each holding
  *exactly* the value that service already used: this is a relocation, not
  a retune, and nothing changed on screen.
- `IslandLayout` split into `IslandLayout` + `IslandLayout+Resolution` —
  the file had grown past the point where the resolution rules were
  readable next to the geometry.
- Idle power pass across the services, plus settings for it.

### Removed
- Dead UI left over from the old-code port: the Lottie welcome JSON (the
  SF Symbols `.symbolEffect(.replace)` pair replaced it in 2.0), the
  unused equaliser and seek-bar views, `LiquidGlassBackground`,
  `NowPlayingArtworkBackground`, `AnimateImage`, `PlaybackSourceButton`,
  `SystemMute`, and the small `Support/extension+*` helpers. ~3,800 lines,
  no behaviour change.
- `COMMIT-PROMPTS.md`, `COMMITS.sh` and three superseded phase plan docs.

### Fixed
- **The volume island never appeared on anything but the built-in speakers.**
  `VolumeService` read `kAudioDevicePropertyVolumeScalar` on the device's
  *main element*, which only exists where the hardware has a master volume
  control. A Bluetooth soundbar, most USB DACs and HDMI have none, so the
  read returned nil, `store.volume` went nil and the feature deactivated
  itself — silently, because that path was written for devices with genuinely
  no volume. It now reads, writes and observes
  `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` (`'vmvc'`), the
  volume macOS itself moves.

  Measured on a JBL CINEMA SB510 before any app code changed, with four
  throwaway CoreAudio probes: main-element scalar **absent**; per-channel
  scalar present but unbalanced (0.38 / 0.37, so averaging the two channels
  would have drifted); `'vmvc'` present, settable, and firing on every system
  volume change including mute. On the built-in speakers `'vmvc'` returns
  exactly what the master scalar returned (0.70 both), so this is a
  replacement rather than a fallback — no branch, no device sniffing.

  Two things the probes corrected along the way: `SystemMute` was **not**
  affected (mute lives on the main element of both devices and always
  worked), and the documented "CoreAudio fires twice per change" is
  device-specific — the soundbar re-notifies per channel and fires 8–16
  times. The existing dedupe in `refresh()` already absorbed it.

  No UI, layout, motion or geometry changed.

## [2.0.1] — 2026-09-20 (build 19)

### Fixed
- **A width trim moved the island off the notch instead of shrinking it
  evenly.** `NotchGeometry.closedRect` subtracted `widthOffset` from the
  width but computed `x` as `left.maxX + closedWidthInset / 2`, which does
  not account for that offset at all — so every trim came off the **right
  edge only** and walked the island leftwards. Against a real stored trim of
  −13.65pt the island measured 170.35pt inside a 185pt cutout, with a 0.5pt
  gap on the left and 14.15pt on the right, sitting 6.8pt left of centre.
  `x` now derives from the cutout's own midpoint, so a trim is symmetric.

  This is what 2.0.0's "collapsed off-centre" fix was aiming at and missed:
  that pass corrected dead space *inside* the idle island (real, and kept),
  but the island itself was mis-placed for every layout — which is why the
  player looked wrong too. Diagnosed by instrumenting the running app rather
  than by reading: a standalone probe reported the cutout at midX 855.5 while
  the app was placing the island at 848.675, and the gap between those two
  numbers was the stored trim. Three plausible causes were measured and
  discarded first — a stale hosting-view origin during `setFrame` (a probe
  showed `display: true` does not draw synchronously), the collapse squash,
  and a non-symmetric canvas. `NotchTrimTests` now pins both the centring and
  the equal-gap property across six offsets.

- **The island opened twice, with two haptics, on a single hover.**
  Introduced in 2.0.0 by the hover-area fix. Tracking the island's own rect
  rather than `bounds` meant the area had to be rebuilt whenever the island
  resized — but replacing an `NSTrackingArea` makes AppKit re-evaluate the
  cursor against it and re-deliver `mouseEntered` under a stationary pointer,
  so opening the island re-triggered the open. Fixed at both ends: `expand()`
  returns early when already expanded, and `updateTrackingAreas` skips the
  rebuild when the rect has not actually changed. Verified by driving three
  scripted hover cycles and counting exactly three opens and three collapses.

### Left out, deliberately
- **A Mac-model picker for notch dimensions**, asked for again and measured
  again before answering. macOS reports the true cutout through
  `auxiliaryTopLeftArea` / `auxiliaryTopRightArea`; the geometry was right all
  along and a stored trim was corrupting it. A preset table would override
  measured truth and go stale every hardware generation. The ±16pt/±4pt
  sliders remain for per-machine taste, and now behave symmetrically.

## [2.0.0] — 2026-09-20 (build 18)

Major because three things an existing user relies on are gone or moved: the
lock-screen media panel, the shuffle/repeat/lyrics controls, and the calendar
inside the player. Nothing here is a silent change of behaviour — each removal
is listed below with the reason it was removed rather than fixed.

### Removed
- **The lock-screen media panel, entirely.** Eight files
  (`LockScreenPanelManager`, `LockScreenNowPlayingPanelView`,
  `LockScreenNowPlayingView`, `LockScreenWidgetSurface`,
  `LockScreenClockView` and the three style enums), their Settings section and
  their `UserDefaults` keys. **The padlock is untouched** — it is a separate
  window manager (`LockScreenNotchWindowManager`) and still appears above the
  shield, with its style picker and sounds.
- **Shuffle, repeat and the lyrics toggle.** They were MediaRemote commands
  the adapter cannot deliver for every player: YouTube Music in a browser
  reports no shuffle or repeat state and accepts neither command, so all three
  rendered as controls that silently did nothing. A dead control is worse than
  an absent one. `MusicSeekRow` is now the progress bar alone, and the lyrics
  plumbing (`hasLyrics`, `isShowingLyrics`, the second column, `LyricsFetcher`
  wiring) came out with it.
- **The calendar from the expanded player.** With a track loaded the island is
  the player; the agenda is what the *idle* island shows.

### Fixed
- **A single calendar event overlapped the seek bar.** Root cause, not the
  symptom: `IslandLayout.nowPlaying` budgeted only `Block.date`'s height for
  the corner box while `ExpandedMusicView.datePeek` also drew an `EventRow`
  under it. The layout and the view disagreed about the box's height, so the
  row spilled onto the scrub row below. Removing the calendar from the player
  removes the disagreement.
- **The idle island collapsed off-centre, pulling right-to-left.** *Not* a
  notch-calibration fault — measured with a standalone probe on a 15" M4 Air,
  every rect the geometry produces shares `midX = 855.5` exactly and the
  stored user trim was 0/0. The real cause: `IslandLayout.idle` sizes width
  from a fixed 240pt `Column.agenda` sized for the longest title that fits,
  while `ExpandedIdleView` pinned its content `.leading` — so a short title
  ("Gym: Chest-triceps") left the surplus as dead black pooled entirely on the
  right, and the collapse read as the island sliding sideways rather than
  closing into the notch. Content is now centred.
- **Expanding the idle island could make it _narrower_ than its own compact
  wing.** Found while measuring the above: an empty agenda resolved to 275pt
  against a 344pt wing, so opening it visibly shrank the island sideways. The
  same defect `musicExpandMargin` fixed for the player in 1.6.0; `idle` never
  got the floor. `IslandLayoutTests` now pins the invariant across both
  layouts and four content shapes.
- **The hover area reached far below the notch.** `NotchContentView.islandRect`
  fell back to `NotchGeometry.expandedSize` — the *tallest* layout any feature
  declares — whenever the island was not expanded, making the closed island's
  target a ~220pt block of screen that swallowed the cursor on the way past.
  Every state now measures its own resting size. The `NSTrackingArea` was
  `bounds` for the same reason and is now `islandRect`; `.inVisibleRect` is
  dropped with it, since that option re-pins the area to `bounds` and would
  undo the fix, so an observer rebuilds the area when the island resizes.

### Added
- **A paused track leaves a dot rather than vanishing.** After the 5s pause
  collapse, `.nowPlaying` now hands over to a new `.pausedTrack` activity —
  a 6pt dot tinted from the album — instead of deactivating outright. It
  resolves to the same expanded player card, so playback is always one hover
  away; previously a paused track disappeared with no way back to it short of
  switching to the player app. Ranked below every real activity in both
  ladders, so it can never displace one.

### Left out, deliberately
- **A Mac-model picker for notch dimensions.** Asked for, and measured before
  answering: macOS reports the real cutout through `auxiliaryTopLeftArea` /
  `auxiliaryTopRightArea`, and on the reference machine it is correct to the
  half-point. Presets would override measured truth with a table that goes
  stale on every new model. The existing ±16pt/±4pt trim sliders remain for
  per-machine taste.
- **Removing `toggleShuffle`/`cycleRepeat` from `NowPlayingCommands`.** The UI
  is gone; the service plumbing is harmless and removing it reaches further
  than the change required.

## [1.7.1] — 2026-09-20 (build 17)

### Fixed
- **The `.dmg` no longer carries a visible `.background.tiff`.** The volume now
  shows exactly two icons — `Visor.app` and the `Applications` alias — even
  with `AppleShowAllFiles = 1`. The art moved into the app bundle, at
  `Visor.app/Contents/Resources/dmg-background.tiff`, so it is not an entry in
  the install window at all rather than an entry that is merely hidden.

  This reverses the "Left out" note in 1.7.0, which claimed the art cannot
  live inside `Visor.app`. That conclusion was drawn from a real failure but
  blamed the wrong cause: the AppleScript reached the file as `file "x" of
  folder "Visor.app" of vol`, and Finder answers `-1728` there because it
  treats a `.app` as an application, not a folder. Addressed instead as
  `(POSIX file "…") as alias`, the assignment is accepted and a correct
  `icvp` record is written.

  Both candidate fixes were measured on scratch images before the build script
  changed:
  - **Deleting the art before detach: does not work.** The `icvp` record
    survives, but it stores the background as a Carbon *alias* to a real file
    on the volume. With the file gone the alias dangles and the window paints
    plain grey — confirmed by mounting the converted image and looking at it.
  - **Moving the art into the bundle: works.** Background, arrow and icon
    positions all render, with no extra entry on the volume.

  `chflags hidden` is no longer applied to the art, because there is no longer
  an art file on the volume to flag; `.DS_Store` is still flagged.

## [1.7.0] — 2026-09-20 (build 16)

### Added
- **The `.dmg` now opens onto a styled install window** instead of a bare
  file list: background art carrying the notch silhouette, the Visor
  wordmark and an arrow, with `Visor.app` on the left and the
  `/Applications` alias on the right for the arrow to point at. Toolbar and
  status bar hidden, icons at 128pt.

  The layout lives in the volume's `.DS_Store`, and Finder writes that only
  to a **mounted read-write** disk. `make-dmg.sh` therefore creates the image
  as UDRW, decorates it through Finder/AppleScript, `sync`s, detaches, and
  only then `hdiutil convert`s to the compressed UDZO image that ships.
  Creating UDZO directly — which is what the script did before — silently
  produces an unstyled window with no error to notice.

  The art is committed at `scripts/dmg/background.png` and `@2x`, so a
  release build needs neither Python nor Pillow.
  `scripts/dmg/make-background.py` regenerates it and is a development tool,
  not a build step.

### Changed
- **The disk image ships three entries and nothing else** —  `Visor.app`, the
  `Applications` alias, and one hidden `.background.tiff`.
  - `.fseventsd` is now deleted. It has to go **after** `diskutil rename` and
    immediately before the detach: macOS maintains that log for as long as the
    volume is mounted and writable, so an earlier delete is quietly undone,
    and the rename invalidates the mount path the delete was using.
  - The art moved from a `.background/` folder holding a 1x and a 2x PNG to a
    single multi-resolution `.background.tiff` built with `tiffutil
    -cathidpicheck` — one hidden entry in the window instead of a folder.
    `tiffutil` is part of macOS, so this adds no dependency.
  - Checked against real shipped images rather than guessed: Rectangle 0.87
    and IINA 1.3.5 both ship **no** `.fseventsd`; IINA uses a single
    `.background.tiff` and Rectangle keeps the folder.

### Fixed
- **The Finder layout pass could fail without failing the build.** `osascript`
  wrote to `/dev/null` and its exit status went unchecked, so an error part-way
  through produced a valid but completely unstyled `.dmg`. It now aborts the
  build. Hit for real while testing: `chflags` ran on `.DS_Store` while Finder
  was still writing it, and the entire layout — background, icon positions,
  window size — was lost. A settle and a `sync` now precede it.

### Left out
- `chflags hidden` as the *fix* for those entries. It is applied, but it does
  not do what it is usually claimed to: with `AppleShowAllFiles = 1` Finder
  lists flagged items anyway (verified both ways on this machine). The leading
  dot is what hides them under default settings, and nothing inside the image
  can hide them from someone who has asked to see hidden files. The only real
  reduction available was to ship fewer entries, which is what was done.
  `SetFile -a V`, the spelling most sources still suggest, is deprecated since
  Xcode 14 and fails silently.
- Moving the art inside `Visor.app` to reach zero extra entries. Finder reports
  the assignment as succeeding and then persists no `icvp` record at all, so
  the window loses its background entirely. Measured, not assumed.
  **Superseded in 1.7.1 — this conclusion was wrong.** The failure was in how
  the AppleScript addressed the file, not in Finder's handling of bundles.

### Note
- Build 14 is also in `new-releases/` and is **not** the release. It was cut
  from a `make-dmg.sh` whose AppleScript comment still contained backticks;
  in an unquoted heredoc the shell ran the word inside them as a command and
  printed `update: command not found`. The image it produced is sound — the
  stray substitution touched nothing — but the shipping artifact should come
  from the corrected script, so 15 supersedes it. Build 15 in turn predates
  the volume cleanup above and is superseded by 16. All three stay on disk
  because releases are never deleted.

### Left out
- `create-dmg` and the other packaging helpers: ~20 lines of `hdiutil` and
  AppleScript do the whole job, and CLAUDE.md's no-new-dependency rule covers
  tooling too.
- A custom volume icon. It needs `SetFile`/`Rez` from the full Xcode command
  line tools and only changes the mounted disk's icon in the sidebar, which
  is not where anyone looks during an install.

## [1.6.1] — 2026-09-20 (build 13)

### Fixed
- **The lock-screen media panel never appeared.** Two faults in the SkyLight
  pin, not in the panel. The lock windows pinned at absolute levels 301/302,
  but the lock shield and its companions occupy the band just above 300, so
  both windows sat underneath them — the reference uses 400/401. And the
  spaces were created lazily on the first pin, which happens while the shield
  is already up; a space created at that moment does not reliably become
  visible. `SkyLightPin.prepare()` now builds every space at launch.
- The media panel never received key status, so SwiftUI drew its transport
  controls in their inactive state. It now forces key, as the reference's
  own overlay window does.
- `DeviceBatteryGlyph` returned the generic antenna glyph for headsets.

### Added
- **Restore original settings**, in Settings › About. Clears every stored
  preference back to how it shipped. It removes the keys rather than writing
  a table of defaults back, so each accessor stays the single source of its
  own default. Onboarding and greeting state are not settings and are left
  alone; neither is launch-at-login, which is a macOS login item.
- A drawn battery indicator on the low/full alert, ported from the
  reference. The pulse is bounded to a repeat count rather than
  `.repeatForever` — an endless animation keeps the view graph running, the
  same fault the power pass found in `PlaybackBars`. The bar is sized to the
  real percentage. Reduce Motion skips the pulse.
- Speaker and headphone glyphs for connected accessories. Headphone words
  are matched before speaker brands, since JBL and Sonos both sell
  headphones.

### Changed
- Unlocking now reads as one handoff: the padlock dissolves through
  `Materialize` while the island's music wing resolves in. The two live in
  different windows and cannot cross-fade, so they are sequenced instead.
  This required animating on the activity kind — swapping which branch of the
  compact wing is built is an identity change, and without a transaction the
  transitions were inert.
- Accessory battery peek 2.5s → 4s. Too quick to read a device name and a
  figure.
- `ActivityKind` is now `Equatable`.

### Not included
- **Apple Clock timer mirroring.** It needs a `log stream` subprocess,
  scraping of the private `com.apple.mobiletimerd.plist`, Accessibility
  permission with menu-bar traversal, and a 1s poll. The poll alone is ruled
  out by the power rules. Visor's own `TimerService` is unaffected.

## [1.6.0] — 2026-09-19 (build 12)

### Added
- Insets so the expanded panel stops reading edge-to-edge: the artwork's halo
  and the date's digits sit at the extremes, so the eye measures from the
  glow rather than the frame.

### Changed
- With a track loaded — playing or paused — the island is the player and
  nothing else. The calendar column beside it was removed; the agenda is what
  the idle island shows.
- A pause collapses the island to the bare notch after 5s. The delay is the
  point: a pause is usually a step on the way to a skip or a seek, and an
  island that shuts instantly flaps around every one of them. The track is
  not cleared, so opening the island by hand still finds a transport row.

## [1.5.1] — 2026-09-19 (build 11)

### Fixed
- The padlock did not appear while locked. The island's own panel is pinned
  below the lock shield by design, so it is invisible there; the padlock
  needed a window of its own above the shield.
- The lock widget lingered about a second after unlock, because its gate
  included the unlock settle.
- The expanded player was narrower than the compact wing it opened from, so
  expanding shrank the island sideways.

## [1.5.0] — 2026-09-19 (build 10)

### Added
- Lock screen: a media panel and a latching padlock above the shield.
- The reference's player components — seek bar, marquee, control buttons.
- Progress tint styles and an optional decorative equaliser.
- Downloads, AirDrop, screen recording, Bluetooth, Focus and VPN activities.
- Notch customization: outline, width and height trims, fullscreen hiding,
  display selection.
- Capsule mode for screens with no cutout.
- Swipe up to dismiss, down to restore.

## [1.4.0] — 2026-09-19 (build 5)

### Added
- Three-step welcome flow, living inside the panel as a mode orthogonal to
  the activity ladder.
- Player upgrades: seek bar, shuffle and repeat, and a lyrics panel that
  fetches only while open.
- Settings sections.

### Changed
- Relicensed to GPL-3.0, so GPL-licensed reference code can be ported in.

## [1.3.0] — 2026-09-19 (build 4)

### Added
- Animation strokes, colour dimming, and an easter egg.
- Vinyl mode, play/pause morphs, artwork tilt with the cursor, progress.
- Screenshot drag and drop, with a primary colour tint.
