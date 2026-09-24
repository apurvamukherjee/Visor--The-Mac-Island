<div align="center">

# Visor

[![by Apurva](https://img.shields.io/badge/by-APURVA-e11d48?style=for-the-badge&labelColor=1a1a1a)](https://github.com/apurvamukherjee)

### The MacBook notch, turned into a Dynamic Island.

[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-black?style=flat-square)](https://www.apple.com/macos/)
[![Release](https://img.shields.io/badge/release-3.1.0-blue?style=flat-square)](CHANGELOG.md)
[![License](https://img.shields.io/badge/license-GPL--3.0-lightgrey?style=flat-square)](LICENSE)

</div>

## What it does

Hover the notch and it opens into a music player, your calendar, a file
shelf and more. Move away and it closes back into the camera housing.

- **Now playing** from any app that reports to macOS, including YouTube Music
  in Chrome or Safari, as well as Apple Music and Spotify. Artwork, scrubbing,
  shuffle and repeat.
- **Vinyl mode:** a spinning record in place of the cover, with a tonearm
  that drops on play.
- **Lock and unlock:** a padlock in the notch for a few seconds each time,
  then back to the album cover.
- **HUDs** for volume, brightness and keyboard backlight.
- **Live activities** for charging and downloads.
- **Shelf:** drop files on the notch to keep them close; share them from there.
- **Calendar and reminders**, and a **mirror** from the camera.
- A **welcome tour** that explains each permission before asking for it.

## Requirements

- Apple silicon, macOS 14 or later
- A MacBook with a notch (other screens get a floating island)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`

## Download

Disk images live in [`new-releases/`](new-releases), named
`Visor-<version>-build<n>-<date>-<time>-<commit>.dmg`. Take the highest
build, open it, and drag Visor onto Applications. Old builds are never
deleted; [`CHANGELOG.md`](CHANGELOG.md) says what changed in each.

Builds are ad-hoc signed, so on a Mac other than the one that built it, run
this once after installing:

```bash
xattr -dr com.apple.quarantine /Applications/Visor.app
```

## Build

```bash
xcodegen generate
xcodebuild -scheme Visor -configuration Debug build
```

Package a `.dmg`:

```bash
bash scripts/make-dmg.sh
```

## License

GPL-3.0, see [`LICENSE`](LICENSE).
