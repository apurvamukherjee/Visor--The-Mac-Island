# Visor — what is pending, and the re-plan (2026-09-24, at 2.9.2 build 33)

Audit of every source file, `CLAUDE.md`, `CHANGELOG.md`, `docs/RESEARCH.md`,
both spec files and all three plan files. Nothing here is built yet; this is
the list and the order.

**The headline:** almost nothing is *unbuilt*. 18 feature folders ship, 299
tests pass, swiftlint is at 3/0-serious. What is pending is **verification**,
and the two oldest checklists that verification is supposed to run from now
describe an island that no longer exists.

---

## A. Stale checklists — fix these before anything else

Both hardware checklists predate three UX decisions. Running them as written
produces false failures, which is worse than not running them.

### Phase 2 Task 10 (`~/.claude/plans/notchy-phase2-live-activities.md` §1341-1350)

| # | Item as written | Status |
|---|---|---|
| 7 | "island expands, shows **clock + battery row** + full Now Playing" | **Stale.** The clock/battery row was cut — the agenda and music columns needed the height and the row pushed content past the shape's bottom edge. Time is in the menu bar, battery is in the wings (`NotchRootView.expandedContent` doc comment). |
| 4 | "then reverts to closed (no music) or compact-with-music" | **Stale.** A *paused* track now collapses the island after 5s (`Dwell`, 2026-09-20), so the third outcome "paused → collapses" is missing. |
| 1-3, 5, 6, 8, 9, 10 | — | Still valid. |

### Phase 3 Task 11 (`docs/superpowers/specs/2026-09-16-notch-content-layer-design.md` §274-285)

`CLAUDE.md` says 16 items; the spec has 10. **The 16 does not exist anywhere
on disk** — treat 10 as the real number and correct `CLAUDE.md`.

| # | Item as written | Status |
|---|---|---|
| 3 | "Mood chip bar appears only while playing; exits in reverse on pause" | **Delete.** The chip bar was removed 2026-09-16 (stub actions, and its canvas reserve pushed the island 22pt below the notch). |
| 4 | "Idle → music-live resizes the **calendar column** in ONE animation" | **Rewrite.** The music card has had no calendar column since 2026-09-19 ("with a track loaded the island is the player and nothing else"). The coordinated-resize claim is still worth testing — against the *lyrics* column, which is the only second column left. |
| 6 | "**Chips** are clickable; everywhere outside the shape clicks through" | **Rewrite.** No chips. The click-through half is a live regression guard and must survive; the clickable half now means the transport row and the shelf tiles. |
| 1, 2, 5, 7, 8, 9, 10 | — | Still valid. |

### New checklist items neither list has

The island grew four pages, a deck, a palette and a badge since these were
written. Nothing verifies any of it except the card stack's own list.

- Card stack: the 10-item list in `docs/superpowers/plans/2026-09-23-island-card-stack.md`
  §Task 7 Step 3 is current and unrun.
- Paging: swipe reaches agenda/home/usage/shelf; **the box never resizes**
  (the rule the whole of RESEARCH §2.6b exists to protect).
- The shelf page appears only with something on it, and a catch no longer
  costs you the player (2.9.0).
- Every short screen is now vertically centred (2.9.1) — volume, alerts,
  timer, shelf, a one-row usage screen.
- Palette: 37 commands, per-command letter shortcuts, 10 launch-group slots.
- AI usage badge: hides while music owns the island, returns after.

---

## B. Verification debt — built, never seen on hardware

Ranked by how likely a fault is to be structural rather than cosmetic.

| Item | Shipped | Why it is risky |
|---|---|---|
| **Card stack** (chins, gradients, retract-before-collapse) | 2.7.0-2.9.0 | Three releases of fixes, none confirmed. The retract-before-collapse ordering is the same class of bug as the 2026-09-19 clipping fix; if it is still wrong it is visible on every close. |
| **Shelf as a page** | 2.9.0 | Changes `expandedPriority` — a screenshot during playback is the case to try. |
| **Global centring** | 2.9.1 | Touches every expanded screen in one line. Cheap to check, wide blast radius. |
| **Equaliser at the edge + badge exclusivity** | 2.9.2 | Cosmetic, one screen. |
| **Launch Groups** | 2.7.0 | Ten palette slots that spawn apps. Never run once. |
| **Palette beyond ⌃⌥K** | 2.6.0 | The hotkey is confirmed; none of the 37 commands are. |
| **AI usage badge's music rule** | 2.6.0 | Badge itself is confirmed on hardware; the hide/return rule is not. |
| **Codex token figure** | 2.6.0 | Schema-verified, **never seen against real rows** — `threads.tokens_used` was empty on this machine. Needs one real Codex session. |
| **`DeviceBatteryService`** | 2026-09-19 | Never verified at all. One command answers it: `ioreg -r -c AppleDeviceManagementHIDEventService -l \| grep -i BatteryPercent` |

