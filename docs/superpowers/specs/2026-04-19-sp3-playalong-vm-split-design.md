# SP-3 — PlayAlongViewModel Split: Design Spec

**Date:** 2026-04-19
**Sub-project:** SP-3 (fourth in the Apple 3-OS refactor trajectory; consumer of SP-0 + SP-2)
**Status:** Design approved; awaiting user spec review before per-phase `writing-plans`.
**Size:** ~3 weeks of work across 4 incremental phases (SP-3a → SP-3d).
**Context:** No release has shipped; back-compat shims not required.
**Foundations consumed:**
- SP-0 F1 `LatencyContractTests.featureFlagToggleDoesNotRestartEngine` (stays green between every phase).
- SP-0 F4 `FeatureFlag.playAlongViewModelV2` — declared but **unused** in SP-3 (incremental path does not need a flag; flag available for a hypothetical future big-bang A/B).
- SP-0 F6 Foundation primitives: `SPSCRingBuffer` (cross-actor audio handoff), `LatencyProbe`+`LatencyHistogram` (p95 baseline capture).
- SP-2 `PlayAlongSceneHost` (hosts the facade; unchanged by SP-3).
- SP-2 `LatencyContractTests.rotationDoesNotRestartAudioEngine` (stays green between every phase).
- SP-2 `TransportActions` / `@FocusedValue(\.transportActions)` — facade continues to publish this; internal routing now goes through coordinators.
- SP-2 `AppRouter` v2 (unchanged).

## 1. Purpose

`SurVibe/PlayAlong/PlayAlongViewModel.swift` is a 1,828-line `@Observable @MainActor final class` holding playback state, scoring bookkeeping, chrome visibility state, pitch-detection loops, MIDI input routing, chord detection, session completion + SwiftData writes, and theme color resolution. The file carries a `// swiftlint:disable file_length` directive and a comment explaining the author's belief that `@Observable` forces a single-file class.

SP-3 splits this god-object into **one facade + four coordinators + the existing `WaitController`**, preserving the external `PlayAlongViewModel` API (20+ call sites) so views and tests stay untouched. Each coordinator is itself `@Observable @MainActor`; SwiftUI's observation-tracking follows references through `let`-held nested observables (Swift 5.9+ standard pattern).

SP-3 ships in **4 incremental phases**, each its own PR + merge + tag. The highest-risk phase (NoteRouter, which owns the single-hop `AudioEngineManager.shared.noteOn()` call) is **LAST** — by then, every other coordinator has been battle-tested on `main`.

**In scope (4 phases):**

| Phase | Extracts | Est. LOC extracted | Risk | Tag |
|---|---|---:|:---:|---|
| **SP-3a** ScoringCoordinator | Score bookkeeping, streak tracking, pure scoring math | ~200 | 🟢 LOW | `sp-3a-scoring` |
| **SP-3b** PlaybackCoordinator | Transport, tempo, wait-mode toggle, session completion, SwiftData write | ~600 | 🟡 MED | `sp-3b-playback` |
| **SP-3c** View-chrome extraction | Theme colors, chrome visibility, view/notation modes, latency preset | ~150 | 🟢 LOW | `sp-3c-view-chrome` |
| **SP-3d** NoteRouter | Pitch detection, chord detection, note input processing, keyboard handlers, display-link integration | ~500 | 🔴 **HIGH** | `sp-3d-note-router` |
| — Umbrella | Final facade ≤ 200 lines; delete `file_length` disclaimer | — | — | `sp-3-vm-split-complete` |

**Out of scope (explicit non-goals):**
- No `PlayAlongViewModel` public API changes. External call sites (20+ files) untouched.
- No audio-path rewrite. `AudioEngineManager.shared.noteOn/off` call semantics identical to today.
- No new `async/await` boundaries on note-on path.
- No feature-flag gating (incremental path is git-revertable per phase).
- No AI hooks yet — coordinator boundaries MUST accommodate SP-5 extension, but SP-3 does not add SVAI surfaces.
- No Mac destination enablement — SP-6 territory. Code must compile on macOS.
- No changes to `WaitController` (already-extracted class; composed by PlaybackCoordinator).
- No changes to `MIDIInputManager` / `AudioEngineManager` / `SPSCRingBuffer` / `LatencyProbe` (all SVAudio internals; SP-3 is app-target only).

## 2. Success criteria

Across all 4 phases:

