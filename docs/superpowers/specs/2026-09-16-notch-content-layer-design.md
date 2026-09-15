# Notchy Phase 3 — Content Layer (material, calendar, expanded layouts, motion)

> Design spec. Status: approved in brainstorm 2026-09-16, pending implementation plan.
> Supersedes the Phase 2 expanded/compact *content* views. Does **not** touch the
> shape-morph or activity-priority systems (RESEARCH.md §2.6, §3.3) — those stay settled.

## 1. Goal

Replace Phase 2's placeholder content (clock + battery row + basic Now Playing block)
with the real UI/UX layer: a translucent material surface, an EventKit-backed calendar
agenda, a split music+calendar expanded layout, a play-state-gated mood chip bar, and
the micro-animations that make the island read as "fluid" rather than functional.

The bar is Alcove's animation polish, whose own marketing leads with "fluid
transitions" — concretely, that means spring-only curves, no state pops without
intermediate frames, and coordinated (not sequential) multi-property transitions.

## 2. Decisions locked during brainstorming

| Decision | Choice | Why |
|---|---|---|
| Closed state | **Stays pure black and invisible against the hardware notch** | Phase 1 acceptance criterion; the masquerade-as-hardware illusion is the foundation the whole app is built on |
| Expanded width | **Grows to ~600pt** | The two-column agenda is the point of the idle-expanded state; it does not fit at 320pt |
| Spec scope | **One spec covering the whole brief** | User's explicit call over a 3-way decomposition |
| Album art on track change | **Crossfade + scale-pop, not a 3D flip** | See §9.2 |
| Material | **`NSVisualEffectView(.hudWindow)`** | See §6 |
| Mood chip hit-testing | **Union of shape path + chip-row rect** | Keeps the detached-with-a-gap look without a second panel; see §10 |
| Swipe gestures | **Simple threshold `DragGesture`** | Roadmap says plain next/previous; no rubber-band preview |

## 3. Explicitly dropped

- **Brief states 1 & 2 (closed pill with calendar glyph / art thumbnail + dot).**
  A direct consequence of keeping the closed state invisible — there is no visible
  closed pill to put content in. The "activity-aware icon swap" concept already
  exists at the compact wings (`CompactActivityView`), which is where it stays.
- **Instant Notifications (mirroring macOS system notifications).** Dropped after a
  feasibility spike on 2026-09-16: Notification Center's DB
  (`~/Library/Group Containers/group.com.apple.usernoted/db2/db`) exists on macOS
  26.6.2 but is TCC-blocked ("Operation not permitted") without **Full Disk Access**,
  an all-or-nothing manual grant covering the entire disk. Schema is undocumented and
  unversioned. Disproportionate permission cost plus breaks-on-any-update fragility.

## 4. Non-goals

- No rebuild of `NotchShape`, `NotchWindowController` sequencing, `Activity`/
  `ActivityKind` priority, or the `NotchService` contract.
- No settings/preferences surface for mood chips — tap handler is a logging stub.
- No mood-playlist backend. The chip bar's entrance/exit/scroll feel is the deliverable.
- No AppKit/Core Animation springs where SwiftUI's `.spring()` suffices.

## 5. Geometry

`Notchy/Window/NotchGeometry.swift`:

```
expandedSize   320×120  →  600×220     (starting values, tune by eye)
chipBarHeight  36 (new)
chipBarGap      8 (new)
```

`expandedCanvasRect(for:)` — already exists from the collapse-jitter fix — must now
also reserve the chip bar's vertical space:

```
expandedRect ∪ compactRect, then height += chipBarGap + chipBarHeight
```

Rationale: the panel is transparent, so an over-tall canvas costs nothing visually,
and it means the chip bar animates in inside an already-large-enough frame. This is
the same lesson the expanded→compact jitter bug taught — never grow a frame
*during* an animation; size it before.

