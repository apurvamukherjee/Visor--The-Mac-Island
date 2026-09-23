# Island card stack

Paging inside the expanded island becomes a visible deck. Two adjacent
pages peek as chins below the front card, the stack cycles endlessly in
both directions, and each page carries its own tint so the chins read as
distinct screens rather than a drop shadow.

Today's paging (§2.6b, "one box per page") cross-fades content inside a
shape that does not move. That stays reachable: the stack is a *style*,
selected in Settings, and the unwritten key is the cross-fade.

## 1. What changes, and what does not

| | Today | With the stack |
|---|---|---|
| Box size | one box covering every page | same box, plus `chinReveal` height |
| Page swap | `.island` transition, keyed on `islandPage` | cards animate between depths |
| Ends of the stack | clamp | wrap |
| Surface colour | pure black | chins tinted; front black unless opted in |
| `NotchShape` | one silhouette | unchanged — reused per card |

`IslandLayout.covering` is untouched. The front card is exactly the size
and shape it is today; everything here is additive and lives below it.

## 2. Geometry

A new view, `IslandStack`, owns a `ZStack` of one card per available
page. Each card is a `NotchShape` at the resolved expanded size,
displaced by its **depth** — its distance from the front along the swipe
axis.

```
depth 0   offset.y 0    inset.x 0     the front card, today's geometry
depth 1   offset.y 9    inset.x 11
depth 2   offset.y 18   inset.x 22
```

The inset is what makes the chins read as *behind* rather than *below*:
a card the same width peeking under another reads as one shape with a
lip. The bottom radius drops ~3pt per depth for the same reason.

`IslandLayout` gains:

```swift
/// How far the deepest chin protrudes below the front card. Zero unless
/// the card stack is on AND more than one page is reachable — a stack of
/// one is just the island.
var chinReveal: CGFloat
```

The panel frame grows by `chinReveal` so the chins are not clipped. This
is the only frame change, and it happens on open, not per frame — the
power rule against animating window frames is not touched.

### Why three `NotchShape`s and not one path

CLAUDE.md: *one black `NotchShape` morphs between states; never cross-fade
two shapes.* The cards never cross-fade — they translate between depths,
and each is the same silhouette at a different offset. There remains one
shape vocabulary.

The alternative, growing `NotchShape.path(in:)` into stacked lips, was
rejected: the file is already flagged by swiftlint for size and
complexity, the shape must still morph to `.closed`, and a single path
cannot animate its lips independently of its body.

## 3. Cycling

`IslandPage.stepped(by:in:)` gains a wrapping sibling. The existing
method is unchanged and still the one used when the stack is off, so
clamping behaviour is byte-identical with the feature unselected.

```swift
func cycled(by delta: Int, in available: [IslandPage]) -> IslandPage
```

Index arithmetic modulo `available.count`, negative-safe. With two pages
reachable (the idle island, where `.agenda` drops out) a wrap of ±1 is
the same page either way, which is correct — two pages cycle by
alternating.

Motion falls out of depth rather than being choreographed. Each card
computes its depth from `store.islandPage`; the page change happens
inside `withAnimation(Motion.morph)`, so every card springs to its new
depth together. The outgoing front card travels to the back of the stack
and fades; the depth-1 chin rises into the front position. One animated
property, not three coordinated transitions.

Scroll up and scroll down are the same call with the sign flipped, so
the cycle is symmetric by construction.

## 4. Tint

`IslandPage` gains a `tint`. Chins carry it at full strength — at 9pt of
visible lip there is not much to read, so a subtle tint is no tint.

- `.agenda` — a light glassy lip, `.ultraThinMaterial` over black
- `.home` — neutral; whatever the activity already is
- `.usage` — warm orange over black, matching the badge's own marks

The **front card stays pure black by default.** `NotchRootView` records
two prior attempts at a non-black surface that both failed: an
`NSVisualEffectView` material washed out to grey against a bright
wallpaper, and a blurred bleed painted outside the silhouette. A tinted
front card also becomes the island's resting colour, so the island would
close in whatever colour the last-viewed page had.