- `PlayAlongViewModel.swift` ≤ 200 lines after SP-3d merges. Current: 1,828 lines.
- `// swiftlint:disable file_length` directive at line 1 **deleted** (completion signal).
- `LatencyContractTests.featureFlagToggleDoesNotRestartEngine` green after every phase.
- `LatencyContractTests.rotationDoesNotRestartAudioEngine` green after every phase.
- `LatencyProbe` p95 delta ≤ 0.5 ms vs. Phase-3a pre-commit baseline (captured once, checked after every merge).
- All 8 existing PlayAlong test suites pass after every phase: `PlayAlongFullFlowTests`, `PlayAlongIntegrationTests`, `PlayAlongThemeIntegrationTests`, `PlayAlongChromeTests`, `PlayAlongGestureTests`, `ChordScoringIntegrationTests`, `PlayAlongViewModelTests`, `PlayAlongTempoScalingTests`.
- Hardcoded-logic scan on `SurVibe/PlayAlong/`: 0 hits for `UIDevice|UIScreen.main.bounds|UIInterfaceOrientation|.bottomBar|.topBarTrailing|#if os(macOS)|#if os(iOS)`.
- Per-coordinator unit tests: ≥ 1 focused suite per new coordinator covering its extracted responsibilities.
- Every coordinator compiles for iOS + iPadOS simulators; Mac-ready by construction (no `UIKit`-only types, no `AVAudioSession` touched directly).
- No unit-test count REGRESSION vs. pre-SP-3 baseline. Count may grow.

## 3. Architecture decisions

**AD-1 — Facade pattern, not delete-entirely.**
`PlayAlongViewModel` stays as a thin (~100-line) `@Observable @MainActor final class` holding the four coordinators as `let` properties. External call sites (20 files including 6 test suites + `SongPlayAlongView` + `PlayAlongSceneHost`) read properties through the facade unchanged. Views continue to access `viewModel.X` — SwiftUI tracks observation through nested observables.

**AD-2 — Incremental extraction, no feature flag.**
Four separate PRs land sequentially on `main`. Each PR is individually revertable (`git revert <sha>`). `FeatureFlag.playAlongViewModelV2` stays declared in SVCore but is **unused** in SP-3 code — available for a hypothetical future big-bang A/B if ever needed.

**AD-3 — Risk-tiered phase ordering: LOW → MED → LOW → HIGH.**
SP-3a (ScoringCoordinator, pure math) proves the `@Observable` nested-coordinator pattern works. SP-3b (PlaybackCoordinator) is the most user-visible but has a trivial rollback story. SP-3c (view-chrome) is pure presentation. SP-3d (NoteRouter) is HIGHEST risk — it owns `AudioEngineManager.shared.noteOn()` — and ships LAST after every other piece is battle-tested.

**AD-4 — Coordinators are concrete classes, not protocols.**
No over-abstraction. Each coordinator is `@Observable @MainActor final class` with the concrete type as the interface. Protocols are introduced ONLY when a second implementation exists or is imminent (matches SP-0 Task 6 discipline). SP-5's future AI integration can add a `CoachingContext` output from `ScoringCoordinator` WITHOUT making `ScoringCoordinator` a protocol.

**AD-5 — Single-hop note-on preserved.**
`NoteRouter` is the SOLE site that calls `AudioEngineManager.shared.noteOn(_:velocity:)` / `noteOff(_:)`. MIDI callback → `NoteRouter.handleNoteOn(midiNote:)` → `AudioEngineManager.shared.noteOn(...)` is synchronous on the arriving thread. No `await` boundary. Non-negotiable.

**AD-6 — Cross-actor state reads via SPSCRingBuffer or Mutex snapshots.**
If `ScoringCoordinator` needs to see a note event produced by `NoteRouter`, the handoff is via `SPSCRingBuffer` (existing SVAudio primitive) or `Mutex<State>` snapshot read — never a direct call crossing isolation boundaries. `NoteRouter` pushes events; `ScoringCoordinator` drains on MainActor schedule.

**AD-7 — `MIDIInputManager` stays `NSLock`-guarded, not `@MainActor`.**
CoreMIDI callbacks arrive on arbitrary threads (CLAUDE.md rule, verified in existing `SVAudio/MIDI/MIDIInputManager.swift`). `NoteRouter` wraps `MIDIInputManager` as a dependency; the lock discipline is preserved.

**AD-8 — `ModelContext` injection on `PlaybackCoordinator` only.**
Only session completion writes to SwiftData (`SongProgress` updates). `PlaybackCoordinator` owns the `modelContext: ModelContext?` optional (currently at `PlayAlongViewModel.swift:308`). `ScoringCoordinator` is pure computation — no SwiftData. This gives SP-4's future accessibility work a clean PK handoff: tests can mock persistence without touching scoring.

