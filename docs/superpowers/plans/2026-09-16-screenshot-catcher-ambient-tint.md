# Visor Phase 4 — Screenshot Catcher + Ambient Tint

> **Git:** NEVER commit. Stage nothing automatically. Stop at the end of each task and wait for review.

**Goal:** Two additions. (1) A screenshot taken anywhere on the system slides into the notch as a draggable thumbnail, then clears itself. (2) The playback bars take the current album's colour, the way the iPhone's Dynamic Island tints its waveform.

**Architecture:** `ScreenshotService: NotchService` watches the user's screenshot folder with a `DispatchSource` file-system source — no polling, no timer. New files that are images become a `ScreenshotCatch` (url + thumbnail) pushed into `NotchStore`, which surfaces as a third `ActivityKind`. The tint reuses the artwork decode already happening in `ArtworkCache`: one extra 32×32 thumbnail pass per track yields a colour cached against `trackIdentity`, applied to the `PlaybackBars` layers. **The island surface stays pure black** — iOS tints the waveform, never the Island itself, which is also the rule this project has already reverted two features to protect.

**Non-goals:** screen recordings (`.mov`), clipboard-only screenshots (no file is written — nothing to catch), a persistent file shelf, editing/annotation, any tint of the island *surface* (background washes, materials, blurred bleeds — all previously tried and reverted).

## Global constraints

Same as every phase — see CLAUDE.md. The ones this plan leans on hardest:

- Event-driven only. No polling loops. Nothing ticks when idle.
- Never animate a layout property in a loop (RESEARCH §5.1b).
- All animation from `Motion` tokens, wrapped in `Motion.resolved(_:)`.
- Nothing may paint outside the silhouette; closed state stays hardware-invisible.
- A feature never imports another feature; composition lives in `UI/`.
- Unit-test pure logic only.
- Build + test + `swiftformat .` + `swiftlint` before any task is done.

## Verified facts (checked 2026-09-16 — do not re-derive)

| Fact | How it was verified |
| --- | --- |
| `DispatchSource.makeFileSystemObjectSource(eventMask: .write)` on a directory fd fires on file creation, immediately, with zero idle cost | Ran a watcher against a temp dir; 2 events on one file create |
| Screenshot folder is `defaults read com.apple.screencapture location`, and is **not** always `~/Desktop` | Returned `/Users/apurvamukherjee/Pictures/Screenshots` on this machine |
| `CGImage` crosses an actor boundary under Swift 6 strict concurrency complete — no `@unchecked Sendable` box needed | `swiftc -swift-version 6 -strict-concurrency=complete -typecheck` of a detached decode → `@MainActor` sink: clean |
| `.draggable(url)` compiles for `URL`; `url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image)` is the image test | Same typecheck, clean |
| iOS tints the Dynamic Island's **waveform**, not its surface — the Island stays black | Design research; matches this project's existing pure-black rule |
| OKLab + k-means + chroma floor 0.045 + lightness lift 0.78 behaves correctly on real covers | Prototyped in Python against two covers pulled from live screenshots: B&W cover → nil (chroma 0.017), colour cover → rgb(211,171,177) at **10.2:1** contrast on black |

**Unverified, and cannot be from here:** whether `.draggable` initiates a drag session from a `.nonactivatingPanel` whose `canBecomeKey` is `false`. Synthetic mouse events need Accessibility (`AXIsProcessTrusted` is false). Task 6 resolves this with a real drag; the fallback is in Risks.

---

### Task 1: Screenshot location + new-file filter (pure logic)

**Files:** new `Visor/Features/Screenshot/ScreenshotLocation.swift`, new `Visor/Features/Screenshot/ScreenshotFilter.swift`, new `VisorTests/ScreenshotFilterTests.swift`

- `ScreenshotLocation.current() -> URL` — reads `UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")`, expands `~`, strips a trailing slash, falls back to `~/Desktop`. Returns a URL even if the path does not exist; the service handles that.
- `ScreenshotFilter.newest(in:after:) -> URL?` — pure over an injected `[(url: URL, modified: Date, isImage: Bool)]`. Keeps entries where `isImage`, `modified > after`, and the name does not start with `.`; returns the most recently modified.
- Never match on the filename prefix ("Screenshot") — it is localized.

**Verify:** tests for empty input, all-older input, a non-image newer file, a dotfile, and two candidates where the newer wins.

### Task 2: ScreenshotService

**Files:** new `Visor/Features/Screenshot/ScreenshotCatch.swift`, new `Visor/Features/Screenshot/ScreenshotService.swift`