---

## C. Known open faults

1. **Dragging an image out of a browser is rejected.** The drop target is
   `dropDestination(for: URL.self)`; a browser vends TIFF/PNG *data*, not a
   file URL. The adopt path already writes clipboard image data to a file
   (`Stash Clipboard`, 2.5.0) — the same writer would serve here. **Small,
   self-contained, and the most user-visible gap on the list.**
2. **The volume island misses 0% and 100%.** At either rail a keypress changes
   nothing, so CoreAudio fires nothing and the island never appears. Stated
   as the ceiling of the no-permission approach and left open on purpose;
   closing it means a `CGEventTap` on the media keys, which is an
   Accessibility prompt.
3. **Calendar permission re-prompts on every build.** TCC keys grants to the
   code signature and ad-hoc signing gives every build a new cdhash. `DEVELOPMENT_TEAM`
   is still commented out at `project.yml:40`. Free Apple ID is enough. **One
   line, and it unblocks testing the calendar-denied path at all.**

---

## D. Never built — roadmap items still standing

From RESEARCH §8 Phase 5 and §6.3 "Later", minus what has since shipped:

- **Brightness HUD** — DisplayServices is private; the honest alternative is
  observing key events, which is the same Accessibility prompt as (C2). Pairs
  with it or neither.
- **Media-key HUD replacement** — explicitly dropped in the old-code port for
  the CGEventTap + Accessibility cost. Same prompt again; these three are one
  decision, not three.
- **Notarization / Developer ID / Sparkle / Homebrew cask** — gated on a paid
  developer account. Until then ad-hoc `.dmg` is the distribution, which is
  what `make-dmg.sh` already does.
- **Progress-as-bottom-lip** — cut by choice in Phase 5, recorded as "scoped,
  feasible, cheap to revive". The only cut on the list with no blocker.

Launch at login (§6.3) and the global shortcut (§6.4) are **done** and the
table still lists them as Later — correct §6.3 while editing.

---

## E. Code debt — small, none urgent

| Item | Size |
|---|---|
| 20 hand-rolled `min(max(…))` where `Comparable.clamped(to:)` already exists | ~20 lines |
| `ExpandedUsageView.tools` duplicates `NotchStore.usageRows` | 1 helper |
| `Haptics`: 4 of 5 functions are byte-identical `.generic`/`.drawCompleted` calls | ~12 lines |
| `IslandLayout.resolved(for:content:)` at cyclomatic 12 (limit 10) | 1 warning |
| Two `large_tuple` warnings in `AlbumColorTests` | known, deliberate |
| Two `ponytail:` markers (`ClaudeUsageReader` newest-by-mtime, `NotchContentView` hit-test radii) | both correctly scoped, no action |
| **`CLAUDE.md` is 664 lines against its own "<200 lines" rule** | the Progress section is now longer than the rules it precedes |

---

## The re-plan — proposed order

**1. Make the checklists true (docs only, no code).**
Correct Phase 2 Task 10 items 4 and 7, Phase 3 Task 11 items 3, 4 and 6, fix
the 16→10 count in `CLAUDE.md`, and fold in the new items from §A. Move
launch-at-login and the global shortcut out of RESEARCH §6.3. **Nothing can
be verified honestly until this is done**, which is why it is first.

**2. Set `DEVELOPMENT_TEAM` (one line).**
Unblocks the calendar-denied path, which is item 7 on the Phase 3 list and
currently untestable.

**3. Run the hardware pass.**
Phase 2 (10), Phase 3 (10), card stack (10), plus the new items. This is
yours to run; I can only fix what it finds. Expect the card stack and the
shelf page to produce the real findings.

**4. Fix browser-image drops (C1).**
The only open fault with no permission cost and a writer that already exists.

**5. Then, and only then, features.**
Progress-as-bottom-lip is the cheapest. The Accessibility trio (media-key HUD,
brightness, volume rails) is one yes/no about a TCC prompt — worth deciding
once rather than three times.

**Explicitly not proposed:** a volume bar sized from the card (tried, rejected
on sight 2.9.1), any change to the one-box rule, and Notification Center
mirroring / Focus names / Chromium history (all TCC-blocked, each already
recorded with a reason).

---

## Open questions

1. **The Accessibility prompt** — media-key HUD, brightness HUD and the volume
   0/100 rails all need `CGEventTap` + an Accessibility grant. One decision.
   Is Visor allowed to ask for it?
2. **Hardware pass scope** — 30 items across three lists. All at once, or
   card stack first since it has three releases of unconfirmed fixes behind it?
3. **`CLAUDE.md` at 664 lines** — move Progress to its own `docs/PROGRESS.md`
   and leave rules + a pointer, or leave it?