**AD-9 — `@Observable` composition verified via Swift 5.9+ semantics.**
Every coordinator declares `@Observable @MainActor final class`. Facade stores them as `let coordinator: ScoringCoordinator`. Views reading `viewModel.scoring.totalScore` transparently register observation on `totalScore` — the `let` access is not observed, the nested property access is. This is the standard Swift 5.9+ nested-observable pattern (SP-0 `FeatureFlagStore.shared` uses it already at smaller scale).

**AD-10 — Cross-platform discipline preserved.**
Zero new `#if os(...)` / `UIDevice` / `UIScreen` / `AVAudioSession` in SP-3 code. Verified pre-SP-3 baseline is clean (grep returns 0 hits in `PlayAlongViewModel.swift`). SP-3 must NOT introduce any. Platform-variant behavior routes through SVCore protocols per SP-0's Platform Hygiene convention.

## 4. Target file layout

```
SurVibe/PlayAlong/
├── PlayAlongViewModel.swift                          SHRINKS from 1,828 → ≤200 lines (facade)
├── Coordinators/                                     NEW folder
│   ├── ScoringCoordinator.swift                      NEW (SP-3a) — ~200 lines
│   ├── PlaybackCoordinator.swift                     NEW (SP-3b) — ~600 lines
│   ├── PlayAlongChromeState.swift                    NEW (SP-3c) — ~150 lines
│   └── NoteRouter.swift                              NEW (SP-3d) — ~500 lines
├── PlayAlongSceneHost.swift                          UNCHANGED (SP-2)
├── PlayAlongWaitController.swift                     UNCHANGED (composed by PlaybackCoordinator)
├── MIDINoteHighlightCoordinator.swift                UNCHANGED (owns CADisplayLink; NoteRouter references it)
├── SongPlayAlongView.swift                           UNCHANGED (call sites intact per AD-1)
├── SongPlayAlongView+Subviews.swift                  UNCHANGED
└── … other existing files                            UNCHANGED

SurVibeTests/
├── ScoringCoordinatorTests.swift                     NEW (SP-3a)
├── PlaybackCoordinatorTests.swift                    NEW (SP-3b)
├── PlayAlongChromeStateTests.swift                   NEW (SP-3c)
└── NoteRouterTests.swift                             NEW (SP-3d)
```

**No SVCore / SVAudio changes.** All SP-3 work is app-target only.

## 5. Coordinator contracts

### 5.1 ScoringCoordinator (SP-3a)

**Responsibility:** compute per-note scores + session aggregates (accuracy, stars, XP, streaks). Pure state machine; no audio, no SwiftData, no UI.

**Extracts from VM:** lines 1679–1710 (Score Bookkeeping + Streak Tracking) + score-related published properties (`notesHit`, `accuracy`, `streak`, `longestStreak`, `starRating`, `xpEarned`, `noteScores`).

**Dependencies (via init):**
- Immutable: song difficulty (passed at init once per session).
- None from SVCore/SVAudio for scoring logic itself (already uses `NoteScoreCalculator` from SVLearning as a pure helper — stays that way).

**Public surface (read by facade + views via `viewModel.scoring.X`):**
```swift
@Observable @MainActor final class ScoringCoordinator {
    private(set) var notesHit: Int = 0
    private(set) var accuracy: Double = 0
    private(set) var streak: Int = 0
    private(set) var longestStreak: Int = 0
    private(set) var starRating: Int = 0
    private(set) var xpEarned: Int = 0
    private(set) var noteScores: [NoteScore] = []

    func record(_ score: NoteScore)
    func recordMissed(_ score: NoteScore)
    func finalize(songDifficulty: Int)
    func reset()
}
```

**Latency risk:** 🟢 None. Pure MainActor computation, called from existing VM dispatch sites.

### 5.2 PlaybackCoordinator (SP-3b)

**Responsibility:** transport state (play/pause/stop), tempo scaling, wait-mode toggle, playback scheduling, session completion, `SongProgress` persistence.

**Extracts from VM:** lines 40–130 (Published State — playback/wait/tempo/sound), 448–613 (Public Methods — loadSong, startSession, pauseSession, resumeSession), 744–812 (waitMode, stopAndComplete, cleanup), 1366–1498 (Playback Scheduling), 1711–1799 (Session Completion). Owns the `modelContext`.

**Dependencies (via init):**
- `modelContext: ModelContext?` (for `SongProgress` writes)
- `clock: ClockProviding` (existing DI — drift-corrected timing)
- `waitController: PlayAlongWaitController` (existing class, composed)
- `scoring: ScoringCoordinator` (for session-completion finalization)
- `metronome: MetronomeScheduling` (existing protocol)
- `analytics: (any AnalyticsProviding)? = nil` (SP-0/1/2 nil-sentinel pattern for `@MainActor` default)