Tinting the front card is therefore its own opt-in
(`NewFeatures.islandStackTint`), off by default, enabled in Settings only
while the stack style is selected. Turning it on is how the full-colour
version gets seen on hardware without committing to it.

## 5. Reveal and retraction

**Reveal.** The island opens with today's spring showing one clean card.
After a delay the chins slide out from behind it. A single `Task`,
cancelled on collapse — the pattern `hoverIntentTask` already uses. No
timer, no polling.

`Dwell.stackReveal` (600ms) is the default; a Settings slider overrides
it. The slider's floor of 0 means "chins are there from the start", which
is a real configuration rather than a degenerate one.

**Retraction, before collapse.** The chins retract behind the front card
first (~120ms), *then* the island collapses with its existing spring.

This order is load-bearing. The 2026-09-19 motion pass found that
`setFrame` firing while geometry was still protruding clipped the
still-moving corners — `.logicallyComplete` landing 117ms before the
spring did. Chins are the same failure at larger scale: the frame must
never be smaller than what is drawn. Collapsing first would clip them.

## 6. Settings

Both controls go in the **New Features** tab.

**Paging style** — a picker, not a toggle:

```
( ) Cross-fade    Pages swap in place inside one box.
(•) Card stack    Adjacent pages peek below; the stack cycles.
```

A picker rather than two booleans because `islandStack` and
`islandStackTint` as independent flags give four states, one of which
(tint on, stack off) means nothing.

`Preferences.pagingStyleKey`, backed by a `PagingStyle` enum whose
`.crossFade` case is what an unwritten or unrecognised key resolves to —
the same construction as `NotchScreenChoice`. §2.1's guarantee
("unwritten key *is* today's behaviour") holds structurally, exactly as
it does for `bool(forKey:)`.

It goes in `Preferences`, not `NewFeatures`. `NewFeatures` earns its
guarantee from every member being a bool with no default; one member that
is a string would weaken what `NewFeaturesTests` pins. `islandStackTint`
*is* a bool and stays in `NewFeatures`.

**Chin reveal delay** — a slider, 0–1500ms, beside the existing hover
delay slider so the two dwell controls sit together.
`Preferences.stackRevealDelayKey`, same shape as
`hoverIntentDelayKey`.

**Both new keys go in `Preferences.ownKeys`.** This is the bug the
2026-09-23 audit found for `launchGroupsKey`: a key declared beside its
neighbours but never added to `resettableKeys` survives a restore, and
`PreferencesRestoreTests` iterates that list, so the omission is
invisible to the test. Keys and list entries land in the same commit.

## 7. Music

The stack shows while music is playing. The player is the page most
often on screen and hiding the affordance there would make the deck feel
conditional.

## 8. Tests

- `IslandPageCycleTests` — wrap in both directions; three pages and two;
  `stepped` still clamps, unchanged, so the off path is pinned
- `IslandStackTests` — depth per page for each front page; `chinReveal`
  is 0 with fewer than two pages available and 0 with the style set to
  cross-fade
- `PagingStyleTests` — unwritten key resolves `.crossFade`; an
  unrecognised string does too
- `PreferencesRestoreTests` — already iterates `resettableKeys`; covers
  both new keys once they are listed
- `NewFeaturesTests` — already iterates `NewFeatures.all`; covers
  `islandStackTint`'s default-off

## 9. Deliberately out of scope

- **Dragging the stack.** Scroll cycles it; a drag that follows the
  finger and rubber-bands is a second gesture system, and the existing
  vertical scroll already has a 1.25x direction lock protecting the
  track-change swipe.
- **Tapping a chin to jump to it.** The panel is non-activating and the
  chins are 9pt tall. Scroll reaches every page in at most one step.
- **More than two chins.** Three pages exist; a fourth would need the
  depth table extended, not redesigned.
- **Per-page tint customisation in Settings.** Three tints, chosen to
  match what each page already shows.

## 10. Uncertain until hardware

- Whether 9pt of lip is enough to read a tint against a bright wallpaper.
  The inset and the reveal are constants, tunable in one place.
- Whether the retract beat reads as deliberate or as lag. If it drags,
  the retraction overlaps the collapse's first frames rather than
  preceding them outright — still never letting the frame lead the
  geometry.
