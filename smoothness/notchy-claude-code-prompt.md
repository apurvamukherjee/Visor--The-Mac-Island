# Notchy — UI & motion overhaul

You are the lead macOS engineer on Notchy, my personal notch "Dynamic Island" app (SwiftUI + AppKit, XcodeGen, MacBook Air M4 15", macOS Sequoia). Phase 1 (closed island scaffold) is done and passes an 8-item hardware checklist. Phase 2 (live activities: battery + Now Playing, closed → compact → expanded) is planned. Your job: make the island feel like Apple shipped it — edge-to-edge shape that grows out of the bezel, zero jitter, interruptible springs, near-zero idle CPU.

## 0. Before writing any code
1. Read the whole repo, especially NotchGeometry, NotchShape, NotchPanel, NotchStore, Motion, NotchRootView, NotchWindowController, the tests, RESEARCH.md and tender-waddling-rose.md.
2. Read `docs/motion/notchy-motion-reference.html`. It is the source of truth for every number below; the tokens block at the top of its script mirrors this spec. If ffmpeg is installed, extract frames from `docs/motion/notchy-ui-reference.mp4` (`ffmpeg -i docs/motion/notchy-ui-reference.mp4 -vf fps=10 frames/%03d.png`) and look at them.
3. Report back: (a) whether the NSPanel frame changes during any animation, (b) how hover and hit-testing work today, (c) where springs are defined. Then propose a step plan. Do not code until I approve.

## 1. Defects to fix (seen in a 60fps screen recording)
- D1 Collapse tail: after collapsing, the shape lingers a few pt below the hardware notch for ~0.25s. Any move that ends smaller must be critically damped, and the closed target must sit fully inside the hardware notch.
- D2 No shoulders: panel sides meet the screen top at 90°. Add concave top fillets so the shape flares into the bezel.
- D3 Bottom radius is constant (~12pt) at every size. It must be an animated parameter per state.
- D4 Content is revealed by the growing mask at final layout, so glyphs get sliced mid-open. Content must enter after the shape is ~50% open.
- D5 Page switch blurs both pages to empty black for ~150–200ms. Replace with an overlapping, directional transition and a visible tab indicator.
- D6 Layout is left-heavy with low contrast, the area beside the camera is unused, and "no context reported" reads as an error.

## 2. Geometry: ONE shape for every state
A single `NotchShape` draws closed, compact and expanded. The same shape instance is used for fill, content clip, and hit-test (`contentShape`). Four animatable params, animated together in one transaction:

| State | width | height | bottomRadius | shoulderRadius |
|---|---|---|---|---|
| closed | hardware notch width (measured) | safeAreaInsets.top | 9 | 5 |
| compact · now playing | notch + 2×62 | notch height | 11 | 6 |
| compact · charging | notch + 2×80 | notch height | 11 | 6 |
| expanded | 548 | 188 | 30 | 14 |

Measure the notch at runtime per screen: width = `screen.frame.width − auxiliaryTopLeftArea.width − auxiliaryTopRightArea.width`, height = `safeAreaInsets.top`. Re-measure on screen-parameter changes (you already handle reconfiguration; keep that). Keep the existing closed-state calibration that made it invisible; the closed shape must never extend past the hardware cutout at rest.

Path, mirrored from the prototype. Use `addCurve`, not `addArc(clockwise:)`, which caused a backwards-sweep bug before.

```swift
struct NotchShape: Shape {
    var width: CGFloat, height: CGFloat, bottomRadius: CGFloat, shoulderRadius: CGFloat
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(width, height), .init(bottomRadius, shoulderRadius)) }
        set { width = newValue.first.first; height = newValue.first.second
              bottomRadius = newValue.second.first; shoulderRadius = newValue.second.second }
    }
    func path(in rect: CGRect) -> Path {          // rect = fixed panel canvas; shape glued to rect.minY
        let cx = rect.midX, top = rect.minY
        let L = cx - width/2, R = cx + width/2, B = top + height
        let s = max(0, min(shoulderRadius, height * 0.5))
        let k: CGFloat = 0.5523, reach: CGFloat = 1.18   // circle handle; continuous-corner reach
        let r = max(0, min(bottomRadius, (height - s)/reach, (width/2)/reach))
        let a = r * reach, hd = r * 0.30
        var p = Path()
        p.move(to: .init(x: L - s, y: top - 2)); p.addLine(to: .init(x: L - s, y: top))
        p.addCurve(to: .init(x: L, y: top + s), control1: .init(x: L - s + s*k, y: top), control2: .init(x: L, y: top + s - s*k))
        p.addLine(to: .init(x: L, y: B - a))
        p.addCurve(to: .init(x: L + a, y: B), control1: .init(x: L, y: B - hd), control2: .init(x: L + hd, y: B))
        p.addLine(to: .init(x: R - a, y: B))
        p.addCurve(to: .init(x: R, y: B - a), control1: .init(x: R - hd, y: B), control2: .init(x: R, y: B - hd))
        p.addLine(to: .init(x: R, y: top + s))
        p.addCurve(to: .init(x: R + s, y: top), control1: .init(x: R, y: top + s - s*k), control2: .init(x: R + s - s*k, y: top))
        p.addLine(to: .init(x: R + s, y: top - 2)); p.closeSubpath()
        return p
    }
}
```

## 3. Motion spec (SwiftUI `.spring(response:dampingFraction:)`)
| Token | response | damping | Used for |
|---|---|---|---|
| open | 0.48 | 0.78 | anything → expanded (small felt overshoot) |
| compactGrow | 0.42 | 0.86 | closed → compact, compact → wider compact |
| settle | 0.38 | 1.00 | ANY move that ends smaller (expanded → compact/closed, compact → closed) |
| tab | 0.34 | 0.86 | tab indicator + incoming pane |
| fadeIn | 0.30 | 1.00 | content entering |
| fadeOut | 0.14 | 1.00 | content leaving, starts immediately |

Choreography:
- Shape leads. Expanded content enters with a 0.10s delay; compact wings with 0.08s. Enter = opacity 0→1, blur 6→0, scale 0.95→1, y −8→0, anchor top-center (it grows out of the notch).
- Leaving content goes out immediately with fadeOut and is gone before the shape is ~40% collapsed.
- Tab switch: outgoing pane slides −18pt×direction and fades; incoming slides from +18pt×direction with a 0.04s delay, no scale. The pill indicator springs to the new tab. Never show an empty panel.
- Compact wings are anchored to the live shape edges with a 12pt inset and scale 0.8→1 from the notch center. Do this with an `Animatable` ViewModifier fed the same width value, so wings ride the edge instead of floating or getting clipped.
- Shadow scales with expansion e = (h − notchH)/(expandedH − notchH): y 14e, radius 30e, opacity 0.55e. No shadow when closed. The window's `hasShadow` stays false.
- Hover intent: expand 70ms after entering; collapse 200ms after leaving. Retargeting mid-flight must keep velocity (never restart from the start value).
- Reduce Motion: every geometry move uses response 0.28 with damping 1.0, content uses opacity only, no blur or offset.

## 4. Layout spec
Colors: island #000; primary #FFFFFF; secondary rgba(235,235,245,0.6); tertiary 0.3; red #FF453A; green #30D158; Claude orange #D97757 (icon only). Font: system SF Pro, `.monospacedDigit()` on all numbers.

- Expanded header row (height = notch height), split around the camera: 3 tab icons (home, music note, spark) as 30×24 pills at a 36pt pitch starting 22pt from the left edge, with a 16% white pill indicator. Battery % + glyph on the right, secondary color. Nothing goes under the camera.
- Body starts at notchH + 12, 24pt side padding.
- Home tab: date column ("THU" 12pt bold red, "24" 44pt semibold tight tracking, month 12pt secondary) · "Up next" column (empty state: check icon + "Nothing left today", plus a "New reminder" pill) · "Timer" 2×2 chips (1m 5m 10m 25m, 56×26, 11% white).
- Media tab: 76pt artwork (radius 16, soft tinted shadow), title 16 semibold, artist 13 secondary, prev/play/next at 22pt spacing on the right, scrubber (5pt track, elapsed and remaining times 11pt tertiary).
- Claude tab: icon + "Claude Code", "N sessions today" right-aligned; "1.3M" 32pt semibold + "tokens today"; 24 hourly bars with the current hour in orange; "Context: not reported by this session yet" in tertiary.
- Compact now playing: 22pt artwork on the left wing, 4-bar orange equalizer on the right. Compact charging: green bolt left, "82%" + battery glyph right, green.
- Priority: hover → expanded; else charging peek (2.5s) → now playing → closed.

## 5. Engineering rules (anti-jitter + power)
1. The NSPanel is created once at max expanded size + shadow margin, pinned to the screen top at integral coordinates. Never call setFrame during an animation. All motion happens inside SwiftUI through the shape's animatableData.
2. One `IslandGeometry` value in NotchStore; change all four params inside one `withAnimation`. No implicit `.animation()` on containers.
3. Fill, clip, and hit-test use the same NotchShape values. Keep the existing menu-bar passthrough behavior exactly.
4. Content in expanded panes has fixed layout; only opacity/blur/scale/offset animate. No frame changes per animation tick for text.
5. Snap resting geometry to device pixels (backingScaleFactor). Mid-animation fractional values are fine.
6. Blur only while a layer is transitioning (radius 0 at rest), with `.compositingGroup()` before blur. The equalizer and scrubber tick only while visible and playing (TimelineView paused otherwise). Idle closed = no timers, no redraws.
7. Budgets: idle ~0% CPU; playing music <0.5%; no dropped frames in Instruments (Animation Hitches) during open, close, and tab switch.

## 6. Plan (commit after each step; tests green at every step)
1. Motion + geometry tokens exactly as above; NotchShape four-param version; unit tests (point-sampling for shoulders and bottom corners; no NaN at zero sizes; a spring simulation proving the settle token never goes below its target when shrinking).
2. Fixed-size panel audit and fix if needed; single geometry state; closed ↔ expanded with the new springs.
3. Content choreography + tab system (Home, Media, Claude) with directional transitions and indicator.
4. Compact states (Phase 2 plumbing: Activity priority, BatteryService, NowPlayingService) using the wing-anchoring modifier.
5. Reduce Motion path, shadow, pixel snapping, idle-power pass.
6. Verification: record the screen at 60fps for open, close, a rapid in/out flick (interrupt), tab switches, and the charging peek. Frame-step with ffmpeg and confirm no clipped glyphs, no empty frames, and no lip below the notch after collapse. Re-run the Phase 1 hardware checklist and the Phase 2 checklist.

## 7. Guardrails
- Don't regress any Phase 1 checklist item. Don't add dependencies beyond the planned mediaremote-adapter.
- Ask before deleting or renaming existing types.
- At the end of each step, report: what changed, test results, anything unverified, and what I need to check on hardware. Be honest about what you could not test.