**Public surface:**
```swift
@Observable @MainActor final class PlaybackCoordinator {
    private(set) var playbackState: PlaybackState = .idle
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var tempoScale: Double = 1.0 { didSet { /* rescheduleAtNewTempo */ } }
    var isWaitModeEnabled: Bool = false
    var isSoundEnabled: Bool = true
    var playbackProgress: Double { ... }

    func loadSong(_ song: Song) async
    func startSession() async
    func pauseSession()
    func resumeSession()
    func stopAndComplete()
    func seek(to progress: Double)
    func cleanup()
}
```

**Latency risk:** 🟡 Low-Medium. Playback scheduling uses `ContinuousClock` + `Task.sleep`; no sampler reconfiguration. Rotation-safety test from SP-2 must stay green — `PlayAlongSceneHost` still owns the facade, which now owns the PlaybackCoordinator.

### 5.3 PlayAlongChromeState (SP-3c)

**Responsibility:** UI presentation state — chrome visibility, theme colors, view/notation modes. No audio, no scoring, no persistence.

**Extracts from VM:** lines 131–225 (Resolved Theme Colors, latency preset), 226–275 (Chrome Visibility + Actions), plus `viewMode`, `notationMode`.

**Dependencies (via init):**
- `themeManager: AppThemeManager` (SVCore, existing)
- `latencyPreset: LatencyPreset = .fast` (existing default)

**Public surface:**
```swift
@Observable @MainActor final class PlayAlongChromeState {
    private(set) var isChromeVisible: Bool = true
    var viewMode: PlayAlongViewMode = .fallingNotes
    var notationMode: NotationDisplayMode = .sargam
    var latencyPreset: LatencyPreset = .fast

    // Theme colors resolved against current theme
    private(set) var resolvedColors: ResolvedPlayAlongColors = .default

    static let autoHideDuration: TimeInterval = 6.0   // NEW — was magic `6.0` at VM line 244

    func summonChrome()
    func hideChrome()
    func resetAutoHide()
    func updateTheme(_ themeManager: AppThemeManager)
}
```

**Latency risk:** 🟢 None. Pure UI state. `chromeAutoHideSeconds` magic number becomes named `static let autoHideDuration` with docstring (enforces P3 no-hardcode principle).

### 5.4 NoteRouter (SP-3d) — HIGHEST RISK

**Responsibility:** audio/MIDI input → structured note + chord events. Owns the single site that calls `AudioEngineManager.shared.noteOn()`. Drives `MIDINoteHighlightCoordinator`'s CADisplayLink via snapshot reads.

**Extracts from VM:** lines 650–758 (note handling), 855–1365 (Pitch Detection + chord detection), 1499–1522 (Display Link), 1523–1678 (Note Input Processing).

**Dependencies (via init):**
- `audioEngine: any AudioEngineProviding` (existing SVAudio protocol; test-injectable)
- `midiInput: any MIDIInputProviding` (existing SVAudio protocol)
- `soundFont: any SoundFontPlaying` (existing SVAudio protocol)
- `highlightCoordinator: MIDINoteHighlightCoordinator` (existing class, composed)
- `scoring: ScoringCoordinator` (consumes note/chord events via main-actor dispatch; NOT via SPSCRingBuffer because scoring is already `@MainActor`)

**Public surface:**
```swift
@Observable @MainActor final class NoteRouter {
    private(set) var isMIDIConnected: Bool = false
    private(set) var currentPitch: Double = 0
    private(set) var detectedChord: ChordClassification? = nil

    func startMIDIDetection() async
    func stopMIDIDetection()
    func startMicPitchDetection() async
    func stopMicPitchDetection()
    func handleKeyboardNoteOn(midiNote: Int)
    func handleKeyboardNoteOff(midiNote: Int)

    // Invariant: this is the ONLY method that calls AudioEngineManager.shared.noteOn.
    // MIDI callbacks → this method, synchronously, on the arriving thread.
}
```

**Latency risk:** 🔴 **HIGH.** Single-hop note-on (AD-5) is the load-bearing invariant. No new `await` between MIDI callback and `AudioEngineManager.shared.noteOn()`. Phase 3d plan defines the precise call-graph verification.

## 6. Per-phase acceptance criteria

### SP-3a — ScoringCoordinator

- [ ] `SurVibe/PlayAlong/Coordinators/ScoringCoordinator.swift` exists, ~200 lines, `@Observable @MainActor final class`.
- [ ] Facade holds `let scoring = ScoringCoordinator()`; delegates existing `notesHit` / `accuracy` / etc. properties to `scoring.*`.
- [ ] `SurVibeTests/ScoringCoordinatorTests.swift` with ≥ 4 tests: `recordIncrementsHitCount`, `accuracyAveragesCorrectly`, `finalizeComputesStarRating`, `resetClearsState`.
- [ ] All 8 existing PlayAlong test suites pass.
- [ ] `LatencyContractTests` green.
- [ ] Hardcoded-logic scan: 0 hits on new file.
- [ ] Tag `sp-3a-scoring` pushed.

