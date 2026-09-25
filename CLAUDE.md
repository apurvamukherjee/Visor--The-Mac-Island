# Visor

Native macOS Dynamic Island–style app for the MacBook notch.
Priorities, in order: feels like iOS → near-zero idle power → clean, small codebase.
Design record: this file. The 2.x design doc (RESEARCH.md) is archived in `backup/docs/`.
License: GPL-3.0 (see `LICENSE`, added 2026-09-19 so GPL-licensed reference code can be ported in — see Progress).

## Stack
- **Since 3.0.0 the app is , ported file for file** into `Visor/`
  (source: `backup/-upstream/`, identical to upstream `main` on
  2026-09-24). Changes to it: branding (Visor / "By Apurva"), the Now
  Playing transport (Visor's MediaRemoteAdapter), removing Sparkle, and
  Visor's own additions. Every added line is marked `// Visor:`, and new
  files live beside upstream's: vinyl mode (`components/Music/VinylDisc.swift`,
  from 2.x) and the lock/unlock padlock (`Live activities/LockLiveActivity.swift`
  + a `.lock` activity + the lock handlers in `App.swift`).
  Every `Boring*` name (files, types, `.boringShelf`, `boring.m4a`) is renamed
  to `Visor*`, unmarked; everything else stays byte-for-byte.
- Swift 5 language mode (the ported code is not Swift 6 clean)
- macOS 14.0 minimum, Apple silicon
- XcodeGen: edit project.yml, never edit .pbxproj; run `xcodegen generate` after changes
- Approved packages (2026-09-25): MediaRemoteAdapter, Defaults,
  KeyboardShortcuts, MacroVisionKit, each pinned exactly. No others without
  approval. Lottie, AsyncXPCConnection and LaunchAtLogin-Modern were removed
  in 3.1.2; SkyLightWindow's one used class is vendored (MIT) as
  `private/SkyLightOperator.swift`. It lifts the notch above the lock screen. **Sparkle is excluded**: its
  feed was TheBoredTeam's appcast.
- App Sandbox off (spawns the media adapter); LSUIElement = YES
- Unused code is deleted, not excluded: the five never-compiled upstream
  files were removed after 3.1.1, so `project.yml` has no excludes.

## Commands
- Generate: `xcodegen generate`
- Build: `xcodebuild -scheme Visor -configuration Debug build | xcbeautify`
- Test: none since 3.0.0 (VisorTests covered the replaced code and was removed)
- Format: `swiftformat .`   Lint: `swiftlint`. Both exclude `Visor/` and
  `VisorXPCHelper/` (ported verbatim, so reformatting would defeat the copy)
- Release: `bash scripts/make-dmg.sh`
- Run build, format and lint before saying a task is done.

## Releases
- **Semantic versioning, always.** `MARKETING_VERSION` is `MAJOR.MINOR.PATCH`:
  MAJOR changes how the island behaves for someone already using it, MINOR
  adds a feature, PATCH fixes without adding one. `make-dmg.sh` *rejects* a
  version that is not three numbers, so the convention cannot lapse quietly.
- Every release build goes in `new-releases/` as a new `.dmg`, committed,
  named `Visor-<version>-build<n>-<date>-<time>-<commit>.dmg`.
- **Never delete or overwrite an old build.** They are permanent history:
  `make-dmg.sh` refuses to overwrite a release already on disk, and the
  folder is meant to accumulate. Removing one is a regression, not tidying.
  (Builds up to 1.6.0 used an older `Visor-1.6(12)-…` name and were renamed
  in place with `git mv` when this convention was adopted — bytes and history
  unchanged. That was a rename, not a deletion.)
- Bump `MARKETING_VERSION` *and* `CURRENT_PROJECT_VERSION` in project.yml
  before building, so each DMG gets its own name — the hash in the filename
  is `HEAD` *at build time*, so commit first.