Note: once `expandedSize.width` is 600, `compactRect` (closed width + 160 ≈ 360) is
strictly inside it, so the `∪ compactRect` term becomes inert. Keep it — it is still
correct, and it guards the non-notched-screen fallback path where `closedRect` is a
200pt pill and the numbers are closer.

## 6. Material & accessibility

**One shape, animated fill — never two cross-faded shapes** (RESEARCH.md §2.5).

Layer order, bottom to top, all masked to the same `NotchShape`:

1. Soft outer bleed: a duplicate shape, blurred (~8pt), low opacity, behind everything,
   so the edge doesn't hard-cut against the wallpaper.
2. `NSVisualEffectView(material: .hudWindow, blendingMode: .behindWindow)` wrapped in
   an `NSViewRepresentable`.
3. Black overlay whose **opacity animates with state**: `1.0` closed → `~0.15` expanded.

At closed, opacity 1.0 means pure black — the hardware-notch masquerade is preserved
exactly. The material only becomes visible as the shape grows past the real cutout.

**Material choice — `.hudWindow` over `.underWindowBackground`:** `underWindowBackground`
is semantically "the material shown *under* a window's background," designed for
layering inside a window; floating it as the top surface reads washed-out and
low-contrast. `.hudWindow` is the semantic match for a small translucent panel
floating over arbitrary content, which is exactly what the island is.

**Accessibility fallbacks:**

- **Reduce Transparency** (`NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency`):
  skip the visual-effect view entirely, pin the black overlay at 1.0, drop the outer
  bleed. Solid fill in every state.
- **Reduce Motion**: already handled by `Motion.resolved(_:)`. Every new token in §9
  must route through it — including the chip bar and art-swap animations.

Both are read at render time, and both post change notifications
(`NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`) — observe once, no polling.

## 7. Calendar

New feature folder `Notchy/Features/Calendar/`.

**`CalendarEvent`** — pure model, the unit-testable surface:

```swift
struct CalendarEvent: Equatable, Identifiable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: Color   // from EKCalendar.color
}
```

**`CalendarEventMapper`** — `EKEvent → CalendarEvent?`, plus today-filtering and
sort-by-start. Pure functions, fully unit-tested (matches how `BatteryInfoParser`
and `NowPlayingInfo.from` are tested).

**`CalendarService: NotchService`** — `EKEventStore`, event-driven only:

- `start()`: request access, fetch today, subscribe to `.EKEventStoreChanged`.
- Access via `requestFullAccessToEvents()` (macOS 14+; read access requires *full*
  access, write-only is insufficient).
- Refresh **only** on `.EKEventStoreChanged` and on `NSWorkspace` wake — no polling,
  no timers. This is the non-negotiable power rule.
- `stop()`: remove the observer, drop the store reference.
- Denied / restricted / not-determined → empty event list, logged once at `.info`.
  The UI degrades to music-only; it never blocks or nags.

**Info.plist** via `project.yml`: `NSCalendarsFullAccessUsageDescription`.

> ⚠️ Verify at implementation time: macOS 14+/iOS 17+ introduced
> `NSCalendarsFullAccessUsageDescription`, superseding `NSCalendarsUsageDescription`.
> Confirm the exact key the current SDK enforces before shipping — a wrong key is a
> silent permission failure, not a build error.

**Store additions** (`NotchStore`, additive only):

```swift
private(set) var calendarEvents: [CalendarEvent] = []
func setCalendarEvents(_ events: [CalendarEvent])
```

Calendar is deliberately **not** an `ActivityKind`. It is ambient context shown in the
expanded state, not something that claims the compact state.

## 8. View hierarchy

```
NotchRootView
├─ closed   → (no content)
├─ compact  → CompactActivityView              (unchanged from Phase 2)
└─ expanded → ExpandedIdleView                 when store.nowPlaying == nil
            → ExpandedMusicView                when store.nowPlaying != nil
               └─ MoodChipBar                  when info.isPlaying (docked below)
```