### SP-3b — PlaybackCoordinator

- [ ] `PlaybackCoordinator.swift` exists, ~600 lines.
- [ ] Facade holds `let playback = PlaybackCoordinator(...)`; delegates `playbackState` / `currentTime` / `tempoScale` / etc.
- [ ] `PlaybackCoordinatorTests.swift` with ≥ 6 tests: load-song, start/pause/resume, tempo change triggers reschedule, session completion writes `SongProgress`, wait-mode toggle.
- [ ] SP-2 `TransportActions` bindings (`togglePlayPause` → `handlePlayPause`, `seek(by:)` translations, `stop` → `handleStop`) still work — transport commands continue to dispatch correctly.
- [ ] Session completion still writes `SongProgress` via `modelContext` (verify with a ModelContainer integration test).
- [ ] All latency gates + all 8 test suites green.
- [ ] Tag `sp-3b-playback` pushed.

### SP-3c — View-chrome state

- [ ] `PlayAlongChromeState.swift` exists, ~150 lines.
- [ ] Facade holds `let chrome = PlayAlongChromeState(...)`; delegates `viewMode` / `notationMode` / `isChromeVisible` / `resolvedColors`.
- [ ] `chromeAutoHideSeconds = 6.0` magic number replaced by `static let autoHideDuration: TimeInterval = 6.0` with docstring.
- [ ] `PlayAlongChromeStateTests.swift` with ≥ 3 tests: summon/hide cycle, auto-hide timing, theme-update propagation.
- [ ] `PlayAlongThemeIntegrationTests` + `PlayAlongChromeTests` still pass (regression guard).
- [ ] All latency gates green.
- [ ] Tag `sp-3c-view-chrome` pushed.

### SP-3d — NoteRouter (HIGHEST RISK)

- [ ] `NoteRouter.swift` exists, ~500 lines.
- [ ] Facade holds `let noteRouter = NoteRouter(...)`; delegates `isMIDIConnected` / `currentPitch`.
- [ ] **Single-hop note-on verified:** grep `AudioEngineManager.shared.noteOn` across `SurVibe/PlayAlong/` returns **exactly one** call site, in `NoteRouter`.
- [ ] **No new `await` on MIDI → noteOn path:** code review + grep for `await.*noteOn` returns 0.
- [ ] `NoteRouterTests.swift` with ≥ 5 tests: MIDI note-on dispatch, keyboard touch, mic pitch detection start/stop, chord detection publishes result, DisplayLink integration preserved.
- [ ] Both latency-safety tests green WITH p95 delta ≤ 0.5 ms vs. pre-SP-3a baseline.
- [ ] All 8 PlayAlong test suites pass.
- [ ] Tag `sp-3d-note-router` pushed.

### Umbrella completion

- [ ] `PlayAlongViewModel.swift` ≤ 200 lines (facade only).
- [ ] `// swiftlint:disable file_length` directive at line 1 **deleted**.
- [ ] `// swiftlint:disable:next type_body_length` directive above class declaration **deleted**.
- [ ] Hardcoded-logic grep on `SurVibe/PlayAlong/`: 0 hits.
- [ ] Tag `sp-3-vm-split-complete` pushed on the final merge.
- [ ] Tracker row flips from `⬜ in-progress` to `✅ shipped`.

## 7. Testing plan

Per CLAUDE.md: Swift Testing (`@Test`, `#expect`), no SwiftUI layout tests.

**New test files** (one per coordinator): `ScoringCoordinatorTests.swift` (4 tests), `PlaybackCoordinatorTests.swift` (6 tests), `PlayAlongChromeStateTests.swift` (3 tests), `NoteRouterTests.swift` (5 tests). **~18 new `@Test` functions**.

**Pre-existing PlayAlong tests:** all 8 suites (`PlayAlongFullFlowTests`, `PlayAlongIntegrationTests`, `PlayAlongThemeIntegrationTests`, `PlayAlongChromeTests`, `PlayAlongGestureTests`, `ChordScoringIntegrationTests`, `PlayAlongViewModelTests`, `PlayAlongTempoScalingTests`) are regression guards. None should be modified; all must pass at every phase.

**Latency gates** (per-phase merge gate):
```bash
xcodebuild ... -only-testing:SurVibeTests/LatencyContractTests test
```
Must show `featureFlagToggleDoesNotRestartEngine` + `rotationDoesNotRestartAudioEngine` green.

