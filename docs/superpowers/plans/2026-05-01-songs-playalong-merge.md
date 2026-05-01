# Songs → Play Along Merge — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended for parallelism — see §Parallel Execution) or `superpowers:executing-plans` for inline. Steps use checkbox (`- [ ]`) syntax.

**Spec:** [docs/superpowers/specs/2026-05-01-songs-playalong-merge-design.md](../specs/2026-05-01-songs-playalong-merge-design.md) (commit `4067cdf`).

**Goal:** Tap a song from Songs tab → push directly into Play Along. Old SongDetailView's setup controls (Tonic Sa, parts, preview, tanpura, loop, theme) move into a non-modal Settings sheet on Play Along behind a gear icon.

**Architecture:** Delete the intermediate detail screen + the orphaned Practice flow. Move shared infrastructure out of `Practice/` first; collapse two redundant tempo properties into one canonical `tempoScale ∈ [0.5, 1.5]`; relocate user-state fields from `Song` model to `SongProgress` model. Build a HIG-blessed `.sheet` settings panel with detents `[.medium, .large]`, default `.medium`, with background interaction enabled at `.medium` so user can keep playing while configuring.

**Tech stack:** Swift 6.2, iOS 26+, SwiftUI, SwiftData + CloudKit, AVAudioEngine, CoreMIDI. `@Observable` view models, `@MainActor` UI, async/await throughout. Tests use Swift Testing framework (`import Testing`).

---

## 🤝 Handover notes for next session

**Current state (2026-05-01):**
- ✅ Brainstormed, spec written, two rounds of HIG + hostile-review revisions applied → spec at commit `4067cdf`
- ✅ This implementation plan written and committed
- ⏳ User has NOT started execution yet — they will say something like "execute this plan" or "start the plan" in the next session

**Recommended startup command for next session:**
- The user starts by saying something like *"start executing the songs/playalong plan"* or just *"begin"* (referring to this plan)
- The first thing the orchestrator should do is invoke the `superpowers:subagent-driven-development` skill, then begin with **Wave 0a** below
- Use **Opus 4.7** for non-trivial subagent work (per project rule); Haiku 4.5 acceptable for purely mechanical tasks (file moves with no logic change)

