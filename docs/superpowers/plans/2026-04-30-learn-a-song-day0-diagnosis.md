# Day-0 Diagnosis: Broken Play Along Path

**Date:** 2026-04-30
**Status:** Root cause identified

---

## 1. Exact Symptom

Tapping "Play Along" from `SongDetailView` opens the full-screen cover correctly
(`PlayAlongSceneHost` -> `SongPlayAlongView`), `loadSong` runs, and the view
appears in `.idle` state with **zero note events**. Tapping the play button does
nothing because `startScheduling()` silently exits at its `guard !noteEvents.isEmpty`
check. No error is shown to the user. No console error is logged for the notation
mismatch because the `loadSong` code path treats it as a successful load.

## 2. Root Cause

**File:** `SurVibe/Playback/NoteEvent.swift`, line 126
**File:** `SurVibe/Resources/SeedContent/seed-songs.json`

The chain breaks in two places that conspire together:

### 2a. Data defect: notation array length mismatch in seed data

The only seed song ("Jana Gana Mana") has **118 sargam notes** but **130 western
notes** (12 extra). This mismatch has been present since the v7/v8 seed content
update that re-imported Jana Gana Mana with "official notation in G major."

### 2b. Silent empty-array return in `NoteEvent.fromNotation`

```swift
// NoteEvent.swift:126
guard sargamNotes.count == westernNotes.count else {
    return []   // <-- silently returns empty array, no logging
}
```

This guard silently returns `[]` instead of logging the mismatch or throwing an
error. The caller (`PlaybackCoordinator.loadSong`, line 188) receives an empty
array and treats the load as successful (`result = true`), setting
`playbackState = .idle` with zero `noteEvents`.

### 2c. The silent cascade

The full chain of silent failures:

1. `PlaybackCoordinator.loadSong` enters the `else if` notation branch (both
   `decodedSargamNotes` and `decodedWesternNotes` are non-nil).
2. `NoteEvent.fromNotation` returns `[]` (count mismatch guard).
3. `loadSong` sets `noteEvents = []`, `duration = 0` (no last event), and
   returns `true`.
4. `PlayAlongViewModel.loadSong` proceeds: configures raga context, requests
   mic permission, starts input detection, starts audio engine for playback.
5. State is `.idle` with 0 note events. The UI renders correctly but there is
   nothing to play.
6. User taps play -> `startSession` -> `startScheduling`:
   ```swift
   // PlaybackCoordinator.swift:249
   guard !noteEvents.isEmpty else { return }  // exits silently
   ```
7. Nothing happens. No error, no feedback.

### Why user-imported songs also break

`SongImportViewModel` and `ContentImportManager` both use the same
`NoteEvent.fromNotation` path. Any user-imported MusicXML or JSON where the
sargam and western arrays differ in length will hit the same silent failure.

## 3. Classification

**This is a two-line data fix + a one-line logging fix (option a).**

The deep rewrite planned in the spec (MusicXML pipeline, Verovio rendering, etc.)
is orthogonal. The immediate fix is:

1. **Fix the seed data:** Align the sargam and western notation arrays in
   `seed-songs.json` so they have the same count (either trim the 12 extra
   western notes or add the 12 missing sargam notes).
2. **Add logging:** In `NoteEvent.fromNotation`, log a warning when the guard
   fails so this class of bug is immediately visible in diagnostics.
3. **Optional but recommended:** Have `PlaybackCoordinator.loadSong` check for
   empty `noteEvents` after the notation branch and transition to `.error`
   instead of `.idle`, so the user sees "No playable notation found" instead of
   a dead play button.

## 4. Recommendation

**Fix now (before the deep rewrite):**

- Align the seed data arrays (most likely: add the 12 missing sargam notes to
  match the 130 western notes, since v7 was explicitly "official notation").
- Add a log + error transition in `loadSong` when `noteEvents` is empty after
  the notation branch.
- Bump `SeedContentLoader.currentContentVersion` to 9 to force re-import.

**The deep rewrite (MusicXML + Verovio + server-side pipeline)** is still the
right long-term plan because it eliminates the dual-array problem entirely.
Single-source-of-truth notation means no more count mismatches. But the one-line
fix unblocks Play Along for the existing seed song immediately.

## 5. Files Examined

| File | Role |
|------|------|
| `SurVibe/Songs/SongDetailView.swift` | Entry point: sets `showPlayAlong = true` |
| `SurVibe/PlayAlong/PlayAlongSceneHost.swift` | Creates VM, passes song to `SongPlayAlongView` |
| `SurVibe/PlayAlong/SongPlayAlongView.swift` | `.task` calls `viewModel.loadSong(song)` |
| `SurVibe/PlayAlong/PlayAlongViewModel.swift` | Facade: delegates to `playback.loadSong(song)` |
| `SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift` | `loadSong` enters notation branch, gets 0 events |
| `SurVibe/Playback/NoteEvent.swift:126` | **ROOT CAUSE** — `guard sargamNotes.count == westernNotes.count else { return [] }` |
| `SurVibe/PlayAlong/Coordinators/NoteRouter.swift` | Not reached in failure path |
| `SurVibe/Resources/SeedContent/seed-songs.json` | **DATA DEFECT** — 118 sargam vs 130 western notes |
| `SurVibe/Models/Song.swift` | Song model with `decodedSargamNotes`/`decodedWesternNotes` |

## 6. Recent Commits

The regression was introduced by the v7/v8 seed content update (Jana Gana Mana
"official notation in G major") which created the 118/130 mismatch. The triage
commits (`0002ef5`, `e3bf09f`) added diagnostic logging to the PlayAlong setup
path but did not examine the NoteEvent factory or seed data.