**p95 baseline capture:** Phase 3a's first commit measures `LatencyProbe` p95 over 200 iterations. Every subsequent phase's verification re-measures; delta must stay ≤ 0.5 ms.

**Smoke tests (manual, per phase):**
1. Launch app on iPad simulator, open a song, play-along, verify no audio glitches.
2. Rotate mid-playback. Verify audio continuous, no restart.
3. Cmd+Space to play/pause (SP-2 TransportActions). Verify.
4. Toggle `FeatureFlag.playAlongViewModelV2` in DEBUG diagnostics. Verify no audio restart (SP-0 F1 still green).

## 8. Rollout

**4 separate PRs**, each:
1. Own branch `feat/sp-3X-<coordinator-name>` off `main`.
2. Own merge commit to `main`.
3. Own tag (`sp-3a-scoring`, etc.).
4. Own latency-gate verification.

**Between phases:** `main` stays shippable. Coordinators are additively extracted; facade grows delegation layers; no call site breaks.

**Merge gates (per phase):**
- `/check` green.
- `/latency-check` green — with p95 delta ≤ 0.5 ms.
- All 8 PlayAlong test suites green.
- Hardcoded-logic grep = 0 hits.
- Per-coordinator unit tests green.

**No feature flag.** Git revert of a phase's merge SHA is the rollback mechanism.

## 9. Risks & open questions

### Resolved pre-spec

- ✅ `@Observable` nested-composition verified as Swift 5.9+ standard pattern — existing comment at VM line 1-4 was about extension files, not new classes.
- ✅ 20 call sites — facade preserves all; deleting class would have required rewriting 6 test suites + 4 view files.
- ✅ Chord detection belongs in NoteRouter — `runChordDetectionLoop` already lives inside the Pitch Detection block at line 1049.
- ✅ `ScoringCoordinator` is pure MainActor computation; `SPSCRingBuffer` not needed for note-event handoff (both sides are `@MainActor`).
- ✅ Zero platform hardcoding in current VM — SP-3 preserves this.
- ✅ `modelContext` optional, owned by `PlaybackCoordinator` only.

### Open (flagged for phase plans)

1. **SP-3a:** confirm `NoteScoreCalculator` (SVLearning) stays a pure helper; ScoringCoordinator calls it but doesn't own it.
2. **SP-3b:** verify `PlaybackScheduling` task cancellation semantics survive the extraction. Today the task reference lives on the VM; it needs to live on `PlaybackCoordinator` now.
3. **SP-3b:** `completeSession()` at line ~1720 writes `SongProgress` to `modelContext`. Confirm the exact write path when plan-time reading the full method body.
4. **SP-3c:** `AppThemeManager.resolvePlayAlongColors(...)` or similar — verify the existing API for theme resolution and how chrome coordinates.
5. **SP-3d:** `MIDINoteHighlightCoordinator` ownership — currently referenced by VM; after split it should be constructed by `NoteRouter`. Confirm its init signature and lifecycle.
6. **SP-3d:** `SPSCRingBuffer` usage — audit the existing DSP pipeline to confirm ring-buffer drains happen from the `NoteRouter` (not from anywhere else).

### Deliberate non-risks

- No release shipped → no back-compat concerns.
- No feature-flag gating needed; git revert is the safety net.
- No Mac destination enablement → SP-6 territory; SP-3 only preserves portability.
- No `AudioEngineManager` changes → CLAUDE.md's single-engine rule preserved.

## 10. Exit checklist (Umbrella)

SP-3 ships only when ALL of these are true:

- [ ] All 4 phase tags created and merged: `sp-3a-scoring`, `sp-3b-playback`, `sp-3c-view-chrome`, `sp-3d-note-router`.
- [ ] `PlayAlongViewModel.swift` ≤ 200 lines.
- [ ] `// swiftlint:disable file_length` directive deleted.
- [ ] `LatencyContractTests` both tests green with p95 delta ≤ 0.5 ms.
- [ ] All 8 PlayAlong test suites green.
- [ ] 4 new coordinator test suites green with ≥ 18 new `@Test` functions.
- [ ] Hardcoded-logic grep on `SurVibe/PlayAlong/` = 0 hits.
- [ ] `sp-3-vm-split-complete` umbrella tag on the final merge SHA.
- [ ] SP-TRAJECTORY-TRACKER.md SP-3 row flipped from `⬜ in-progress` to `✅ shipped`.

Next: **SP-4** — Accessibility polish + iOS in-app Settings navigation. Consumes SP-0 `PreferenceStoring` protocol + SP-3's clean coordinator boundaries (SP-4 haptics wiring goes into `ScoringCoordinator` for achievement/correct-note/XP; accessibility labels touch `PlayAlongChromeState`).

## 11. SP-3b plan-time refinements (locked 2026-04-19)