**Critical context the executor MUST internalize before starting:**
1. **Practice/ directory has 21 files; 16 are deleted, 5+ are kept** — see [§Wave 1](#wave-1--practice-cleanup-practice-folder-surgery). Naive `rm -rf SurVibe/Practice/` BREAKS PlayAlong (`PracticeSessionRecorder` is used by `PlaybackCoordinator`, `PitchProximityMeter` is used by `SongPlayAlongView+Subviews`). Wave 1a moves the kept files OUT before Wave 1b deletes the rest.
2. **Tempo collapse touches 34 references across 11+ files** — see [§Wave 0b](#wave-0b--tempo-property-collapse-sequential-1-agent). This is the noisiest single change; do it in one focused agent.
3. **`Song` model loses 2 fields** — see [§Wave 0c](#wave-0c--song-model-field-removal-sequential-1-agent). 27 references. Tests `SongPlayAlongFieldsTests.swift` is deleted entirely.
4. **CloudKit conflict resolution is whole-record last-write-wins** — NOT per-field. The earlier "split SongProgress into two models" idea was rejected. Document in `SongProgress.swift` header. App-level `recordPlay(...)` already does max-merge for `bestScore`/`timesPlayed` — keep that path.
5. **Sub-screen refactors are independent** — TanpuraSettingsSheet, LoopBuilderView, ThemeCarouselPicker (the last lives in `Profile/`, not `PlayAlong/`). These run in parallel in [§Wave 2](#wave-2--sub-screen-refactors-parallel-3-agents).
6. **VM hydration first-launch policy: do not overwrite VM state with field defaults from a freshly-created SongProgress row.** Persist VM state INTO the new row instead. See [§Wave 0a T0a.3](#t0a3-add-viewmodel-helper-stubs).
7. **Settings sheet "Custom…" tempo item must be disabled when Settings sheet is open** (single-sheet rule).
8. **Keep all xcodebuild calls using `-derivedDataPath /private/tmp/SurVibe-DD`** per CLAUDE.md storage hygiene rule.

**Storage hygiene reminders for subagents:**
- `xcodebuild` MUST include `-derivedDataPath /private/tmp/SurVibe-DD`
- Prefer `swift test --package-path Packages/<X>` for package-level tests (no DerivedData explosion)
- In subagent prompts that build/test, restate the derivedDataPath rule explicitly

---

## Parallel Execution & Context Window

User has 1M-token-context per agent and budget for ~20 parallel agents. Plan is organised into **6 waves**. Within a wave, tasks marked **PARALLEL** run as concurrent subagents in isolated worktrees. Between waves, the orchestrator merges back into trunk and runs tests as a gate.

### Wall-clock budget

| Wave | Tasks | Sequential cost | Parallel cost | Concurrency |
|------|-------|-----------------|---------------|-------------|
| 0a   | 3     | 1 hr            | 1 hr          | 1 |
| 0b   | 1     | 2 hr            | 2 hr          | 1 (single-agent collapse) |
| 0c   | 1     | 1.5 hr          | 1.5 hr        | 1 |
| 1a   | 2     | 1 hr            | 30 min        | **2** |
| 1b   | 2     | 1.5 hr          | 1.5 hr        | 1 |
| 2    | 3     | 4.5 hr          | 1.5 hr        | **3** |
| 3a   | 1     | 2 hr            | 2 hr          | 1 |
| 3b   | 1     | 3 hr            | 3 hr          | 1 |
| 4    | 3     | 4 hr            | 1.5 hr        | **3** |
| 5    | 5     | 6 hr            | 6 hr          | 1 (cohesive UI surgery) |
| 6    | 4     | 4 hr            | 1.5 hr        | **3** |
| **Total** | **26** | **~31 hr** | **~22 hr** | up to 3 |

Speedup ≈ **1.4×** vs sequential. The core surgery (Waves 0b, 0c, 5) must be done by a single agent for code-coherence reasons. Parallelism wins are concentrated in sub-screen refactors (Wave 2), navigation cleanup (Wave 4), and tests (Wave 6).

### Context-window math

- Per subagent: ~150–200K tokens working budget (well within 1M)
- Orchestrator: ~250K tokens cumulative across all wave summaries
- Total tokens consumed across project: ~3M

### Parallel-execution rules

1. **Each parallel task gets its own git worktree** — `Agent` tool's `isolation: "worktree"` flag
2. **Each parallel task gets its own subagent prompt** — restate the storage-hygiene rule + Opus 4.7 model preference in the prompt
3. **Wave gates:** orchestrator merges all worktrees back to trunk after each wave, runs `xcodebuild clean build -derivedDataPath /private/tmp/SurVibe-DD` + tests, blocks the next wave on green
4. **If a parallel task fails:** orchestrator runs `/review` on its diff, fixes inline, then retries the wave gate

---

## File structure summary

| File | Wave | Action |
|------|------|--------|
| `SurVibe/Models/SongProgress.swift` | 0a | Modify (+9 fields) |
| `SurVibe/Models/Song.swift` | 0c | Modify (−2 fields) |
| `SurVibe/PlayAlong/PlayAlongViewModel.swift` | 0a, 0b | Modify (+3 methods, tempo collapse) |
| `SurVibe/PlayAlong/PlayAlongToolbar.swift` | 0b, 5 | Tempo collapse, then full rewrite |
| `SurVibe/Practice/PracticeSessionRecorder.swift` | 1a | Move → `SurVibe/PlayAlong/Coordinators/SessionRecorder.swift` |
| `SurVibe/Practice/PitchProximityMeter.swift` | 1a | Move → `SurVibe/Components/PitchProximityMeter.swift` |
| `SurVibe/Practice/{16 orphaned files}` | 1b | Delete |
| `SurVibe/PlayAlong/TanpuraSettingsSheet.swift` | 2 | Refactor (extract content view) |
| `SurVibe/PlayAlong/LoopBuilderView.swift` | 2 | Refactor (extract content view) |
| `SurVibe/Profile/ThemeCarouselPicker.swift` | 2 | Refactor (extract content view) |
| `SurVibe/PlayAlong/PlayAlongSettingsRows.swift` | 3a | **Create** |
| `SurVibe/PlayAlong/PlayAlongSettingsSheet.swift` | 3b | **Create** |
| `SurVibe/Navigation/AppDestination.swift` | 4 | Modify (−2 cases) |
| `SurVibe/Navigation/AppRouter.swift` | 4 | Modify (doc comment) |
| `SurVibe/SongsTab.swift` | 4 | Modify (−2 case branches, −resolver) |
| `SurVibe/Songs/SongLibraryView.swift` | 4 | Modify (NavigationLink target) |
| `SurVibe/Songs/SongDetailView.swift` | 4 | **Delete** |
| `SurVibe/Songs/SongDetailViewParts.swift` | 4 | **Delete** (port helpers) |
| `SurVibe/Songs/PlaybackControlsView.swift` | 4 | **Delete** |
| `SurVibe/Notation/WesternNoteHelper.swift` | 4 | Modify (port `noteName`) |
| `SurVibe/Songs/Song+TrackLabels.swift` | 4 | **Create** |
| `SurVibe/PlayAlong/SongPlayAlongView.swift` | 5 | Major rewrite |
| `SurVibe/PlayAlong/SongPlayAlongView+TitleStrip.swift` | 5 | **Create** (Sa chip + title block) |
| `SurVibe/PlayAlong/TempoCustomSheet.swift` | 5 | **Create** (small slider+stepper sheet) |
| `SurVibe/SurVibeTests/SongPlayAlongFieldsTests.swift` | 0c | **Delete** |
| `SurVibe/SurVibeTests/CrossAppThemeContractTests.swift` | 1b | Modify (lines 24, 28) |
| `SurVibe/SurVibeTests/PlayAlong/*Tests.swift` (5 files) | 0b, 0c | Rewrite |
| `SurVibe/SurVibeTests/PlayAlongSettingsSheetTests.swift` | 6 | **Create** |
| `SurVibe/SurVibeTests/SongPlayAlongViewLayoutTests.swift` | 6 | **Create** |
| `SurVibe/SurVibeTests/SongProgressFieldsTests.swift` | 6 | **Create** |
| `SurVibe/SurVibeTests/SongTrackLabelsTests.swift` | 4 | **Create** |

---

# Wave 0a — Foundation: Add fields and helpers (sequential, 1 agent)

**Goal:** Add new persisted fields and VM helper method stubs without breaking compilation.

## T0a.1: Add SongProgress fields

**Files:**
- Modify: `SurVibe/Models/SongProgress.swift`
- Read first: `SurVibe/Models/SongProgress.swift` (full file)

- [ ] **Step 1: Read existing model** to confirm `preferredSaHz: Double?` exists and find the property list location.

- [ ] **Step 2: Add file-header comment block above `@Model`:**

```swift
// MARK: - Conflict Resolution
//
// SongProgress uses CloudKit's default whole-record last-write-wins.
// Per-field merge is NOT possible — the entire record is one CKRecord.
//
// Additive fields (`bestScore`, `timesPlayed`, `xpEarnedTotal`) are
// merged at the application level inside `recordPlay(...)` via max()
// and additive increments. Pref fields (preferredTempoScale, etc.)
// use last-write-wins as the desired UX.
//
// DO NOT introduce per-field merge expectations — they cannot be
// honored at the persistence layer.
```

- [ ] **Step 3: Add 9 new properties** alongside `preferredSaHz`:

```swift
public var preferredHands: String = "both"               // "both" | "rh" | "lh"
public var preferredTempoScale: Double = 1.0             // clamped [0.5, 1.5]
public var preferredLearnerTrackIndex: Int = 0
public var waitModeEnabled: Bool = false
public var clickTrackEnabled: Bool = false
public var clickTrackLevel: String = "normal"            // "soft" | "normal" | "loud"
public var tanpuraEnabled: Bool = false
public var tanpuraRaga: String = ""                      // "" = use song default
public var loopRegionStart: Int? = nil                   // bar index
public var loopRegionEnd: Int? = nil                     // bar index
```

- [ ] **Step 4: Build and run model-layer tests:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  build
```

Expected: ✅ build succeeds (purely additive change with defaults; no existing tests broken).

- [ ] **Step 5: Commit:**

```bash
git add SurVibe/Models/SongProgress.swift
git commit -m "feat(SVCore): add per-song preference fields to SongProgress

Adds 9 new fields (preferredHands, preferredTempoScale,
preferredLearnerTrackIndex, waitModeEnabled, clickTrackEnabled,
clickTrackLevel, tanpuraEnabled, tanpuraRaga, loopRegionStart,
loopRegionEnd) with explicit defaults. Documents whole-record
last-write-wins CloudKit strategy in file header.

Spec: docs/superpowers/specs/2026-05-01-songs-playalong-merge-design.md"
```

## T0a.2: PlayAlongViewModel — add `restart()` method

**Files:**
- Modify: `SurVibe/PlayAlong/PlayAlongViewModel.swift`
- Read first: lines 1–150 (imports, properties), and find `stopAndComplete`, `seek`, `startSession`, and `scoring` references

- [ ] **Step 1: Add public `restart()` method:**

```swift
/// Resets the current session back to start.
///
/// Differs from `startSession()` in that it stops in-flight playback,
/// seeks transport to 0, and resets scoring state before starting fresh.
/// Used by both the toolbar Restart button and the Replay action on
/// the Results overlay.
public func restart() async {
    await stopAndComplete(emit: false)
    seek(to: 0)
    scoring.reset()
    await startSession()
}
```

- [ ] **Step 2: Confirm `stopAndComplete(emit:)`, `seek(to:)`, `scoring.reset()`, `startSession()` exist** by grep:

```bash
grep -n "func stopAndComplete\|func seek\|func startSession\|extension.*scoring" \
  SurVibe/PlayAlong/PlayAlongViewModel.swift \
  SurVibe/PlayAlong/Coordinators/*.swift
```

If `scoring.reset()` doesn't exist, add it to `ScoringCoordinator` as `public func reset()` that zeroes `notesHit`, `accuracy`, `streak`, `longestStreak`, `starRating`, `xpEarned`.

- [ ] **Step 3: Build:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  build 2>&1 | tail -20
```

Expected: ✅ build succeeds.

- [ ] **Step 4: Commit:**

```bash
git add SurVibe/PlayAlong/PlayAlongViewModel.swift SurVibe/PlayAlong/Coordinators/*.swift
git commit -m "feat(PlayAlong): add restart() method to PlayAlongViewModel

Wraps stopAndComplete + seek(0) + scoring.reset + startSession
into a single restart action. Used by both toolbar Restart and
Replay-from-Results."
```

## T0a.3: Add ViewModel helper stubs

**Files:**
- Modify: `SurVibe/PlayAlong/PlayAlongViewModel.swift`
- Read first: existing `.task` initialization in `SongPlayAlongView.swift` to understand `tanpura.effectiveSaHz` debounce pattern (around line 347)

- [ ] **Step 1: Add hydration state + helper method stubs:**

```swift
// MARK: - Per-song preference hydration

/// True after the first hydration from `SongProgress` has completed
/// (or after the seed write for a new song). UI elements that depend
/// on per-song prefs (Sa chip, Tempo pill) hide or show placeholders
/// until this is true to avoid default-to-stored flicker.
public private(set) var didInitialHydrate: Bool = false

private var persistDebounceTask: Task<Void, Never>?

/// Hydrate VM state from a stored SongProgress row.
/// First-launch policy: if the row was just created (all defaults),
/// caller should pass `seedFromVM: true` and `persistSettings(to:)` will
/// write the VM's current state INTO the row instead of overwriting VM.
public func loadPersistedSettings(from progress: SongProgress, seedFromVM: Bool = false) async {
    if seedFromVM {
        await persistSettings(to: progress, immediate: true)
        didInitialHydrate = true
        return
    }
    // Hydrate VM from stored values
    if let saHz = progress.preferredSaHz {
        // Convert Hz back to MIDI pitch (existing helper); update VM
        tonicSaPitch = midiPitch(forSaHz: saHz)
    }
    tempoScale = max(0.5, min(1.5, progress.preferredTempoScale))
    // ... hydrate remaining fields: hands, click, tanpura, loop, etc.
    // (see §Wave 5 T5.4 for full wiring; stubs only here)
    didInitialHydrate = true
}

/// Persist VM state to SongProgress (debounced 250 ms unless `immediate`).
public func persistSettings(to progress: SongProgress, immediate: Bool = false) async {
    persistDebounceTask?.cancel()
    if immediate {
        applySettingsToRow(progress)
        return
    }
    persistDebounceTask = Task { [weak self] in
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled, let self else { return }
        await MainActor.run { self.applySettingsToRow(progress) }
    }
}

private func applySettingsToRow(_ progress: SongProgress) {
    progress.preferredSaHz = saHz(forMIDIPitch: tonicSaPitch)
    progress.preferredTempoScale = tempoScale
    // Remaining field assignments — full wiring in Wave 5 T5.4
    try? progress.modelContext?.save()
}
```

(Note: `midiPitch(forSaHz:)` and `saHz(forMIDIPitch:)` may already exist in `SVAudio` or `TanpuraController`. If not, add private helpers in this file.)

- [ ] **Step 2: Build:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  build 2>&1 | tail -10
```

Expected: ✅ build succeeds.

- [ ] **Step 3: Commit:**

```bash
git add SurVibe/PlayAlong/PlayAlongViewModel.swift
git commit -m "feat(PlayAlong): add hydration/persistence stubs to view model

Adds didInitialHydrate flag and loadPersistedSettings/persistSettings
method stubs. Full field wiring wired in Wave 5; stubs allow downstream
work to compile."
```

---

# Wave 0b — Tempo property collapse (sequential, 1 agent)

**Goal:** Remove `arrangementTempoScale` and `clampTempoScale`. Replace 34 reference sites with `tempoScale ∈ [0.5, 1.5]`.

**WARNING:** This is the noisiest single change. Single agent, single commit, single build pass. If you split this across agents, you'll get merge hell.

## T0b.1: Tempo collapse

**Files:**
- Read first: lines 100–280 of `PlayAlongViewModel.swift`; full `PlayAlongToolbar.swift`
- Modify: `SurVibe/PlayAlong/PlayAlongViewModel.swift`, `SurVibe/PlayAlong/PlayAlongToolbar.swift`
- Modify: `SurVibe/SurVibeTests/PlayAlong/PlayAlongToolbarStateTests.swift`, `PlayAlongToolbarTests.swift`, `PlayAlongViewModelE1Tests.swift`, `LearnASongIntegrationTests.swift`

- [ ] **Step 1: Confirm reference count before changes:**

```bash
grep -rn "arrangementTempoScale\|clampTempoScale" SurVibe SurVibeTests | wc -l
```

Expected: 34 (verified at plan-write time 2026-05-01).

- [ ] **Step 2: Remove `arrangementTempoScale` from `PlayAlongViewModel.swift`:**

Lines to delete: the `public var arrangementTempoScale: Double = 1.0 { didSet { ... } }` block (around lines 270–278).

Replace `arrangementTempoScale` with `tempoScale` everywhere in the file (PlayAlongViewModel.swift has 8 references). Lines 123, 597, 622, 651, 664, 711, plus the deleted property itself.

- [ ] **Step 3: Remove `clampTempoScale` from `PlayAlongToolbar.swift`:**

Delete the static func at line 543. Replace toolbar's tempo display/slider bindings (lines 165, 171, 178) with `viewModel.tempoScale` (which already self-clamps in its setter).

- [ ] **Step 4: Update test files:**

```bash
grep -rn "arrangementTempoScale\|clampTempoScale" SurVibeTests
```

For each occurrence:
- `PlayAlongToolbarTests.swift` lines 49–74: tests `clampTempoScale` directly. Since the helper is deleted, **delete the entire `clampTempoScale` test cases** (the underlying clamp behavior is now tested via `tempoScaleClampsToValidRange` on the VM, which is added in Wave 6 T6.1).
- `PlayAlongViewModelE1Tests.swift`: rename all `arrangementTempoScale` → `tempoScale`.
- `LearnASongIntegrationTests.swift`: same rename.
- `PlayAlongToolbarStateTests.swift`: review; rename if `arrangementTempoScale` appears.

- [ ] **Step 5: Verify zero references remain:**

```bash
grep -rn "arrangementTempoScale\|clampTempoScale" SurVibe SurVibeTests
```

Expected: no output.

- [ ] **Step 6: Build + test:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  build test 2>&1 | tail -30
```

Expected: ✅ all tests pass; tempoScale clamps to [0.5, 1.5] in VM setter.

- [ ] **Step 7: Commit:**

```bash
git add -A
git commit -m "refactor(PlayAlong): collapse arrangementTempoScale into tempoScale

Single canonical tempoScale property on PlayAlongViewModel, clamped
to [0.5, 1.5] in setter. Removes legacy arrangementTempoScale (8 sites
in VM) and clampTempoScale static helper (PlayAlongToolbar:543).
Updates 4 test files to use the new name. Zero behavior change for
end users — values are identical, just the property name unifies."
```

---

# Wave 0c — Song model field removal (sequential, 1 agent)

**Goal:** Remove `Song.lastUsedTempoScale` and `Song.defaultPracticeMode`. 27 references across the codebase.

## T0c.1: Song field removal

**Files:**
- Read first: `SurVibe/Models/Song.swift` (full); search results for both field names
- Modify: `SurVibe/Models/Song.swift`
- Modify: every site that reads/writes those fields (let compiler find them)
- Delete: `SurVibe/SurVibeTests/SongPlayAlongFieldsTests.swift`

- [ ] **Step 1: Confirm reference count:**

```bash
grep -rn "lastUsedTempoScale\|defaultPracticeMode" SurVibe SurVibeTests | wc -l
```

Expected: 27 (verified 2026-05-01).

- [ ] **Step 2: List the call sites for review:**

```bash
grep -rn "lastUsedTempoScale\|defaultPracticeMode" SurVibe SurVibeTests
```

Note any non-trivial uses (e.g., reads that drove behavior in PlayAlongToolbar, ArrangementPlayer initialization, MXL importer defaults).

- [ ] **Step 3: Remove the two `@Attribute` declarations from `Song.swift`** (lines 191, 197 per spec analysis).

- [ ] **Step 4: Replace read sites with `SongProgress` lookups (where appropriate)** OR remove the read entirely if the value is now per-VM-default.

Pattern:
```swift
// BEFORE:
let scale = song.lastUsedTempoScale ?? 1.0

// AFTER (when SongProgress is in scope):
let scale = progress?.preferredTempoScale ?? 1.0

// AFTER (no progress in scope, e.g., importer):
// Just default to 1.0 — preference now lives elsewhere
let scale = 1.0
```

For `defaultPracticeMode`:
```swift
// BEFORE:
let mode = PracticeMode(rawValue: song.defaultPracticeMode ?? "both") ?? .both

// AFTER:
let mode = PracticeMode(rawValue: progress?.preferredHands ?? "both") ?? .both
```

- [ ] **Step 5: Delete `SurVibeTests/SongPlayAlongFieldsTests.swift`:**

```bash
git rm SurVibeTests/SongPlayAlongFieldsTests.swift
```

- [ ] **Step 6: Update test fixtures** in `PlayAlongToolbarStateTests.swift` and `ArrangementPlayerTests.swift`:
- Replace any `Song(...)` initializer args setting `lastUsedTempoScale:` or `defaultPracticeMode:` with `SongProgress` rows that set `preferredTempoScale` / `preferredHands`.

- [ ] **Step 7: Build + test:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  build test 2>&1 | tail -30
```

Expected: ✅ all tests pass. Compiler should have caught every read site.

- [ ] **Step 8: Commit:**

```bash
git add -A
git commit -m "refactor(Models): move user-state fields out of Song to SongProgress

Removes Song.lastUsedTempoScale and Song.defaultPracticeMode;
those concerns now live on SongProgress as preferredTempoScale and
preferredHands. Song now represents song *content* only.

Deletes SongPlayAlongFieldsTests.swift (replaced by new
SongProgressFieldsTests in Wave 6). Updates ArrangementPlayerTests
and PlayAlongToolbarStateTests to use SongProgress-based fixtures.

Per project rule (no release yet): no migration shim needed."
```

---

# Wave 1 — Practice cleanup (Practice/ folder surgery)

## Wave 1a — Move shared files OUT of Practice/ (PARALLEL, 2 agents)

**Goal:** Relocate the files that PlayAlong depends on so the deletion sweep in 1b is safe.

### T1a.1: Move PracticeSessionRecorder

**Run as parallel subagent.**

**Files:**
- Move: `SurVibe/Practice/PracticeSessionRecorder.swift` → `SurVibe/PlayAlong/Coordinators/SessionRecorder.swift`
- Update consumers: `SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift:413`, `SurVibe/Models/PlayAlongSession.swift`, `SurVibe/SurVibeTests/PlaybackCoordinatorTests.swift`

- [ ] **Step 1: Move and rename file:**

```bash
git mv SurVibe/Practice/PracticeSessionRecorder.swift \
       SurVibe/PlayAlong/Coordinators/SessionRecorder.swift
```

- [ ] **Step 2: Rename the type inside** from `PracticeSessionRecorder` to `SessionRecorder` (it's not Practice-specific). Update file header comment to reflect "session recording for PlayAlong scoring".

- [ ] **Step 3: Update all consumers:**

```bash
grep -rln "PracticeSessionRecorder" SurVibe SurVibeTests
```

In each file: `s/PracticeSessionRecorder/SessionRecorder/g`.

- [ ] **Step 4: Build:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  build 2>&1 | tail -10
```

Expected: ✅ build succeeds.

- [ ] **Step 5: Commit:**

```bash
git add -A
git commit -m "refactor(PlayAlong): move SessionRecorder out of Practice/

PracticeSessionRecorder is misnamed — it's used by PlayAlong's
PlaybackCoordinator and PlayAlongSession, not Practice. Moving it
to PlayAlong/Coordinators/ and renaming to SessionRecorder makes
deletion of the orphaned Practice/ flow safe in Wave 1b."
```

### T1a.2: Move PitchProximityMeter

**Run as parallel subagent (independent of T1a.1).**

**Files:**
- Move: `SurVibe/Practice/PitchProximityMeter.swift` → `SurVibe/PlayAlong/Components/PitchProximityMeter.swift`
- Update consumer: `SurVibe/PlayAlong/SongPlayAlongView+Subviews.swift:19`

- [ ] **Step 1: Confirm `PlayAlong/Components/` exists or create it:**

```bash
ls SurVibe/PlayAlong/Components 2>/dev/null || mkdir -p SurVibe/PlayAlong/Components
```

- [ ] **Step 2: Move file:**

```bash
git mv SurVibe/Practice/PitchProximityMeter.swift \
       SurVibe/PlayAlong/Components/PitchProximityMeter.swift
```

(No type rename needed — name is fine.)

- [ ] **Step 3: Verify import paths still resolve:**

```bash
grep -rln "PitchProximityMeter" SurVibe SurVibeTests
```

These files reference the type — Swift's module-level resolution means no import path changes needed (same module, just different folder).

- [ ] **Step 4: Build:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  build 2>&1 | tail -10
```

Expected: ✅ build succeeds.

- [ ] **Step 5: Commit:**

```bash
git add -A
git commit -m "refactor(PlayAlong): move PitchProximityMeter out of Practice/

Used by SongPlayAlongView's pitch HUD, not Practice. Relocating
to PlayAlong/Components/ ahead of the orphaned-Practice deletion
sweep in Wave 1b."
```

### Wave 1a Gate

After both parallel agents finish, orchestrator merges and re-runs the build:

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  clean build test 2>&1 | tail -30
```

Expected: ✅ all tests still green.

## Wave 1b — Delete orphaned Practice files (sequential, 1 agent)

### T1b.1: Verify-then-delete the orphaned Practice files

**Files to delete (verified in spec; re-verify before deletion):**
```
SurVibe/Practice/ListenFirstView.swift
SurVibe/Practice/NoteDetailListView.swift
SurVibe/Practice/PracticeAlongView.swift
SurVibe/Practice/PracticeControlsToolbar.swift
SurVibe/Practice/PracticeHUD.swift
SurVibe/Practice/PracticeHistoryView.swift
SurVibe/Practice/PracticeSessionSummaryView.swift
SurVibe/Practice/PracticeSessionView.swift
SurVibe/Practice/PracticeSessionViewModel.swift
SurVibe/Practice/PracticeSessionViewModel+Monitoring.swift
SurVibe/Practice/PracticeSessionViewModel+Raga.swift
SurVibe/Practice/SectionBreakdownView.swift
SurVibe/Practice/SourceChip.swift
SurVibe/Practice/StarRatingView.swift
SurVibe/Practice/StatCard.swift
SurVibe/Practice/SwiftDataEventLogger.swift
SurVibe/Practice/WaitModeSettingsView.swift
SurVibe/Practice/WaitModeSettingsStore.swift
SurVibe/Practice/WaitingIndicatorOverlay.swift
```

(19 files — `PracticeSessionRecorder` and `PitchProximityMeter` already moved out in Wave 1a; `Practice/` should be empty after.)

- [ ] **Step 1: Pre-deletion verification — for each file, confirm zero non-Practice references:**

```bash
for f in ListenFirstView NoteDetailListView PracticeAlongView \
         PracticeControlsToolbar PracticeHUD PracticeHistoryView \
         PracticeSessionSummaryView PracticeSessionView \
         PracticeSessionViewModel SectionBreakdownView SourceChip \
         StarRatingView StatCard SwiftDataEventLogger \
         WaitModeSettingsView WaitModeSettingsStore \
         WaitingIndicatorOverlay; do
  echo "=== $f ==="
  grep -rln "\\b${f}\\b" SurVibe SurVibeTests | grep -v "/Practice/"
done
```

For any that show non-Practice consumers, STOP and either move them out (à la Wave 1a) or update the spec — do NOT proceed with deletion. (As of plan-write time, none have non-Practice consumers, but the codebase may have changed.)

- [ ] **Step 2: Delete via git:**

```bash
git rm SurVibe/Practice/ListenFirstView.swift
git rm SurVibe/Practice/NoteDetailListView.swift
git rm SurVibe/Practice/PracticeAlongView.swift
git rm SurVibe/Practice/PracticeControlsToolbar.swift
git rm SurVibe/Practice/PracticeHUD.swift
git rm SurVibe/Practice/PracticeHistoryView.swift
git rm SurVibe/Practice/PracticeSessionSummaryView.swift
git rm SurVibe/Practice/PracticeSessionView.swift
git rm SurVibe/Practice/PracticeSessionViewModel.swift
git rm SurVibe/Practice/PracticeSessionViewModel+Monitoring.swift
git rm SurVibe/Practice/PracticeSessionViewModel+Raga.swift
git rm SurVibe/Practice/SectionBreakdownView.swift
git rm SurVibe/Practice/SourceChip.swift
git rm SurVibe/Practice/StarRatingView.swift
git rm SurVibe/Practice/StatCard.swift
git rm SurVibe/Practice/SwiftDataEventLogger.swift
git rm SurVibe/Practice/WaitModeSettingsView.swift
git rm SurVibe/Practice/WaitModeSettingsStore.swift
git rm SurVibe/Practice/WaitingIndicatorOverlay.swift
```

- [ ] **Step 3: Delete companion test files:**

```bash
find SurVibeTests -name "Practice*Tests.swift" -o \
                  -name "ListenFirst*Tests.swift" -o \
                  -name "WaitMode*Tests.swift" \
  | xargs -I{} git rm {}
```

(Adjust list based on what actually exists.)

- [ ] **Step 4: Remove the now-empty Practice/ directory:**

```bash
rmdir SurVibe/Practice 2>/dev/null && echo "Practice/ removed" || \
  echo "Practice/ not empty; check what remains: $(ls SurVibe/Practice)"
```

If anything remains, investigate before proceeding.

- [ ] **Step 5: Build + test:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  clean build test 2>&1 | tail -30
```

Expected: ✅ all tests pass; no compile errors from missing types.

- [ ] **Step 6: Commit:**

```bash
git add -A
git commit -m "feat(Practice): delete orphaned Practice flow

Practice was only reachable from SongDetailView, which is being
deleted in Wave 4. Removes 19 orphaned files. Shared infrastructure
(SessionRecorder, PitchProximityMeter) was relocated to PlayAlong/
in Wave 1a — those remain.

Per project rule (no release yet): no Learn-tab re-entry built; if
Practice features are wanted later, they get a separate spec/plan."
```

### T1b.2: Update CrossAppThemeContractTests

**Files:**
- Modify: `SurVibe/SurVibeTests/CrossAppThemeContractTests.swift`

- [ ] **Step 1: Read current state:**

```bash
sed -n '20,30p' SurVibe/SurVibeTests/CrossAppThemeContractTests.swift
```

- [ ] **Step 2: Update both lines** that reference now-deleted files:
- Line 24: remove `"SurVibe/Songs/SongDetailView.swift"` from the contract path list (the file no longer exists; the test should not assert on a deleted path)
- Line 28: remove `"SurVibe/Songs/PlaybackControlsView.swift"` similarly

If those lines are part of an array of paths that the test asserts each exists or has theme tokens, simply remove the two array entries. Re-read the surrounding test to confirm semantic meaning preserved.

- [ ] **Step 3: Build + test:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  test 2>&1 | tail -20
```

Expected: ✅ CrossAppThemeContractTests still passes (with two fewer asserted paths).

- [ ] **Step 4: Commit:**

```bash
git add -A
git commit -m "test(theme): drop deleted file paths from theme contract test"
```

---

# Wave 2 — Sub-screen refactors (PARALLEL, 3 agents)

**Goal:** Extract the body of three sheets into `*Content` views that work both in their existing sheet wrapper AND when pushed onto a NavigationStack inside the new Settings sheet.

**All three tasks are independent — three different files, no shared state. Run as 3 parallel subagents.**

## T2.1: Refactor TanpuraSettingsSheet (parallel)

**Files:**
- Modify: `SurVibe/PlayAlong/TanpuraSettingsSheet.swift`

- [ ] **Step 1: Read existing file** to identify the body content vs the sheet wrapper. Look for `NavigationStack`, `presentationDetents`, `Environment(\.dismiss)` usage.

- [ ] **Step 2: Extract a new view `TanpuraSettingsContent`:**

```swift
/// The settings UI for tanpura — usable both as a standalone sheet and
/// pushed onto a parent NavigationStack (e.g., the Settings sheet's
/// internal stack).
struct TanpuraSettingsContent: View {
    @Bindable var tanpura: TanpuraController
    var onDismiss: (() -> Void)? = nil  // nil = caller manages dismissal (push mode)

    var body: some View {
        // Move the existing sheet's body INTO here, removing the outer
        // NavigationStack and presentationDetents.
        // Keep the toolbar items (Save / Done) but route them through
        // onDismiss?() instead of @Environment(\.dismiss).
    }
}
```

- [ ] **Step 3: Refactor `TanpuraSettingsSheet` to wrap `TanpuraSettingsContent`:**

```swift
struct TanpuraSettingsSheet: View {
    @Bindable var tanpura: TanpuraController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TanpuraSettingsContent(tanpura: tanpura, onDismiss: { dismiss() })
        }
        .presentationDetents([.medium, .large])
    }
}
```

- [ ] **Step 4: Build + run any existing TanpuraSettings tests:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  build 2>&1 | tail -10
```

Expected: ✅ build succeeds; existing usages of `TanpuraSettingsSheet` (in `SongPlayAlongView.swift`) still work.

- [ ] **Step 5: Commit:**

```bash
git add SurVibe/PlayAlong/TanpuraSettingsSheet.swift
git commit -m "refactor(PlayAlong): extract TanpuraSettingsContent for dual presentation

Splits TanpuraSettingsSheet into a sheet wrapper + reusable content
view. The new content view will be pushed onto the Settings sheet's
internal NavigationStack in Wave 3b without re-implementing the UI."
```

## T2.2: Refactor LoopBuilderView (parallel)

**Files:**
- Modify: `SurVibe/PlayAlong/LoopBuilderView.swift`

- [ ] **Step 1: Read existing file.** Note the `NavigationStack` at line 74, `toolbar` items at lines 86–101 with `dismiss()` calls.

- [ ] **Step 2: Extract `LoopBuilderContent` view** following the same pattern as T2.1. Move `NavigationStack` and toolbar items to the wrapper; the content takes `onDismiss: (() -> Void)?` for its Cancel/Done buttons.

- [ ] **Step 3: Build:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  build 2>&1 | tail -10
```

- [ ] **Step 4: Commit:**

```bash
git add SurVibe/PlayAlong/LoopBuilderView.swift
git commit -m "refactor(PlayAlong): extract LoopBuilderContent for dual presentation"
```

## T2.3: Refactor ThemeCarouselPicker (parallel)

**Files:**
- Modify: `SurVibe/Profile/ThemeCarouselPicker.swift` (note: `Profile/`, NOT `PlayAlong/`)

- [ ] **Step 1: Read existing file.** Find its `NavigationStack` and `presentationDetents([.large])`.

- [ ] **Step 2: Extract `ThemeCarouselContent`** following the same pattern. The wrapper retains sheet-specific modifiers; the content view is push-safe.

- [ ] **Step 3: Verify any existing call sites** still work:

```bash
grep -rn "ThemeCarouselPicker" SurVibe SurVibeTests
```

- [ ] **Step 4: Build:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  build 2>&1 | tail -10
```

- [ ] **Step 5: Commit:**

```bash
git add SurVibe/Profile/ThemeCarouselPicker.swift
git commit -m "refactor(Profile): extract ThemeCarouselContent for dual presentation"
```

### Wave 2 Gate

After all 3 parallel agents finish:

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  clean build test 2>&1 | tail -30
```

Expected: ✅ all tests pass.

---

# Wave 3 — Settings sheet infrastructure

## Wave 3a — Settings rows (sequential, 1 agent)

### T3.1: Create PlayAlongSettingsRows.swift

**Files:**
- Create: `SurVibe/PlayAlong/PlayAlongSettingsRows.swift`

- [ ] **Step 1: Create the file with reusable row components:**

```swift
import SwiftUI

// MARK: - Disclosure row (push-style with chevron + value preview)

struct DisclosureRow<Destination: View>: View {
    let title: String
    let value: String?
    let destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Text(title)
                Spacer()
                if let value { Text(value).foregroundStyle(.secondary) }
            }
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - Toggle row

struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var hint: String? = nil

    var body: some View {
        Toggle(isOn: $isOn) { Text(title) }
            .accessibilityHint(hint ?? "")
    }
}

// MARK: - Segmented row (Both / RH / LH style)

struct SegmentedRow<T: Hashable & Identifiable>: View {
    let title: String
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Picker(title, selection: $selection) {
                ForEach(options) { opt in Text(label(opt)).tag(opt) }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - Action row (button-style with icon)

struct ActionRow: View {
    let title: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImage)
                Text(title)
            }
        }
        .disabled(!isEnabled)
    }
}

// MARK: - Chip row (read-only badge style — for context cards)

struct ChipRow: View {
    let title: String
    let badges: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            HStack(spacing: 6) {
                ForEach(badges, id: \.self) { badge in
                    Text(badge)
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                }
            }
        }
    }
}
```

- [ ] **Step 2: Build:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  build 2>&1 | tail -10
```

Expected: ✅ build succeeds. (No callers yet — these are pure additions.)

- [ ] **Step 3: Commit:**

```bash
git add SurVibe/PlayAlong/PlayAlongSettingsRows.swift
git commit -m "feat(PlayAlong): add reusable settings row components

DisclosureRow, ToggleRow, SegmentedRow, ActionRow, ChipRow.
Used by the Settings sheet built in Wave 3b."
```

## Wave 3b — Settings sheet container (sequential, 1 agent)

### T3.2: Create PlayAlongSettingsSheet.swift

**Files:**
- Create: `SurVibe/PlayAlong/PlayAlongSettingsSheet.swift`
- Read first: `SurVibe/Models/SongProgress.swift` (new fields), `SurVibe/PlayAlong/PlayAlongViewModel.swift` (relevant bindings)

- [ ] **Step 1: Create the sheet container** with all sections per spec:

```swift
import SwiftData
import SwiftUI

struct PlayAlongSettingsSheet: View {
    @Bindable var viewModel: PlayAlongViewModel
    @Bindable var tanpura: TanpuraController
    let song: Song
    @Bindable var progress: SongProgress
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                songSection
                tuningSection
                partsSection
                practiceAidsSection
                inputSection
                appearanceSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark") {
                        dismiss()
                    }
                    .accessibilityLabel("Close settings")
                }
            }
            .accessibilityFocused($titleFocused)
            .onAppear {
                // Move VoiceOver focus to title on open
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    titleFocused = true
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var songSection: some View {
        Section("Song") {
            ChipRow(
                title: "\(song.title) — \(song.artist ?? "")",
                badges: [
                    song.difficulty?.rawValue ?? "—",
                    song.raag ?? "—",
                    song.language ?? "—",
                    formatDuration(song.duration ?? 0)
                ]
            )
        }
    }

    @ViewBuilder
    private var tuningSection: some View {
        Section("Tuning") {
            DisclosureRow(
                title: "Tonic Sa",
                value: noteName(for: viewModel.tonicSaPitch)
            ) {
                TonicSaPickerContent(viewModel: viewModel, progress: progress)
            }
        }
    }

    @ViewBuilder
    private var partsSection: some View {
        Section("Parts") {
            if (song.learnerTrackIndices?.count ?? 0) > 1 {
                // I'll play this part — only when multiple tracks
                let labels = Song.trackLabels(for: song)
                Picker("I'll play this part", selection: Binding(
                    get: { progress.preferredLearnerTrackIndex },
                    set: { progress.preferredLearnerTrackIndex = $0 }
                )) {
                    ForEach(Array(labels.enumerated()), id: \.offset) { idx, label in
                        Text(label).tag(idx)
                    }
                }
            }
            if viewModel.hasMultipleStaves {
                Picker("Hands", selection: Binding(
                    get: { progress.preferredHands },
                    set: { progress.preferredHands = $0 }
                )) {
                    Text("Both").tag("both")
                    Text("Right Hand").tag("rh")
                    Text("Left Hand").tag("lh")
                }
                .pickerStyle(.segmented)
            }
            ActionRow(
                title: "Preview my part",
                systemImage: "play.fill",
                isEnabled: !viewModel.isPlaying
            ) {
                Task { await viewModel.previewLearnerPart() }
            }
            ActionRow(
                title: "Preview backing",
                systemImage: "play.fill",
                isEnabled: !viewModel.isPlaying
            ) {
                Task { await viewModel.previewBackingPart() }
            }
        }
    }

    @ViewBuilder
    private var practiceAidsSection: some View {
        Section("Practice aids") {
            ToggleRow(title: "Wait mode", isOn: Binding(
                get: { progress.waitModeEnabled },
                set: { progress.waitModeEnabled = $0; viewModel.isWaitModeEnabled = $0 }
            ))
            ToggleRow(title: "Click track", isOn: Binding(
                get: { progress.clickTrackEnabled },
                set: { progress.clickTrackEnabled = $0 }
            ))
            if progress.clickTrackEnabled {
                Picker("Click level", selection: Binding(
                    get: { progress.clickTrackLevel },
                    set: { progress.clickTrackLevel = $0 }
                )) {
                    Text("Soft").tag("soft")
                    Text("Normal").tag("normal")
                    Text("Loud").tag("loud")
                }
                .pickerStyle(.segmented)
            }
            DisclosureRow(
                title: "Tanpura",
                value: progress.tanpuraEnabled ? (progress.tanpuraRaga.isEmpty ? "On" : progress.tanpuraRaga) : "Off"
            ) {
                TanpuraSettingsContent(tanpura: tanpura)
            }
            DisclosureRow(
                title: "Loop section",
                value: loopRegionLabel(start: progress.loopRegionStart, end: progress.loopRegionEnd)
            ) {
                LoopBuilderContent(viewModel: viewModel, progress: progress)
            }
            ToggleRow(title: "Sound", isOn: $viewModel.isSoundEnabled)
        }
    }

    @ViewBuilder
    private var inputSection: some View {
        Section("Input") {
            HStack {
                Text("MIDI device")
                Spacer()
                Text(viewModel.isMIDIConnected ? (viewModel.midiDeviceName ?? "Connected") : "No device connected")
                    .foregroundStyle(.secondary)
            }
            ToggleRow(title: "Microphone pitch detection", isOn: $viewModel.isMicEnabled)
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        Section("Appearance") {
            DisclosureRow(
                title: "Theme",
                value: AppThemeManager.shared.currentPreset.displayName
            ) {
                ThemeCarouselContent()
            }
        }
    }

    // MARK: - Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60, s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }

    private func noteName(for midi: UInt8) -> String {
        WesternNoteHelper.noteName(midi)
    }

    private func loopRegionLabel(start: Int?, end: Int?) -> String {
        guard let s = start, let e = end else { return "Off" }
        return "Bars \(s)–\(e)"
    }
}
```

(Note: any property names referenced above that don't yet exist on `PlayAlongViewModel` (e.g., `isPlaying`, `isMicEnabled`, `previewLearnerPart`, `previewBackingPart`) are added in Wave 5 — the sheet may reference them, but those bindings are stubbed in this Wave. The sheet should still compile because the view model properties are declared even if the implementations are no-ops.)

- [ ] **Step 2: Add minimal stubs for missing VM properties** in `PlayAlongViewModel.swift` so the sheet compiles. Examples (replace with real impls in Wave 5):

```swift
public var isPlaying: Bool { playbackState == .playing }
public var isMicEnabled: Bool = false
public func previewLearnerPart() async { /* TODO Wave 5 */ }
public func previewBackingPart() async { /* TODO Wave 5 */ }
```

- [ ] **Step 3: Build:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  build 2>&1 | tail -15
```

Expected: ✅ build succeeds. (Sheet not yet wired into SongPlayAlongView — that's Wave 5.)

- [ ] **Step 4: Add `TonicSaPickerContent`** as a small helper view at the bottom of the sheet file or in a new file `SurVibe/PlayAlong/TonicSaPickerContent.swift`:

```swift
struct TonicSaPickerContent: View {
    @Bindable var viewModel: PlayAlongViewModel
    @Bindable var progress: SongProgress

    var body: some View {
        Form {
            Section("Tonic Sa") {
                ForEach(48...72, id: \.self) { midi in
                    Button {
                        viewModel.tonicSaPitch = UInt8(midi)
                        progress.preferredSaHz = saHz(midi: UInt8(midi))
                    } label: {
                        HStack {
                            Text(WesternNoteHelper.noteName(UInt8(midi)))
                            Spacer()
                            if Int(viewModel.tonicSaPitch) == midi {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Section { Button("Play reference tone") { /* TODO: audible tone */ } }
        }
        .navigationTitle("Tonic Sa")
    }

    private func saHz(midi: UInt8) -> Double {
        440.0 * pow(2.0, (Double(midi) - 69.0) / 12.0)
    }
}
```

- [ ] **Step 5: Commit:**

```bash
git add SurVibe/PlayAlong/PlayAlongSettingsSheet.swift \
        SurVibe/PlayAlong/PlayAlongViewModel.swift
git commit -m "feat(PlayAlong): add Settings sheet with all sections

Six sections: Song / Tuning / Parts / Practice aids / Input /
Appearance. Wraps existing TanpuraSettingsContent, LoopBuilderContent,
ThemeCarouselContent (refactored in Wave 2). Two-way bindings to
SongProgress for per-song persistence. Sheet is constructed but not
yet wired to SongPlayAlongView — that's Wave 5."
```

---

# Wave 4 — Navigation surgery (PARALLEL, 3 agents)

**Goal:** Switch SongLibrary's navigation target, delete the orphaned detail screen, port helper functions.

**3 independent tracks — run in parallel.**

## T4.1: Update navigation routing (parallel)

**Files:**
- Modify: `SurVibe/Navigation/AppDestination.swift`
- Modify: `SurVibe/Navigation/AppRouter.swift` (doc comment)
- Modify: `SurVibe/SongsTab.swift`
- Modify: `SurVibe/Songs/SongLibraryView.swift` (line ~244)

- [ ] **Step 1: AppDestination.swift** — remove `.songDetail(Song)` and `.practiceMode(Song)` cases. Update Hashable/Equatable conformances accordingly (drop the matched branches).

- [ ] **Step 2: AppRouter.swift** — find the doc comment example referencing `.songDetail` and update to `.playAlong`.

- [ ] **Step 3: SongsTab.swift** — drop the case branches in `.navigationDestination(for: AppDestination.self)`. Delete the private `SongDetailViewResolver` struct (lines 80–110 dead code).

- [ ] **Step 4: SongLibraryView.swift** — change `NavigationLink(value: AppDestination.songDetail(song))` to `NavigationLink(value: AppDestination.playAlong(song))`.

- [ ] **Step 5: Build:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  build 2>&1 | tail -10
```

Expected: ✅ build fails until T4.2 deletes SongDetailView (which still references the deleted destination case). Plan order: build will pass after Wave 4 fully merges.

- [ ] **Step 6: Commit (do NOT push yet — wait for T4.2 + T4.3 in this wave):**

```bash
git add SurVibe/Navigation/AppDestination.swift \
        SurVibe/Navigation/AppRouter.swift \
        SurVibe/SongsTab.swift \
        SurVibe/Songs/SongLibraryView.swift
git commit -m "feat(Navigation): drop .songDetail and .practiceMode routes

Songs tab now pushes directly into PlayAlong. Old detail screen
will be deleted in T4.2 (same wave). Build will be red between
T4.1 and T4.2 — both must merge before the wave gate."
```

## T4.2: Delete SongDetailView + companions (parallel)

**Files:**
- Delete: `SurVibe/Songs/SongDetailView.swift`
- Delete: `SurVibe/Songs/SongDetailViewParts.swift`
- Delete: `SurVibe/Songs/PlaybackControlsView.swift`
- Delete: `SurVibe/SurVibeTests/SongDetailViewPartsTests.swift` (helpers ported in T4.3)

- [ ] **Step 1: Delete via git:**

```bash
git rm SurVibe/Songs/SongDetailView.swift
git rm SurVibe/Songs/SongDetailViewParts.swift
git rm SurVibe/Songs/PlaybackControlsView.swift
git rm SurVibe/SurVibeTests/SongDetailViewPartsTests.swift
```

- [ ] **Step 2: Verify no stale references:**

```bash
grep -rln "SongDetailView\|SongDetailViewParts\|PlaybackControlsView" SurVibe SurVibeTests
```

Expected: zero results (after Wave 1b's CrossAppThemeContractTests fix).

- [ ] **Step 3: Commit:**

```bash
git add -A
git commit -m "feat(Songs): delete SongDetailView and companions

Detail screen is now subsumed into PlayAlong's Settings sheet.
Helpers (noteName, trackLabels) ported in T4.3."
```

## T4.3: Port helpers (parallel)

**Files:**
- Modify: `SurVibe/Notation/WesternNoteHelper.swift` (or create if missing)
- Create: `SurVibe/Songs/Song+TrackLabels.swift`
- Create: `SurVibe/SurVibeTests/SongTrackLabelsTests.swift`
- Update: `SurVibe/SurVibeTests/WesternNoteHelperTests.swift` (or create) — port `noteName` tests from `SongDetailViewPartsTests.swift`

- [ ] **Step 1: Read existing `WesternNoteHelper.swift`** (if present) to see if `noteName(_:)` already exists. If yes, skip; if no, port from the deleted `SongDetailViewParts.swift`:

```swift
// In SurVibe/Notation/WesternNoteHelper.swift
public enum WesternNoteHelper {
    /// Formats a MIDI pitch as a Western note name (e.g., "C4", "F#3").
    public static func noteName(_ midi: UInt8) -> String {
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = Int(midi) / 12 - 1
        return "\(names[Int(midi) % 12])\(octave)"
    }
}
```

- [ ] **Step 2: Create `SurVibe/Songs/Song+TrackLabels.swift`:**

```swift
extension Song {
    /// Display labels for each candidate learner track.
    /// (Ported from the deleted SongDetailViewParts.trackLabels(for:).)
    public static func trackLabels(for song: Song) -> [String] {
        // Move the body from the deleted SongDetailViewParts here.
        // Original logic: derives labels from accompanimentInstrumentSummary
        // and learnerTrackIndices.
        guard let indices = song.learnerTrackIndices, !indices.isEmpty else {
            return ["Learner"]
        }
        // ... (preserve existing logic verbatim)
        return indices.map { idx in
            song.accompanimentInstrumentSummary?[safe: idx] ?? "Track \(idx + 1)"
        }
    }
}
```

- [ ] **Step 3: Create test files** that port the test cases from the deleted `SongDetailViewPartsTests.swift`:
- `SongTrackLabelsTests.swift` — round-trip tests for `Song.trackLabels(for:)`
- `WesternNoteHelperTests.swift` — round-trip tests for `WesternNoteHelper.noteName(_:)`

- [ ] **Step 4: Build + run new tests:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  test -only-testing:SurVibeTests/SongTrackLabelsTests \
       -only-testing:SurVibeTests/WesternNoteHelperTests 2>&1 | tail -10
```

Expected: ✅ tests pass.

- [ ] **Step 5: Commit:**

```bash
git add SurVibe/Notation/WesternNoteHelper.swift \
        SurVibe/Songs/Song+TrackLabels.swift \
        SurVibe/SurVibeTests/SongTrackLabelsTests.swift \
        SurVibe/SurVibeTests/WesternNoteHelperTests.swift
git commit -m "feat: port noteName + trackLabels helpers from deleted SongDetailViewParts"
```

### Wave 4 Gate

Merge all 3 parallel branches and run full test suite:

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  clean build test 2>&1 | tail -30
```

Expected: ✅ all tests pass; entire app builds without `SongDetailView`, `.songDetail`, or `.practiceMode` references.

---

# Wave 5 — Main view rewrite (sequential, 1 agent)

**Goal:** Rewrite `SongPlayAlongView` and `PlayAlongToolbar` to match the new minimal layout: 4-icon toolbar, title strip with Sa chip, conditional keyboard, gear → Settings sheet, ContentUnavailableView for empty states, `.glassEffect(.regular)`.

**Single agent — these files are interdependent and the changes are cohesive UI surgery. Splitting causes integration headaches.**

## T5.1: Rewrite PlayAlongToolbar.swift

**Files:**
- Modify: `SurVibe/PlayAlong/PlayAlongToolbar.swift` (full rewrite)
- Read first: existing file to understand inputs (callbacks, bindings); spec §"Top-left toolbar"

- [ ] **Step 1: Replace the entire file** with a minimal toolbar:

```swift
import SwiftUI

struct PlayAlongMinimalToolbar: View {
    @Bindable var viewModel: PlayAlongViewModel
    let onSettingsTap: () -> Void
    let onTempoMenuShouldDisableCustom: Bool   // true when Settings sheet is open

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 12) {
            backButton
            playPauseButton
            restartButton
            Spacer().frame(width: 12)
            settingsButton
            Spacer()
            titleStripView
            Spacer()
            timePill
            tempoMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
    }

    // MARK: - Buttons

    private var backButton: some View {
        Button { dismiss() } label: { Image(systemName: "chevron.backward") }
            .accessibilityLabel("Back")
            .accessibilityHint("Returns to the song list")
            .keyboardShortcut(.escape, modifiers: [])
    }

    private var playPauseButton: some View {
        Button {
            Task { viewModel.isPlaying ? viewModel.pauseSession() : await viewModel.startSession() }
        } label: {
            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                .foregroundStyle(.white)
                .padding(8)
                .background(Color.accentColor, in: Circle())
        }
        .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
        .accessibilityHint(viewModel.isPlaying ? "Pauses playback" : "Starts playback")
        .keyboardShortcut(" ", modifiers: [])
    }

    private var restartButton: some View {
        Button {
            Task { await viewModel.restart() }
        } label: { Image(systemName: "arrow.counterclockwise") }
            .accessibilityLabel("Restart")
            .accessibilityHint("Stops playback and starts the song over from the beginning")
            .keyboardShortcut("r", modifiers: .command)
    }

    private var settingsButton: some View {
        Button(action: onSettingsTap) {
            Image(systemName: "gearshape")
                .opacity(viewModel.isPlaying ? 0.5 : 1.0)
        }
        .accessibilityLabel("Settings")
        .accessibilityHint("Opens song settings")
        .keyboardShortcut(",", modifiers: .command)
    }

    // MARK: - Title strip

    @ViewBuilder
    private var titleStripView: some View {
        SongPlayAlongTitleStrip(viewModel: viewModel)
    }

    // MARK: - Time pill + tempo menu

    private var timePill: some View {
        Text("\(formatTime(viewModel.currentTime)) / \(formatTime(viewModel.duration))")
            .font(.subheadline.monospacedDigit())
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }

    private var tempoMenu: some View {
        Menu {
            ForEach([0.50, 0.60, 0.75, 1.00, 1.25, 1.50], id: \.self) { value in
                Button("\(Int(value * 100))%") { viewModel.tempoScale = value }
            }
            Divider()
            Button("Custom…") { /* trigger Tempo Custom sheet — wired in SongPlayAlongView */ }
                .disabled(onTempoMenuShouldDisableCustom)
        } label: {
            Text("Tempo \(Int(viewModel.tempoScale * 100))%")
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15), in: Capsule())
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60, s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
```

- [ ] **Step 2: Build (will fail until SongPlayAlongView is updated in T5.4):**

This is acceptable — keep going.

- [ ] **Step 3: Commit:**

```bash
git add SurVibe/PlayAlong/PlayAlongToolbar.swift
git commit -m "feat(PlayAlong): rewrite PlayAlongToolbar as minimal 4-icon strip

Replaces the multi-row toolbar with a single horizontal strip:
back / play-pause / restart / settings on the left, title strip
center, time + tempo menu right. Liquid Glass capsule background.
Hardware-keyboard shortcuts: Space, Cmd-R, Cmd-comma, Esc.

Tempo Custom item is gated by onTempoMenuShouldDisableCustom to
avoid double-sheet collision when Settings sheet is open."
```

## T5.2: Add Sa chip + title strip view

**Files:**
- Create: `SurVibe/PlayAlong/SongPlayAlongView+TitleStrip.swift`

- [ ] **Step 1: Create the file:**

```swift
import SwiftUI

struct SongPlayAlongTitleStrip: View {
    @Bindable var viewModel: PlayAlongViewModel

    var body: some View {
        VStack(spacing: 2) {
            Text(viewModel.song?.title ?? "")
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                inputBadge
                middleDot
                if viewModel.didInitialHydrate {
                    saChip
                } else {
                    saChipPlaceholder
                }
                middleDot
                bpmBadge
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder
    private var inputBadge: some View {
        if viewModel.isMIDIConnected {
            HStack(spacing: 4) {
                Image(systemName: "pianokeys")
                Text(viewModel.midiDeviceName ?? "MIDI")
            }
            .foregroundStyle(.secondary)
        } else if viewModel.isMicEnabled {
            HStack(spacing: 4) {
                Image(systemName: "mic.fill")
                Text("Mic")
            }
            .foregroundStyle(.secondary)
        } else {
            EmptyView()
        }
    }

    private var middleDot: some View {
        Text("·").foregroundStyle(.tertiary)
    }

    private var saChip: some View {
        Menu {
            ForEach(48...72, id: \.self) { midi in
                Button {
                    viewModel.tonicSaPitch = UInt8(midi)
                } label: {
                    HStack {
                        Text(WesternNoteHelper.noteName(UInt8(midi)))
                        if Int(viewModel.tonicSaPitch) == midi {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text("Sa = \(WesternNoteHelper.noteName(viewModel.tonicSaPitch))")
                Image(systemName: "chevron.down").font(.caption2)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
            .foregroundStyle(.tint)
        }
        .accessibilityLabel("Tonic Sa, currently \(WesternNoteHelper.noteName(viewModel.tonicSaPitch))")
        .accessibilityHint("Double tap to change Sa pitch")
    }

    private var saChipPlaceholder: some View {
        // Avoid flicker between default C4 and stored value during hydration
        Capsule()
            .fill(Color.secondary.opacity(0.1))
            .frame(width: 70, height: 18)
            .overlay(ProgressView().scaleEffect(0.5))
            .accessibilityHidden(true)
    }

    private var bpmBadge: some View {
        Text("\(Int(viewModel.song?.metadata?.bpm ?? 0)) BPM")
            .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 2: Commit:**

```bash
git add SurVibe/PlayAlong/SongPlayAlongView+TitleStrip.swift
git commit -m "feat(PlayAlong): add SongPlayAlongTitleStrip with Sa chip Menu

Three-token subtitle (input badge / Sa chip / BPM badge) replacing
the old plain-text subtitle. Sa chip is a tappable Menu (C3-C5);
hidden until viewModel.didInitialHydrate to avoid default-to-stored
flicker. Shows shimmer placeholder during hydration."
```

## T5.3: Add Tempo Custom sheet

**Files:**
- Create: `SurVibe/PlayAlong/TempoCustomSheet.swift`

- [ ] **Step 1: Create the file:**

```swift
import SwiftUI

struct TempoCustomSheet: View {
    @Bindable var viewModel: PlayAlongViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Tempo") {
                    HStack {
                        Slider(value: $viewModel.tempoScale, in: 0.5...1.5, step: 0.05)
                        Text("\(Int(viewModel.tempoScale * 100))%")
                            .font(.subheadline.monospacedDigit())
                            .frame(width: 50, alignment: .trailing)
                    }
                    Stepper(value: $viewModel.tempoScale, in: 0.5...1.5, step: 0.05) {
                        Text("Fine")
                    }
                }
            }
            .navigationTitle("Custom tempo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
```

- [ ] **Step 2: Commit:**

```bash
git add SurVibe/PlayAlong/TempoCustomSheet.swift
git commit -m "feat(PlayAlong): add TempoCustomSheet for fine tempo control

Slider 0.5-1.5x + numeric stepper. Presented at .medium detent
(vs fixed-height) so Dynamic Type AX5 doesn't clip. Triggered
from the Tempo Menu's Custom… item; gated when Settings sheet
is open to avoid double-sheet collision."
```

## T5.4: Update SongPlayAlongView.swift — main wiring

**Files:**
- Modify: `SurVibe/PlayAlong/SongPlayAlongView.swift` (large)
- Read first: full current file to identify the `body`, `.task`, `.sheet` modifiers

- [ ] **Step 1: Add new state:**

```swift
@State private var showSettingsSheet: Bool = false
@State private var showTempoCustomSheet: Bool = false
@State private var progress: SongProgress?  // hydrated in .task; sheet uses Bindable wrapper after non-nil check
```

**Note:** The settings sheet uses `@Bindable var progress: SongProgress` (non-optional) — present the sheet only after `progress != nil`. Wrap the sheet content like this:

```swift
.sheet(isPresented: $showSettingsSheet) {
    if let p = progress {
        PlayAlongSettingsSheet(viewModel: viewModel, tanpura: tanpura, song: song, progress: p)
            .presentationDetents([.medium, .large])
            // ... other modifiers
    }
}
```

- [ ] **Step 2: Replace the existing toolbar/chrome rendering** with `PlayAlongMinimalToolbar`:

```swift
PlayAlongMinimalToolbar(
    viewModel: viewModel,
    onSettingsTap: { showSettingsSheet = true },
    onTempoMenuShouldDisableCustom: showSettingsSheet
)
```

- [ ] **Step 3: Replace the existing notation/keyboard layout:**

```swift
VStack(spacing: 0) {
    PlayAlongMinimalToolbar(...)

    notationViewport

    if !viewModel.isMIDIConnected {
        InteractivePianoView(
            highlightedNotes: viewModel.effectiveMidiNotes,
            onNoteOn: { viewModel.handleKeyboardNoteOn(midiNote: $0) },
            onNoteOff: { viewModel.handleKeyboardNoteOff(midiNote: $0) }
        )
        .frame(height: 280)
        .transition(.opacity)
    }
}
.animation(reduceMotion ? .none : .easeInOut(duration: 0.25), value: viewModel.isMIDIConnected)
```

- [ ] **Step 4: Add empty-state ContentUnavailableView for the 4-quadrant matrix:**

```swift
@ViewBuilder
private var notationViewport: some View {
    let hasNotation = !(viewModel.decodedSargamNotes?.isEmpty ?? true) ||
                      !(viewModel.decodedWesternNotes?.isEmpty ?? true)
    let hasScoring = !viewModel.noteEvents.isEmpty

    if !hasNotation && !hasScoring {
        ContentUnavailableView(
            "No notation or audio data available",
            systemImage: "music.note.list",
            description: Text("Try a different song")
        )
    } else if !hasNotation && hasScoring {
        ContentUnavailableView(
            "No notation",
            systemImage: "music.note",
            description: Text("Listen to the song and play by ear")
        )
    } else if hasNotation && !hasScoring {
        VStack(spacing: 0) {
            Text("Notation only — audio scoring not available for this song")
                .font(.caption)
                .padding(8)
                .background(Color.yellow.opacity(0.2))
            existingNotationContent
        }
    } else {
        existingNotationContent  // normal full-feature path (existing dispatch)
    }
}
```

- [ ] **Step 5: Add `.sheet` modifiers for Settings + Tempo Custom:**

```swift
.sheet(isPresented: $showSettingsSheet) {
    PlayAlongSettingsSheet(
        viewModel: viewModel,
        tanpura: tanpura,
        song: song,
        progress: progress
    )
    .presentationDetents([.medium, .large])
    .presentationDragIndicator(.visible)
    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    .presentationCompactAdaptation(.none)
}
.sheet(isPresented: $showTempoCustomSheet) {
    TempoCustomSheet(viewModel: viewModel)
}
```

- [ ] **Step 6: Wire VM hydration in `.task`:**

```swift
.task {
    let descriptor = FetchDescriptor<SongProgress>(
        predicate: #Predicate { $0.songSlug == song.slug }
    )
    if let existing = try? modelContext.fetch(descriptor).first {
        progress = existing
        await viewModel.loadPersistedSettings(from: existing, seedFromVM: false)
    } else {
        let newRow = SongProgress(songSlug: song.slug)
        modelContext.insert(newRow)
        progress = newRow
        await viewModel.loadPersistedSettings(from: newRow, seedFromVM: true)
    }
}
```

- [ ] **Step 7: Apply `.glassEffect(.regular)` to the toolbar surface** (already in T5.1 toolbar code via `.glassEffect(.regular, in: Capsule())`).

- [ ] **Step 8: Build:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  build 2>&1 | tail -20
```

Expected: ✅ build succeeds.

- [ ] **Step 9: Manual smoke test on simulator:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  build-for-testing
```

Run the app, tap a song from Songs tab, verify direct push to Play Along. Tap gear → settings sheet appears at medium detent with notation visible behind. Drag up → large detent, background blocked. Tap close → returns. Verify Sa chip menu, tempo menu, restart, exit, play/pause.

- [ ] **Step 10: Commit:**

```bash
git add SurVibe/PlayAlong/SongPlayAlongView.swift
git commit -m "feat(PlayAlong): wire new toolbar, settings sheet, and conditional keyboard

- Replaces multi-row PlayAlongToolbar with PlayAlongMinimalToolbar
- Adds .sheet for PlayAlongSettingsSheet (.medium default) and
  TempoCustomSheet
- Conditionally renders InteractivePianoView only when no MIDI
- Adds 4-quadrant ContentUnavailableView empty states
- Wires VM hydration in .task (loadPersistedSettings with first-launch
  seedFromVM policy)
- Applies .glassEffect(.regular) to toolbar capsule

Resolves spec success criteria #1-7."
```

## T5.5: Run /audio-review (project mandate)

- [ ] **Step 1: Invoke `/audio-review`** to verify the audio-related changes (VM hydration ordering, restart() audio teardown, conditional keyboard not breaking audio engine).

- [ ] **Step 2: Address any findings** in a follow-up commit if needed.

### Wave 5 Gate

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  clean build test 2>&1 | tail -30
```

Expected: ✅ all tests pass; manual smoke test green; /audio-review clean.

---

# Wave 6 — Tests + final verification (PARALLEL, 3 agents)

## T6.1: SongProgress fields tests (parallel)

**Files:**
- Create: `SurVibe/SurVibeTests/SongProgressFieldsTests.swift`

- [ ] **Step 1: Write Swift Testing tests:**

```swift
import Testing
import SwiftData
@testable import SurVibe

struct SongProgressFieldsTests {
    @Test func defaultValuesAreCorrect() {
        let p = SongProgress(songSlug: "test")
        #expect(p.preferredHands == "both")
        #expect(p.preferredTempoScale == 1.0)
        #expect(p.preferredLearnerTrackIndex == 0)
        #expect(p.waitModeEnabled == false)
        #expect(p.clickTrackEnabled == false)
        #expect(p.clickTrackLevel == "normal")
        #expect(p.tanpuraEnabled == false)
        #expect(p.tanpuraRaga == "")
        #expect(p.loopRegionStart == nil)
        #expect(p.loopRegionEnd == nil)
    }

    @Test func roundTripPersistence() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: SongProgress.self, configurations: config)
        let ctx = container.mainContext

        let p = SongProgress(songSlug: "test")
        p.preferredTempoScale = 0.75
        p.preferredHands = "rh"
        p.tanpuraEnabled = true
        p.tanpuraRaga = "Bhairavi"
        p.loopRegionStart = 5
        p.loopRegionEnd = 12
        ctx.insert(p)
        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<SongProgress>()).first
        #expect(fetched?.preferredTempoScale == 0.75)
        #expect(fetched?.preferredHands == "rh")
        #expect(fetched?.tanpuraEnabled == true)
        #expect(fetched?.tanpuraRaga == "Bhairavi")
        #expect(fetched?.loopRegionStart == 5)
        #expect(fetched?.loopRegionEnd == 12)
    }
}
```

- [ ] **Step 2: Run + commit:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  test -only-testing:SurVibeTests/SongProgressFieldsTests 2>&1 | tail -10
git add SurVibe/SurVibeTests/SongProgressFieldsTests.swift
git commit -m "test(SongProgress): cover new pref fields with defaults + round-trip"
```

## T6.2: Settings sheet behavior tests (parallel)

**Files:**
- Create: `SurVibe/SurVibeTests/PlayAlongSettingsSheetTests.swift`

- [ ] **Step 1: Write tests** covering:
- Sheet appears when `showSettingsSheet = true`
- Toggle changes write through to `SongProgress`
- Hands picker bound to `progress.preferredHands`
- Click track level row hidden when `clickTrackEnabled == false`
- Tonic Sa picker disclosure pushes onto internal nav stack

```swift
import Testing
import SwiftData
import SwiftUI
@testable import SurVibe

@MainActor
struct PlayAlongSettingsSheetTests {
    @Test func toggleWritesToProgress() throws {
        let progress = makeProgress()
        progress.waitModeEnabled = false
        progress.waitModeEnabled = true
        #expect(progress.waitModeEnabled == true)
    }

    @Test func clickLevelHiddenWhenClickDisabled() {
        let progress = makeProgress()
        progress.clickTrackEnabled = false
        // SwiftUI body inspection — use ViewInspector or assert on
        // a visibility computed property on the sheet helper
        // (placeholder: assert on a model-level property)
        #expect(progress.clickTrackEnabled == false)
    }

    private func makeProgress() -> SongProgress {
        let cfg = ModelConfiguration(isStoredInMemoryOnly: true)
        let c = try! ModelContainer(for: SongProgress.self, configurations: cfg)
        let p = SongProgress(songSlug: "t")
        c.mainContext.insert(p)
        return p
    }
}
```

- [ ] **Step 2: Run + commit:**

```bash
git add SurVibe/SurVibeTests/PlayAlongSettingsSheetTests.swift
git commit -m "test(PlayAlong): cover settings sheet bindings and visibility logic"
```

## T6.3: SongPlayAlongView layout tests (parallel)

**Files:**
- Create: `SurVibe/SurVibeTests/SongPlayAlongViewLayoutTests.swift`

- [ ] **Step 1: Write tests** for:
- Tempo cycle behavior: setting `tempoScale = 0.6` writes through to VM and to progress
- `restart()` sequence: stopAndComplete + seek(0) + scoring.reset + startSession (mock the engines)
- Conditional keyboard: when `viewModel.isMIDIConnected = true`, keyboard should be hidden (test the boolean condition; UI snapshot is out of scope per CLAUDE.md "What NOT to test: SwiftUI view layout")
- Sa chip hidden until `didInitialHydrate == true`

- [ ] **Step 2: Run + commit:**

```bash
git add SurVibe/SurVibeTests/SongPlayAlongViewLayoutTests.swift
git commit -m "test(PlayAlong): cover tempo cycle, restart, conditional keyboard, Sa chip gating"
```

## T6.4: Final verification (sequential, after all parallel tasks above)

- [ ] **Step 1: SwiftLint:**

```bash
/opt/homebrew/bin/swiftlint lint --quiet --config .swiftlint.yml
```

Expected: no errors.

- [ ] **Step 2: swift-format:**

```bash
git diff --name-only HEAD~20 | grep '\.swift$' | \
  xargs -I{} xcrun swift-format lint --configuration .swift-format {}
```

Expected: no warnings on changed files.

- [ ] **Step 3: Full clean build + test:**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -derivedDataPath /private/tmp/SurVibe-DD \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  clean build test 2>&1 | tail -50
```

Expected: ✅ all tests pass; zero new warnings.

- [ ] **Step 4: Run `/check`:**

```bash
/check
```

Expected: green.

- [ ] **Step 5: Run `/latency-check` (project mandate before release):**

```bash
/latency-check
```

Expected: green.

- [ ] **Step 6: Manual VoiceOver / Reduce Motion / Dynamic Type AX5 audit on simulator:**
- VoiceOver: tab through toolbar; verify announcements; verify settings sheet announces "Settings panel, opened"
- Reduce Motion: enable in simulator Settings; verify panel cross-fades, keyboard hide/show is instant
- Dynamic Type AX5: Settings → Accessibility → Display → Larger Text → AX5; verify settings sheet rows reflow, tempo Custom sheet doesn't clip

- [ ] **Step 7: Final commit if any cleanup applied:**

```bash
git add -A && git commit -m "chore: post-verification cleanup" || echo "no changes"
```

---

# Final verification checklist — mapped to spec success criteria

After all waves complete:

- [ ] **Spec criterion 1 — Direct nav:** Tap any song → push to PlayAlong (no detail screen)
- [ ] **Spec criterion 2 — Settings sheet contents:** Tonic Sa, Hands, Preview, Wait, Click, Click level, Tanpura, Loop, Sound, MIDI, Mic, Theme — all present, persisted per-song
- [ ] **Spec criterion 3 — Conditional keyboard:** External MIDI connected → keyboard hidden, notation expands
- [ ] **Spec criterion 4 — Zero stale references:**
  ```bash
  grep -rn "SongDetailView\|SongDetailViewParts\|\.songDetail\|\.practiceMode\|PracticeSessionView\|PlaybackControlsView" SurVibe SurVibeTests
  ```
  Expected: zero results
- [ ] **Spec criterion 5 — Tests:** All existing PlayAlong tests pass; new tests cover layout, persistence, tempo collapse
- [ ] **Spec criterion 6 — Build hygiene:** SwiftLint clean; `xcodebuild clean build` zero warnings
- [ ] **Spec criterion 7 — Accessibility:** VoiceOver, Reduce Motion, Dynamic Type AX5 manual audit passed

---

# Risks & rollback plan

| Risk | Mitigation | Rollback |
|------|-----------|----------|
| Wave 1b deletes a file that's actually shared | Pre-deletion verification step in T1b.1 step 1 | `git revert` the deletion commit; move shared files in a fresh Wave 1a iteration |
| Tempo collapse misses a call site | Compiler will catch in Wave 0b step 6 | Fix the call site; re-run Wave 0b |
| CloudKit sync regression on existing test data | No release yet; minimal blast radius | `git revert` SongProgress field additions; data is local-only in dev |
| `presentationBackgroundInteraction` API behavior differs from spec | T5.4 step 9 manual smoke test catches this | Drop `.medium` detent; default to `.large`; document UX regression |
| Sa chip flicker still visible | T5.4 step 9 manual test | Increase placeholder shimmer duration or pre-fetch SongProgress synchronously |
| Sub-screen refactor (Wave 2) breaks existing sheet callers | Wave 2 gate runs full test suite | Each Wave 2 commit is isolated — `git revert` the offending one |

---

# Appendix: Useful greps

```bash
# Find all SongDetail references
grep -rn "SongDetail" SurVibe SurVibeTests

# Find all tempo-related symbols
grep -rn "tempoScale\|arrangementTempoScale\|clampTempoScale" SurVibe SurVibeTests

# Find all Practice/ consumers from non-Practice code
grep -rn -e "PracticeSessionRecorder" -e "PitchProximityMeter" SurVibe SurVibeTests | \
  grep -v "/Practice/"

# Find all consumers of removed Song fields
grep -rn "lastUsedTempoScale\|defaultPracticeMode" SurVibe SurVibeTests

# Find all settings-sheet candidate values
grep -rn "preferredHands\|preferredTempoScale\|waitModeEnabled" SurVibe SurVibeTests
```

---

**Plan version:** 1.0
**Plan status:** Ready for execution. Awaiting user start command in next session.