- **`EventRow`** — shared by both expanded layouts. Colored left-bar chip, title,
  time. **One implementation**; only the container layout differs between states.
  Forking this styling is explicitly out of bounds.
- **`ExpandedIdleView`** — date header ("WED 16"), two-column agenda, `+N more events`
  overflow row when > ~4 items today.
- **`ExpandedMusicView`** — split, fixed 600pt outer width:
  - left: album art + title/artist + transport (prev / play-pause / next)
  - thin vertical divider
  - right: next-2-events peek, single column, same `EventRow`
  - Absorbs and replaces Phase 2's `ExpandedNowPlayingView`.
- **`MoodChipBar`** — horizontally scrollable pill row (Party / Feel good / Relax /
  Sleep / Work out / Commute). Selected chip filled, others outlined. Scrolls within
  its own fixed width — never widens the island above it. Tap → `Log` stub.

**Idle ↔ music is one coordinated layout animation, not a fade-and-replace.** Because
the outer width is fixed at 600, the calendar column compressing (full two-column →
~50% single-column 2-event) and the music column growing in from the left are the
*same* layout change, driven by one `withAnimation`. This is why §5 keeps a single
expanded size instead of two.

**Superseded for certain:** `ExpandedNowPlayingView` — `ExpandedMusicView` absorbs it
wholesale.

**⚠️ Open — needs the user's call before implementation.** The reference design has no
room for three things that exist today. Each is a visible loss, so none should be
deleted silently:

| Existing view | What the reference design does | Options |
|---|---|---|
| `SignatureGlow` ("By Apurva") | No equivalent. RESEARCH.md §0 says attribution belongs in Settings/About, but the user explicitly asked for it in the notch and asked for it *larger* on 2026-09-16 | (a) keep it in idle-expanded alongside the agenda, (b) move to Settings/About per §0, (c) drop |
| `ClockPlaceholderView` | Idle-expanded has a **date** header ("WED 16"), no time-of-day clock | (a) add time beside the date header, (b) drop the clock |
| `ExpandedBatteryRow` | No battery in the expanded state; battery lives in the compact wings only | (a) keep a small battery readout in a corner of expanded, (b) drop from expanded |

Default if unanswered: keep all three (option (a) in each row) — additive, reversible,
and never silently removes something the user asked for.

## 9. Motion

All new curves are `Motion` tokens routed through `Motion.resolved(_:)`. No raw
`.spring`/`.easeInOut`/durations in view code — the existing rule, extended.

### 9.1 New tokens

| Token | Use | Shape |
|---|---|---|
| `Motion.layout` | idle ↔ music column redistribution | spring, response ~0.40, damping ~0.8 |
| `Motion.artSwap` | album art crossfade + scale-pop | spring, ~0.30 |
| `Motion.textSwap` | title/artist crossfade | `.easeInOut(0.15)`, opacity only |
| `Motion.chipBarIn` | chip bar entrance | spring ~0.40, delayed ~0.12 after play-state settles |
| `Motion.chipBarOut` | chip bar exit | spring ~0.28, reverse of entrance (not a plain fade) |

Spring-only for every state change, per the brief. The failure modes to avoid — the
ones public comparisons call out in less-polished competitors — are linear easing, no
overshoot, and abrupt pops with no intermediate frame.

### 9.2 Album art on track change — crossfade, not 3D flip

**Decision: crossfade + scale-pop (0.92 → 1.0), keyed on `NowPlayingInfo.trackIdentity`.**

A Y-axis `rotation3DEffect` sells its illusion through perspective foreshortening
across the card's width. At the 40–60pt art sizes in play here, the foreshortened
mid-flip frames span a handful of pixels, so the 90° texture swap lands in roughly one
or two frames and reads as a flicker rather than a flip — and it is exactly the move
that looks cheap without a carefully tuned `perspective` value. The flip earns its
keep at ~120pt+ (iPad-widget scale). Revisit only if expanded art grows past ~100pt.

**Text never flips or rotates — opacity crossfade only.** Images may transform; text may not.

