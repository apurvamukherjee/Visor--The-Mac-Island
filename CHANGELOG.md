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
