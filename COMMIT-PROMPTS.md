# Commit prompts — pause collapse (2026-09-20)

Five blocks, in order. Paste each one whole into the terminal.
Delete this file once the commits are in.

---

## 1. Store accessor

```bash
git add Visor/Core/NotchStore.swift
git commit -F - <<'EOF'
feat(core): expose whether an activity kind is currently active

`activities` is private, so a service with a delayed deactivation had no
way to ask whether the island it is about to collapse is even up any
more. `isActive(_:)` answers that without handing out the dictionary.

The pause collapse in the next commit is the caller: the media adapter
re-emits on every position tick, so a collapse that re-armed per tick
would push its own deadline out forever.
EOF
```

---

## 2. The pause collapse

```bash
git add Visor/Features/NowPlaying/NowPlayingService.swift VisorTests/PauseCollapseTests.swift
git commit -F - <<'EOF'
feat(music): collapse the island when playback is paused

A paused track held the island open indefinitely, so pausing and walking
away left a player sitting over the notch with nothing playing. It now
collapses back to the bare notch 5s after a pause, and comes straight
back when playback resumes.

Ported from the reference's pause-hide timer, which uses the same 5s.
Its setting and its defer-while-expanded are deliberately left out: the
collapse is unconditional here.

The delay is the point. A pause is usually a step on the way to
something else — a skip, a seek, answering a call — and an island that
shuts the instant the audio stops flaps open and closed around every one
of them.

The track is *not* cleared, only `.nowPlaying` deactivated. That is what
keeps the transport row available: open the island by hand after it has
collapsed and there is still a play button to press. A track that
actually goes away is a different event and still clears through
`scheduleClear`, which now cancels the collapse on its way out.

This reverses the "playing or paused, the island is the player" rule in
the Progress log. Documented there rather than left to be rediscovered.
EOF
```

---

## 3. Lock panel follows suit

```bash
git add Visor/Features/LockScreen/LockScreenPanelManager.swift
git commit -F - <<'EOF'
fix(lockscreen): hide the media panel while playback is paused

The lock screen showed a full player for a track that was not playing,
which is the same thing the island itself no longer does.

Gated on the live track's `isPlaying` rather than on the cache, so
locking the Mac while already paused shows nothing instead of showing a
player for silence. The cache stays for what it was actually for: a
track that *ends* behind the lock screen does not blank the panel
mid-look.
EOF
```

---

## 4. Docs + version

```bash
git add CLAUDE.md project.yml
git commit -F - <<'EOF'
docs: record the pause collapse, and open 1.6 (13)

The pause collapse reverses a decision the Progress log states
outright, so the log says so rather than leaving the next reader to
find a rule the code no longer follows.

Also records the two fixes already in this branch — the restored
SkyLight pin and the wider insets — with what was actually wrong in
each, since both were previously fixed on a wrong theory.

Adds a Releases section: every build lands in new-releases/ as its own
dmg, old builds are never deleted or overwritten, and the version is
bumped before building so each dmg carries its own.
EOF
```

---

## 5. Release build

Build first — the dmg filename embeds `HEAD`, so this has to follow the
commits above:

```bash
bash scripts/make-dmg.sh
```

Then commit it, substituting the filename the script prints:

```bash
git add new-releases/Visor-1.6\(13\)-*.dmg
git commit -F - <<'EOF'
release: Visor 1.6 (13)

Release build of the pause collapse. Ad-hoc signed, so it quarantines
on any other Mac — see docs/RESEARCH.md §0 Distribution.
EOF
```