- Record every release in `CHANGELOG.md`: Added / Changed / Fixed, plus
  anything deliberately left out and why.
- **GitHub release** (from 3.1.0): annotated tag `vX.Y.Z` on the commit the
  DMG was built from (the hash in its name), pushed through `gh`'s
  credential; `gh release create --verify-tag --latest` with the DMG under
  its full build name. Notes: what's new, plus the `xattr -dr
  com.apple.quarantine` step, since builds are ad-hoc signed.
- **Every `.dmg` ships the styled install window** — background art with the
  drag arrow, both icons placed, no toolbar or status bar. `make-dmg.sh`
  builds read-write, decorates via Finder/AppleScript, then converts to
  compressed read-only; skipping the read-write step silently loses the
  layout. The art is committed at `scripts/dmg/background{,@2x}.png`; a
  release build never regenerates it. Change the art only by editing
  `scripts/dmg/make-background.py` and re-running it (Pillow, dev-only —
  never a build dependency). Icon positions in the AppleScript and the arrow
  endpoints in the script must move together, or the arrow stops pointing at
  anything.
- **The volume ships exactly two visible entries**: `Visor.app` and the
  `Applications` alias (plus `.DS_Store`). The background art lives **inside
  the bundle** at `Visor.app/Contents/Resources/dmg-background.tiff`, so
  nothing extra shows even with `AppleShowAllFiles=1` — `chflags hidden` does
  not hide a root-level dotfile from that setting (verified). Assign it with
  `(POSIX file "…") as alias`; `file "x" of folder "Visor.app" of vol` fails
  -1728 because Finder treats a `.app` as an application, not a folder. The
  art cannot instead be *deleted* before detach: `.DS_Store` stores it as a
  Carbon alias, so the record survives, dangles, and the window paints plain
  grey (measured). `.fseventsd` is deleted **after the rename, immediately
  before detach** — macOS maintains it while the volume is mounted, so an
  earlier delete silently comes back. The art is one multi-resolution `.tiff`
  (`tiffutil -cathidpicheck`), not a `.background/` folder of 1x+2x PNGs.
- **Never let the Finder pass fail silently.** `osascript` must abort the
  build on error, and `.DS_Store` needs a settle before `chflags`/`sync` —
  flagging it while Finder is still writing loses the whole layout, and the
  image still builds, just unstyled.

## Architecture (3.0.0+)
- Upstream  structure: `VisorViewModel` + `VisorViewCoordinator`,
  singleton managers (`MusicManager`, `BatteryActivityManager`, ...),
  settings in `Defaults` keys (`models/Constants.swift`).
- Media: `MusicManager` -> `MediaControllerProtocol`. `NowPlayingController`
  wraps Visor's `MediaRemoteAdapter.MediaController`, which is what makes
  browser players (YouTube Music in Chrome/Safari) appear. Don't swap it back
  to a bundled `mediaremote-adapter.pl`: that script was never bundled, and
  its absence was the "doesn't hear YouTube Music" bug.
- Permissions: the upstream onboarding flow (explain first, then request);
  Accessibility goes through `XPCHelperClient` -> the XPC service
  `com.apurvamukherjee.visor.VisorXPCHelper` (target `VisorXPCHelper`,
  upstream's helper copied verbatim, unsandboxed, embedded in
  `Contents/XPCServices`). It also handles screen and keyboard brightness.
- Branding: user-visible text says only Visor / "By Apurva"; links go to
  github.com/apurvamukherjee/Visor--The-Mac-Island. Keep upstream's GPL
  copyright headers in source files.
- The 2.x rules (NotchStore, Motion tokens, card stack, power rules) are
  retired with the code they governed. They live in git history before
  `8b05dad` and in `backup/docs/RESEARCH.md`.

## Code quality
- Small files, small views, clear names. No god objects.
- No force unwraps, no `try!`, no print(); use os.Logger with a subsystem.
- No commented-out code, no TODOs without an issue reference, no placeholder "example" code left behind.
- Comments explain *why*, not *what*.
- Visor is GPL-3.0 (see `LICENSE`); since 3.0.0 it is a  derivative, so code copies verbatim and keeps its copyright headers.
- If something is uncertain (private API behavior, macOS version quirks), say so and verify instead of guessing.

## Workflow
- Plan before coding; wait for approval on plans. Don't code until ~98% confident — ask, don't guess.
- One feature at a time; don't start the next until the current one is committed.
- Commit after every task, authored as the user (`Apurva Mukherjee
  <apurvan.337@gmail.com>`, GitHub `apurvamukherjee`) from their terminal's
  git config, with a descriptive conventional message and no co-author
  trailer. Push only when the user asks, to `origin` as `apurvamukherjee`.
  (Changed 2026-09-24 at the user's request.)
- Keep MD files lean (this file <200 lines): decisions/architecture/stack/conventions/guidelines/progress only, no verbose prose. Full README treatment only on explicit "update read me".
- Run only necessary shell commands — avoid exploratory bloat.
- When done, report: what changed, how you verified it, what I should test by hand, and any open questions.

## Progress
The 2.x log (phases 1-6, every pass after them) is archived locally in
`backup/CLAUDE-2.x-progress.md`, and its code and docs are in git history
before `8b05dad`.

- **3.0.0 "new island" (2026-09-24):** the app was replaced with
  , copied file for file (user's call: "override everything",
  keep the name Visor, "By Apurva", and the media integration). The 2.x
  features it lacks were dropped on purpose: lock-screen player, palette,
  launch groups, AI usage badge, timer, card stack, lyrics, and the
  Bluetooth/VPN/Focus alerts. Swap (`8b05dad`), media fix (`e5b1c17`),
  branding (`dd4d611`), XPC helper target (`2e4014d`; the user copied it in
  after the auto-mode check blocked Claude from doing so). Released as
  `Visor-3.0.0-build34-…-2e4014d.dmg`. **Not seen on hardware.**
- **3.1.0 (2026-09-24, build 35):** vinyl mode
  (`5197ab1`), lock/unlock padlock (`76b603e`), menu bar icon changed to
  `opticaldisc.fill` with the menu reading Settings / By Apurva / Restart /
  Quit (`f6a6d3f`, `1b2cf96`). Builds; **not seen on hardware**. Riskiest:
  whether the notch shows on the lock screen with "Show notch on lock
  screen" off.
- **Repo cleanup (2026-09-24):** local-only `backup/` (git-ignored) now
  holds `old-code/`, `-upstream/` (was `old-code-v1/`), the 2.x
  docs, `smoothness/`, the 2.x README and this file's old progress log. The
  README was rewritten for 3.0.
- **3.1.1 (2026-09-25, build 36):** Boring* names renamed to Visor*
  (`fca9014`), then an audit pass: DMG signature fix, arm64-only stripped
  Release, idle-power fixes (leaked timers, root-view observers, slider
  timeline) and the Apple Music favourite fix; see CHANGELOG.
- **3.1.2 (2026-09-25, build 37):** dead-code cleanup (~3,100 Swift lines,
  Lottie/AsyncXPCConnection/LaunchAtLogin dropped), the HUD-drag fix and the
  browser album-cover fix (re-fetch while the cover is missing or stale).
  Smoke-tested: launches, XPC helper connects, no errors logged.
- **After 3.1.2:** SkyLightWindow vendored (symbols verified on macOS 26.7;
  lock screen not yet seen on hardware).
- **Second dead-code pass (2026-09-25, unreleased):** 32 commits after
  `c0d3389`, ~340 Swift lines, no visible change; what was kept and why
  is in CHANGELOG [Unreleased].
- **Next:** the user tests 3.1.2 on hardware. After the release, Claude
  rewrites history to drop the old Co-Authored-By trailers (plan in
  memory) and the user force-pushes.