- `struct ScreenshotCatch: Equatable, Sendable { let url: URL; let thumbnail: CGImage?; let caughtAt: Date }` — `Equatable` on `url` + `caughtAt` only.
- `start()`: resolve the folder, `open(path, O_EVTONLY)`, build the source with `.write` on `.main`, set `lastSeen = .now` so pre-existing files are never caught, `resume()`.
- Event handler debounces **150ms** (one `Task`, cancelled and restarted per event) — macOS writes then renames, producing a burst.
- After the debounce: enumerate with `contentModificationDateKey` + `contentTypeKey`, hand to `ScreenshotFilter`, skip if the url equals the current catch.
- Thumbnail decode on a detached task (`kCGImageSourceThumbnailMaxPixelSize: 256`, `CreateThumbnailFromImageAlways`, `WithTransform`), then hop to `@MainActor` to write the store. Verified safe above.
- `stop()`: cancel the debounce task and the dismiss task, `source.cancel()`, close the fd in the cancel handler, clear the store.
- Failure paths log via `Log.screenshot` (new category) and no-op: missing folder, unreadable folder (TCC denial), undecodable file.

**Verify:** run the app, `screencapture -x` into the folder, confirm one log line and one store write. Idle `sample` shows no wakeups.

### Task 3: Store + activity wiring

**Files:** `Visor/Core/Activity.swift`, `Visor/Core/NotchStore.swift`, `VisorTests/ActivityTests.swift`

- `ActivityKind` gains `.screenshot`.
- `resolveCurrentActivity` becomes `activities[.screenshot] ?? activities[.charging] ?? activities[.nowPlaying]` — user-initiated beats system-initiated beats ambient.
- Store: `private(set) var screenshot: ScreenshotCatch?` + `setScreenshot(_:)` which also activates/deactivates `.screenshot`, keeping the flag and the payload in step (same reason `setNowPlaying` still exists).

**Verify:** tests for the three-way precedence and for the catch clearing back to `nowPlaying`.

### Task 4: Compact chip

**Files:** new `Visor/UI/ScreenshotChip.swift`, `Visor/UI/CompactActivityView.swift`, `Visor/Core/Motion.swift`

- Chip: 20pt tall, 4:3 max, `RoundedRectangle(cornerRadius: 4)`, plus a `0.5pt white.opacity(0.25)` stroke so a white screenshot does not vanish against black.
- Leading wing shows the chip when a catch exists, otherwise album art. Battery keeps the trailing wing.
- `Motion.catchIn` — one new token, a spring with modest bounce. Content follows the shape, per the standing rule.

**Verify:** screenshot while music plays → chip replaces art, battery unmoved; screen-recording frame check that the island width never changes (the chip must not resize the compact state).

### Task 5: Expanded preview

**Files:** `Visor/UI/ScreenshotChip.swift`, `Visor/UI/NotchRootView.swift`, possibly new `Visor/UI/ExpandedScreenshotView.swift`

- Hovering a live catch shows a larger preview (~72pt tall) with the filename and a one-line hint.
- Sits in the music column's place when both exist; the agenda column is untouched.

**Verify:** hover during a live catch; confirm the housing clearance still holds and nothing overflows the shape.

### Task 6: Drag out and open

**Files:** `Visor/UI/ScreenshotChip.swift`

- `.draggable(url)` on the chip and the preview; `.onTapGesture` opens via `NSWorkspace.shared.open(_:)`.
- Both first check `FileManager.default.fileExists` — the user may have moved or deleted the file — and dismiss silently if gone.

**Verify:** **a real drag into another app.** This is the unverified fact above. If the drag does not start, switch to the AppKit fallback in Risks before continuing.

### Task 7: Auto-dismiss with hover pause

**Files:** `Visor/Features/Screenshot/ScreenshotService.swift`

- On each catch, start a dismiss `Task`: `Task.sleep(for: .seconds(8), tolerance: .milliseconds(500))`.
- On wake, if `store.state == .expanded` the user is looking at it — re-arm for 2s instead of dismissing. No hover observation needed; the state is already in the store.
- Cancel on: new catch, successful drag, tap, `stop()`.

**Verify:** catch → wait → clears at ~8s. Catch → hover through the deadline → survives, clears ~2s after the cursor leaves.

### Task 8: Album colour extraction (pure logic)

**Files:** `Visor/Features/NowPlaying/ArtworkCache.swift`, new `Visor/Features/NowPlaying/AlbumColor.swift`, new `VisorTests/AlbumColorTests.swift`

Prototyped against two real covers before writing this (see Verified facts). Pipeline:

1. 32×32 thumbnail (one extra ImageIO pass per *track*), RGBA8.
2. sRGB → **OKLab**. Not HSB: HSB over-weights yellow and under-weights blue, so "is this colourful enough" is not answerable in it.
3. **k-means, k=5, 12 iterations, k-means++ init with a fixed seed.** The fixed seed is not cosmetic — random init means the same album yields a different colour after a relaunch, which is a real bug class.
4. Score each cluster `chroma × sqrt(population share)`, so a small vivid patch can beat a large muddy one but not overwhelmingly.
5. **Chroma floor 0.045.** Below it return `nil` — greyscale art gets white bars, not a muddy grey. Measured: the Arctic Monkeys B&W cover scores 0.017 and correctly returns nil.
6. **Lift lightness to `max(L, 0.78)` in OKLCh**, preserving hue and chroma. This is what guarantees legibility on black regardless of how dark the album is. Measured 10.2:1 contrast on a dark red cover.

