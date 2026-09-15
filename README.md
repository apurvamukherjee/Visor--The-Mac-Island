<div align="center">

# Visor

### The MacBook notch, turned into a Dynamic Island.

**Built in 26 hours.**

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black?style=flat-square)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift%206-strict%20concurrency-orange?style=flat-square)](https://swift.org)
[![CPU](https://img.shields.io/badge/idle%20CPU-0.0%25-brightgreen?style=flat-square)](#power)
[![Dependencies](https://img.shields.io/badge/dependencies-1-blue?style=flat-square)](#built-with)
[![License](https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square)](LICENSE)

<br />

*The black bar above your screen stops being dead space.*

Hover it and it grows into your music and your day. Move away and it disappears back into the hardware cutout — invisible, and costing nothing.

<br />

<img src="docs/screenshots/expanded.png" width="100%" alt="Visor expanded: album art with a colour halo, title, artist, transport controls, and the day's next event beside a large date block" />

</div>

<br />

---

<br />

<div align="center">

## It lives in the notch

</div>

Not hovering? It sits *inside* the cutout itself — album art, live playback bars, battery. The real notch and the drawn shape are the same black.

<div align="center">
<img src="docs/screenshots/compact.png" width="82%" alt="Visor compact: album art and bouncing playback bars on the left wing, battery percentage on the right" />
</div>

<br />

<table>
<tr>
<td width="50%" valign="top">

### Your day, at a glance

Nothing playing? The island becomes your agenda. Events are colour-matched to the calendar they came from, sorted soonest-first, with an overflow count for the rest.

An event stays listed until it has actually *ended* — something in progress right now doesn't vanish on you halfway through.

</td>
<td width="50%" valign="top">

<img src="docs/screenshots/agenda.png" width="100%" alt="Visor idle: a large WED 16 date block beside three colour-coded calendar events and an '8 more events' overflow row" />

</td>
</tr>
</table>

<br />

<table>
<tr>
<td width="50%" valign="top">

<img src="docs/screenshots/vinyl.png" width="100%" alt="Visor in vinyl mode: a turning record with grooves, a centre label showing the album art, and an S-shaped tonearm lowered onto the lead-in groove" />

</td>
<td width="50%" valign="top">

### Vinyl mode

A record that actually turns, with the album art as its centre label. The tonearm is built the way a real one is — a counterweight behind the pivot, an S-curved tube, and a headshell canted at the 22° offset angle that puts a cartridge tangent to the groove.

It lowers into the lead-in groove when you press play and lifts to its rest when you pause. That's the whole play/pause tell: a still frame of a record can't say whether it's spinning.

A toggle in Settings, off by default — the cover is the honest representation of what's playing.

</td>
</tr>
</table>

<br />

<div align="center">

## Catch a screenshot

</div>

Take a screenshot anywhere on the system and it slides into the notch and waits a minute. Drag it straight into Slack or Figma, click to open it, or flick it away with the ✕. Drag an image *onto* the notch and it opens to take it.

<div align="center">
<img src="docs/screenshots/screenshot-catch.png" width="100%" alt="A caught screenshot waiting in the notch as a draggable thumbnail labelled 'Drag it out, or click to open'" />
</div>

<br />

---

<br />

## What it does

|  | |
| --- | --- |
| **Now Playing** | Artwork, title, artist and transport for whatever's playing, in any app. The cover flips like a card when the track changes. |
| **Your day** | The next events from your calendars, colour-matched to their source calendar. |
| **Screenshot catcher** | Every screenshot lands in the notch for a minute, ready to drag anywhere. |
| **Battery** | Percentage in the wing, and a bolt that bounces the moment you plug in. |
| **Playback bars** | Four capsules bouncing in staggered phase, stopping dead when the music pauses. They take the album's colour, the way the iPhone tints its waveform — and stay white when the cover has no colour worth borrowing. |
| **Album halo** | A soft bloom of the cover's own colour behind the artwork, radial-masked so it never becomes a visible rectangle. The island's surface stays pure black. |

<br />

## How it feels

One black shape morphs between closed, compact and expanded. Never a cross-fade between two views — the shape leads, and the content follows it in.

Every animation comes from one small set of motion tokens, so nothing in the app can invent its own timing. Reduce Motion is honoured everywhere, including mid-track: the card flip becomes a crossfade, the record stops turning, the bars go still.

The island is welded to the notch. Swipe between desktops and the desktops slide *underneath* it, the way the menu bar does — it doesn't ride along with the wallpaper.

<br />

## Power

<div align="center">

### 0.0% CPU while playing

**Not a target — a measurement**, taken with `sample` against a real track.

</div>

<br />

The rules that get it there:

- **Event-driven only.** No polling loops, no global mouse monitors.
- **Nothing animates or ticks** when it isn't visible, isn't playing, or the display is asleep.
- **Never animate a layout property in a loop.** The playback bars are `CALayer` + `CABasicAnimation`, handed to the render server once and costing the main thread nothing. The SwiftUI version of the same four bars cost 5% CPU, because animating `frame(height:)` re-ran the view graph every frame.
- **Observe, don't re-check.** A loop that sleeps to ask "has it changed yet" is a poll no matter how long the sleep.
- **Accessibility settings are cached, not queried.** Reading Reduce Motion is a round-trip to the accessibility server, so it never happens from a view body.
- **Artwork is decoded once per track** and downsampled with ImageIO.
- **The store compares before it writes,** so the adapter's constant position updates re-render nothing.
- **Cursor parallax only re-renders** when the album card is actually on screen, and only once the cursor has moved far enough to see it.

<br />

## Gestures

| Gesture | Does |
| --- | --- |
| Hover the notch | Expand |
| Two-finger swipe | Previous / next track |
| Double-click | Play / pause *(on the island's surface — buttons keep their own clicks)* |
| Right-click | Settings |
| Drag an image onto it | The notch opens and takes it |
| Drag the thumbnail out | Drops the screenshot into any app |

<br />

## Requirements

- A MacBook with a notch, on Apple silicon
- macOS 14 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

<br />

## Download

Built disk images live in [`new-releases/`](new-releases), newest at the bottom. Grab the latest `.dmg`, open it, and drag Visor to Applications.

Builds are ad-hoc signed, so macOS quarantines a downloaded image. After copying it across:

```bash
xattr -dr com.apple.quarantine /Applications/Visor.app
```

<br />

## Build

```bash
xcodegen generate
xcodebuild -scheme Visor -configuration Debug build
```

Or package a local `.dmg`:

```bash
./scripts/make-dmg.sh
```

Drag it to `/Applications` and launch. Visor lives entirely in the notch — no Dock icon, no menu bar item, nothing to close.

> [!NOTE]
> Calendar permissions are bound to the app's code signature. Add an Apple ID in **Xcode → Settings → Accounts** (the free tier is enough) and set `DEVELOPMENT_TEAM` in `project.yml`, or macOS will forget the grant on every rebuild.

<br />

## Built with

Swift 6 with strict concurrency. SwiftUI for every view, AppKit confined to the window layer. No third-party dependencies beyond the Now Playing adapter.

Architecture is one store, one shape, and a service per feature — a feature never imports another feature. The full design record, including every decision that was tried and reversed, lives in [`docs/RESEARCH.md`](docs/RESEARCH.md).

<br />

---

<div align="center">

**by Apurva**

</div>