Captured after plan-time code reading + brainstorming with the user. These refinements supersede §5.2's signature sketch where they conflict; §5.2's *separation of concerns* is preserved exactly.

### D-SP3b-1 — Coordinator exposes domain verbs, not user-action verbs (Option B)

§5.2 listed `loadSong / startSession / pauseSession / resumeSession / stopAndComplete / seek / cleanup` on `PlaybackCoordinator`. Plan-time code reading showed `startSession / pauseSession / resumeSession / cleanup` interleave **playback** concerns (engine.start, scheduling, displayLink, metronome, soundFont, waitController) with **NoteRouter** concerns (`startMIDIDetection`, `startPitchDetection`, mic permission, `configureRagaContext`, `updateExpectedMidiNote`, `guidedPlayState`, `startPatienceTimer`). NoteRouter doesn't ship until SP-3d.

**Locked decision:** `PlaybackCoordinator` exposes scheduling-domain verbs:

```swift
@Observable @MainActor final class PlaybackCoordinator {
    func loadSong(_ song: Song) async -> Bool   // returns false on parse failure
    func startScheduling() async                 // engine.start + reset + schedule + displayLink + metronome
    func pauseScheduling()                       // saves pauseElapsed + cancels playback tasks + metronome.stop
    func resumeScheduling()                      // advances playbackStartTime + reschedules + metronome.start
    func stopAndComplete()                       // → completeSession()
    func seek(to progress: Double)
    func cleanup()                               // playback-side resources only
}
```

`PlayAlongViewModel` (facade) preserves the public `startSession / pauseSession / resumeSession / cleanup / loadSong` API by composing `playback.*` with the still-on-VM NoteRouter-territory work. Facade methods become tiny:

```swift
func startSession() async {
    await playback.startScheduling()
    startPitchDetection()  // SP-3d will become: await noteRouter.startPitchDetection()
}
```

**Why Option B over Option A (closure-DI to spec-literal verbs):**
- Apple's incremental-migration guidance ([Migrating to Observable macro](https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro)) rewards honest boundaries over speculative scaffolding.
- Option A's `playback.onAfterStart = { … }` closure plumbing exists ONLY because NoteRouter doesn't exist yet — provisional API surface that either gets deleted in SP-3d (API churn) or lives forever as zombie code.
- Option B makes `PlaybackCoordinator`'s API **final at SP-3b**. SP-3d only edits the facade, never the coordinator.
- No release shipped → no compat reason to preserve §5.2's exact verb names. Spec named the *separation*; Option B honors it more faithfully.

### D-SP3b-2 — `waitController` is internal, not constructor-injected

§5.2 listed `waitController: PlayAlongWaitController` as a constructor dependency. Reality on `main`: `waitController` is `private var waitController: PlayAlongWaitController?`, constructed inside `startSession` based on `isWaitModeEnabled`, niled in `cleanup` ([PlayAlongViewModel.swift:597-601, 786-787](SurVibe/PlayAlong/PlayAlongViewModel.swift)). Lifecycle stays internal to `PlaybackCoordinator`.

### D-SP3b-3 — `metronome` keeps its real protocol type

§5.2 wrote `metronome: MetronomeScheduling`. Real type on `main` is `any MetronomePlaying` ([PlayAlongViewModel.swift:320](SurVibe/PlayAlong/PlayAlongViewModel.swift:320)). Plan uses the real type.

### D-SP3b-4 — Persistence delegated to `PracticeSessionRecorder` (no direct SongProgress writes)

§5.2 said PlaybackCoordinator "writes SongProgress." Reality: VM uses `PracticeSessionRecorder.recordSession(...)` ([PlayAlongViewModel.swift:1726](SurVibe/PlayAlong/PlayAlongViewModel.swift:1726)) — already a tidy abstraction. PlaybackCoordinator keeps using the recorder; no direct `@Model` writes.

### D-SP3b-5 — Analytics threaded via `AnalyticsProviding` nil-sentinel

Per SP-0 D-SP0-1 / SP-1 D-SP1-1 pattern: `init(analytics: (any AnalyticsProviding)? = nil)`. Internal call sites do `(analytics ?? AnalyticsManager.shared).track(...)`. Avoids `@MainActor` default-parameter isolation issues. Three `.track()` sites move from VM into `PlaybackCoordinator`: `songPlaybackStarted`, `songPlaybackPaused`, `songPlaybackCompleted`.

### Acceptance criteria — refined for SP-3b

§6's SP-3b checklist remains authoritative. The *coordinator method names* in that checklist read as the new Option-B verbs. The behavioural acceptance — TransportActions bindings (`togglePlayPause`, `seek(by:)`, `stop`) keep dispatching correctly via the facade, session completion still writes to `modelContext` via `PracticeSessionRecorder`, both latency gates green, all 8 PlayAlong suites green — is unchanged.

