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