**Transport icons do not animate on skip.** They animate only on their own state
change: play ↔ pause uses `.contentTransition(.symbolEffect(.replace))` (crossfade +
scale), never a hard cut.

### 9.3 Swipe

Threshold `DragGesture` on `ExpandedMusicView` → `commands.next()` / `.previous()`.
No live visual tracking during the drag, no velocity handling — the roadmap specifies
plain next/previous.

## 10. Hit-testing

The mood chip bar sits *below* the island shape with a visible gap. Chips there fall
outside `NotchShape`'s path, and `NotchContentView.hitTest` returns `nil` outside that
path — which is exactly what makes click-through work everywhere else. Left alone, the
chips would render but be inert.

**Fix:** when the chip bar is visible, `hitTest` accepts the **union** of the shape
path and the chip-row rect. Everywhere else is unchanged, so click-through is preserved.

Rejected alternative: a second panel for the chip bar — more lifecycle machinery,
more frame sequencing, same visual result.

## 11. Testing

Unit-testable (Swift Testing, matching the existing suite):

- `CalendarEventMapper`: `EKEvent` → `CalendarEvent` mapping, today-filtering,
  sort order, all-day handling, malformed/missing fields.
- Agenda overflow math: "+N more events" count for N events at a given cap.
- `NotchGeometry`: `expandedCanvasRect` reserves chip-bar height; compact still fits inside.

Not unit-tested (matches the project's existing no-UI-tests convention): the SwiftUI
views themselves, the material layer, and every animation. Those go on the manual
checklist.

Manual checklist (Phase 3's equivalent of Task 10):

- [ ] Reduce Transparency on → solid black fill, no material, no bleed, in every state.
- [ ] Reduce Motion on → no springs anywhere, including chip bar and art swap.
- [ ] Mood chip bar appears only while playing; exits in reverse on pause.
- [ ] Idle → music-live resizes the calendar column in ONE coordinated animation.
- [ ] Closed state still invisible against the hardware notch (regression guard).
- [ ] Chips are clickable; everywhere outside the shape still clicks through.
- [ ] Calendar permission denied → music-only layout, no nag, no blank crash.
- [ ] Track skip: art crossfades + pops, text crossfades, transport icons stay still.
- [ ] Swipe left/right on expanded music changes track.
- [ ] Idle CPU unchanged from Phase 2 (calendar is event-driven; verify no wakeups).

## 12. RESEARCH.md updates required

This spec changes decisions recorded as settled. Update when implementing:

- **§8 Phase 3** — currently lists "swipe gestures, settings window, launch at login."
  Add the material layer, calendar agenda, expanded split layout, mood chips.
  Note that calendar moved up from Phase 4.
- **§8 Phase 4** — remove calendar (pulled into Phase 3).
- **§5.2 power rules** — add: calendar refresh is `.EKEventStoreChanged`-driven only.
- **§0** — add a row for the material decision (`.hudWindow`, black overlay at closed)
  and note the expanded-size change to 600×220 with its larger menu-bar overlap.
- **§6.3** — move Calendar/EventKit out of "Later" into implemented.

## 13. Risks

| Risk | Mitigation |
|---|---|
| `NSCalendarsFullAccessUsageDescription` key wrong → silent permission failure | Verify against the current SDK before shipping; test the denied path explicitly |
| 600pt expanded covers more menu bar | Already an accepted tradeoff (RESEARCH.md §0), just larger. Revisit if it proves annoying in daily use |
| Material at the notch edge doesn't blend as cleanly as the reference images suggest | Tune bleed blur/opacity by eye; fallback is reverting to flat black for expanded too |
| Chip-bar hit-test union regresses click-through | Covered by an explicit manual checklist item |
| 600×220 + chip bar is a large transparent panel | Panel is click-through outside the shape and nothing animates when not visible; verify idle CPU is unchanged |
| EventKit access prompt appears at an awkward moment | Request on first `start()`, log and degrade on denial; never block the UI |