## 12. SP-3c plan-time refinements (locked 2026-04-20, post-SP-3b merge)

Captured after plan-time code reading on `main` post-SP-3b merge (commit `4ca65ae`). Adjusts §5.3 where reality and the spec diverge. Same Option-B-style "honest boundaries over speculative scaffolding" reasoning as SP-3b §11.

### D-SP3c-1 — `latencyPreset` stays on VM, defers to SP-3d

§5.3 listed `latencyPreset: LatencyPreset = .fast` on `PlayAlongChromeState`. Plan-time code reading shows `latencyPreset`'s `didSet` at [PlayAlongViewModel.swift:159-167](SurVibe/PlayAlong/PlayAlongViewModel.swift) calls `audioProcessor.stop()` + `startPitchDetection()` — pure NoteRouter territory. Moving to chrome state would require either (a) closure DI (the Option-A pattern rejected for SP-3b), or (b) splitting the persisted property from its side-effect (cosmetic separation that doesn't reduce VM size).

**Locked decision:** `latencyPreset` stays on `PlayAlongViewModel` for SP-3c. SP-3d moves it alongside NoteRouter (which inherits the side-effect) so the property and its consequence ship together. No release shipped → spec adjustable.

### D-SP3c-2 — Theme colors stay as 7 individual `@ObservationIgnored` properties

§5.3 proposed bundling the 7 color properties into a `ResolvedPlayAlongColors` struct. Reality: views read `viewModel.rhColor`, `viewModel.lhColor`, etc. directly (verified via grep across `SurVibe/PlayAlong/`). Today these are `@ObservationIgnored` because they're set once at view `.task` and don't trigger re-renders.

Wrapping them into an `@Observable` struct field on the chrome coordinator would change observation semantics — theme changes mid-play would propagate to views (they don't today). Strict "no behavior changes" mandate (spec §1) forbids this.

**Locked decision:** keep the 7 individual properties as `@ObservationIgnored` stored properties on `PlayAlongChromeState`. Facade re-exposes each as a delegating computed property so `viewModel.rhColor` continues to work. SP-3c-or-later optimization to bundle into a struct is a separate, behavior-changing project.

### D-SP3c-3 — `updateTheme(_:)` method centralizes color resolution

§5.3 proposed `updateTheme(_ themeManager: AppThemeManager)` on the chrome coordinator. Reality: theme color assignment lives inline in [SongPlayAlongView.swift:219-225, 246-249](SurVibe/PlayAlong/SongPlayAlongView.swift) — the view does 7 manual reads of `themeManager.resolved.X` and assigns to `viewModel.X`.

**Locked decision:** chrome coordinator gets `updateTheme(_ themeManager: AppThemeManager)`. The view replaces 14 lines of inline assignment with a single `chrome.updateTheme(themeManager)` call (or `viewModel.chrome.updateTheme(themeManager)` if accessed via facade). Behavior identical (same `themeManager.resolved.X` reads, same color targets), responsibility cleaner.

### D-SP3c-4 — `chromeAutoHideSeconds` becomes `static let autoHideDuration`

§5.3 proposed `static let autoHideDuration: TimeInterval = 6.0`. Today VM has `var chromeAutoHideSeconds: Double = 6.0` (line 249). The value is never reassigned in production code — confirmed via grep. Magic number → named static let with docstring per spec §1's hardcoded-logic discipline.

**Locked decision:** `static let autoHideDuration: TimeInterval = 6.0` on `PlayAlongChromeState`. The VM's old `var chromeAutoHideSeconds` is removed (no callers outside the chrome methods that move into the coordinator).

### D-SP3c-5 — Analytics not threaded (no track sites in chrome state)

§5.3 didn't list analytics as a dependency. Confirmed: chrome visibility methods (`summonChrome`, `hideChrome`, `resetAutoHide`) and view-mode setters do NOT fire analytics today. No `init(analytics:)` parameter needed on the chrome coordinator. Simpler init than `PlaybackCoordinator`.

**Locked decision:** chrome coordinator init takes zero dependencies — `init()` is sufficient. (Could add `themeManager` later if `updateTheme` becomes "configure once at init" instead of "call from view's `.task`," but that's a separate refactor and doesn't fit SP-3c's scope.)

### Acceptance criteria — refined for SP-3c

§6's SP-3c checklist remains authoritative. The behavioural acceptance — `PlayAlongChromeTests` (6 existing tests) continue to pass against the facade-delegated chrome state, view-side theme color reads still produce the same colors, auto-hide timer behaves identically — is unchanged.