`AlbumColor.from(pixels:width:height:) -> AlbumColor?` is pure over the buffer. `ArtworkCache` caches the result against `trackIdentity` — computed once per track, never per frame.

**Verify:** tests for all-black (nil), all-grey (nil, chroma floor), a black image with a saturated red patch (hue within tolerance, L lifted ≥ 0.78), a near-black navy (lifted, contrast ≥ 7:1), and determinism (same input twice → identical output).

### Task 9: Tint the bars

**Files:** `Visor/Core/NotchStore.swift`, `Visor/UI/PlaybackBars.swift`

- Store carries `nowPlayingTint: Color?`, **written in the same mutation as the artwork** — `setNowPlaying(_:artwork:tint:)`. Two separate writes would leave a frame where new art wears the old colour.
- `PlaybackBarsView.setTint(_:)` animates each layer's `backgroundColor` inside a `CATransaction` whose duration matches `Motion.artFlipIn`, so colour and artwork land on the same frame as the card flip.
- Applies in compact and expanded (the bars are content, not surface). Closed shows no bars at all.
- Tint persists while paused — iOS keeps the colour when playback stops.
- `nil` tint → white, which is also the fallback for: no artwork, decode failure, and chroma below floor.
- **`NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast` forces white.** Reduce Motion does not apply — the colour is static — so this is the accessibility hook that matters here.

**Verify:** three covers (B&W, saturated, near-black) — confirm white / tinted / lifted-and-legible respectively; confirm the island surface is still pure black in every state; confirm no colour flash on track change; toggle Increase Contrast and confirm the bars go white live.

### Task 10: Verification pass + docs

- Screen recording: `screencapture` into the folder while recording, extract frames, confirm the chip appears within ~250ms of the file landing and clears at 8s.
- `sample` the process while idle with a live catch: expect no repeating main-thread work.
- Update RESEARCH §8 (Phase 4) and the CLAUDE.md progress list. Keep both lean.

---

## Edge cases

| Case | Behaviour |
| --- | --- |
| Screenshot copied to clipboard (⌃⇧⌘4) | No file is written; nothing happens. Correct. |
| Several screenshots in a row | Newest wins, dismiss timer resets |
| File deleted/moved before dismiss | Tap and drag both check existence, then dismiss silently |
| Screenshot folder missing or unreadable (TCC) | Log once, feature inert, rest of app unaffected |
| Folder is Desktop/Documents/Downloads | macOS prompts for folder access on first enumeration. Unavoidable. |
| Folder changed in System Settings while running | Not picked up until relaunch. Accepted; re-reading would mean watching a defaults domain for a rare event. |
| Display asleep | Existing rules already gate animation; the catch simply waits |
| Greyscale album art | No tint (chroma floor), bars stay white — verified on a real B&W cover |
| Near-black album art | Hue preserved, lightness lifted to 0.78 so the bars stay legible |
| Increase Contrast enabled | Bars force to white, live |
| Same album played again later | Identical colour — fixed-seed k-means++, no run-to-run drift |

## Power

One file descriptor and one `DispatchSource` for the life of the app — the kernel wakes us only when the folder changes. One thumbnail decode per catch, off the main thread. One dismiss `Task` with 500ms tolerance, alive only while a catch is live. Tint costs one extra 16×16 decode per *track*, and renders as a static gradient — no animation, no per-frame work. Expected delta to the measured 0.0% idle: none.

## Risks

| Risk | Mitigation |
| --- | --- |
| `.draggable` may not start a drag from a non-key, non-activating panel | Task 6 finds out with one real drag. Fallback: `beginDraggingSession(with:event:source:)` on `NotchContentView`, which already receives mouse events — ~20 lines, same behaviour |
| Third `ActivityKind` re-grows what the cleanup pass deleted | Accepted: unlike `.timer`/`.hud`, this kind has a producer shipping in the same change |
| Tint washes out the black surface — a material and a blurred bleed were both reverted before for this | **Eliminated by design:** the surface is never tinted. Colour goes only into the bars, which are already content |
| A colour that is technically dominant but ugly (muddy browns from a sepia cover) | Chroma floor plus the lightness lift push these to either "no tint" or a clean pastel. If a cover still reads badly, the floor is one constant |
| Large screenshot (6K display, ~20MB PNG) hitches the decode | Decode is detached and capped at 256px via ImageIO thumbnailing, which does not decode the full image |
| TCC prompt surprises a user whose screenshots go to Desktop | Documented in README; the failure mode is an inert feature, never a crash |

## Rollback

Both features are additive. The catcher is three new files plus one service registration in `AppDelegate`; the tint is one new file plus two small view changes. Reverting either means deleting its files and its wiring — no shared state, no migrations.
