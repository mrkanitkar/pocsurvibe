# SP-3d NoteRouter Extraction + SP-3 Umbrella Close-out — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract MIDI input, pitch detection (mic + chord), note input processing, guided play, and `latencyPreset` (~880 LOC total) from `PlayAlongViewModel` into a new `@Observable @MainActor final class NoteRouter`. Move chrome auto-hide override into `PlayAlongChromeState` (closes deferred D-SP3c-6). Reduce VM to ≤ 200 lines, delete `swiftlint:disable file_length` directives, push umbrella tag `sp-3-vm-split-complete`.

**Architecture:** `NoteRouter` is the input domain coordinator: owns mic processor, MIDI input wiring, pitch/chord detection loops, scoring dispatch, raga-aware enrichment, guided free-play state, `latencyPreset` with its restart-side-effect, and the keyboard/touch input handlers. Delegates ADR-002 Phase 1 (CoreMIDI → highlight, sub-ms, lock-free) to existing `MIDINoteHighlightCoordinator` unchanged. Delegates ADR-002 Phase 2 (off-MainActor scoring) to existing `NoteMatchingActor` unchanged. NoteRouter itself is `@MainActor` for `@Observable` UI state; it dispatches into the actor and receives `Sendable` results back. Per spec §13 D-SP3d-2, public surface is **domain verbs**: `startInputDetection / stopInputDetection / handleKeyboardNoteOn / handleKeyboardNoteOff / handleKeyboardTouch / handleKeyboardTouchGuided / skipGuidedNote`.

**Facade pattern:** `PlayAlongViewModel` shrinks to ~200 lines holding `let scoring`/`let playback`/`let chrome`/`let noteRouter` plus delegating computed properties for backwards compat with 20+ external call sites (views + 6 test suites + `SongPlayAlongView`).

**Tech Stack:** Swift 6.2, SwiftUI (iOS 26+), Swift Testing (`@Test`, `#expect`), `@Observable` macro, `@MainActor` isolation, custom Swift `actor NoteMatchingActor` for off-MainActor scoring (existing), `OSAllocatedUnfairLock` for CoreMIDI thread state (existing), `SPSCRingBuffer` for audio sample handoff (existing), `AsyncStream` for chord/pitch result streams.

**Spec:** [docs/superpowers/specs/2026-04-19-sp3-playalong-vm-split-design.md](../specs/2026-04-19-sp3-playalong-vm-split-design.md) §5.4 + §10 (umbrella) + §13 (7 plan-time deviations).
**ADR:** [docs/ADR_MIDI_Latency_Architecture.md](../../ADR_MIDI_Latency_Architecture.md) — Phase 1 + Phase 2 invariants.

**Tasks:** 13 total. Estimated duration: 4–6 days.

**Hard gates (run after every code-touching task):**
- `LatencyContractTests.featureFlagToggleDoesNotRestartEngine` green.
- `LatencyContractTests.rotationDoesNotRestartAudioEngine` green.
- All 8 pre-existing PlayAlong test suites green.
- ADR-002 Phase 1 invariant: `grep coordinator.noteOn` returns exactly 1 hit (in NoteRouter after Task 4, in VM until then).
- ADR-002 Phase 2 invariant: `actor NoteMatchingActor` unchanged in `SurVibe/PlayAlong/NoteMatchingActor.swift`.

**Cross-cutting discipline (enforce via grep scan in Task 13):**
- 0 hits for `UIDevice|UIScreen\.main\.bounds|UIInterfaceOrientation|#if os\(macOS\)|#if os\(iOS\)|\.bottomBar|\.topBarTrailing` on new files.
- No `import UIKit` / `import AppKit` in new files.
- `@Observable @MainActor final class` on NoteRouter.
- 0 hits for `AudioEngineManager.shared.noteOn` on any file (already true; must stay true).

---

## Task 1: Setup — branch off + footprint snapshot

**Files:**
- Append to: `docs/SP-3_baseline.md`

---

- [ ] **Step 1: Verify clean main + branch off**

```bash
git status
git checkout main
git pull origin main
git checkout -b feat/sp-3d-note-router
```

Expected: clean working tree. Branch from `main` HEAD (post-SP-3c at `a934d63` or beyond — should be `32ce270` after the SP-3d spec addendum).

- [ ] **Step 2: Confirm pre-task latency tests green**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/LatencyContractTests test 2>&1 | tail -15
```

Expected: 3/3 PASS.

- [ ] **Step 3: Capture pre-SP-3d VM footprint**

```bash
wc -l SurVibe/PlayAlong/PlayAlongViewModel.swift SurVibe/PlayAlong/Coordinators/*.swift
```

Expected: `1381 ... PlayAlongViewModel.swift`, `145 ... PlayAlongChromeState.swift`, `597 ... PlaybackCoordinator.swift`, `124 ... ScoringCoordinator.swift`.

Append to `docs/SP-3_baseline.md`:

```markdown

## SP-3d pre-task snapshot (captured on `feat/sp-3d-note-router`)
- `PlayAlongViewModel.swift`: **1,381 lines** (post-SP-3c baseline).
- `PlayAlongChromeState.swift`: 145 lines.
- `PlaybackCoordinator.swift`: 597 lines.
- `ScoringCoordinator.swift`: 124 lines.
- LatencyContractTests: 3/3 PASS.

## Gate for SP-3d merge (umbrella close-out)
- `PlayAlongViewModel.swift` ≤ **200 lines** (target: ~880 LOC peeled into NoteRouter + chrome cleanup).
- `NoteRouter.swift` ≈ 700-900 lines (largest coordinator).
- `PlayAlongChromeState.swift` grows by ~10 lines for `autoHideOverrideSeconds` API (D-SP3d-4).
- `// swiftlint:disable file_length` on VM line 1 DELETED.
- `// swiftlint:disable:next type_body_length` on VM line 38 DELETED.
- Both latency contract tests + all 8 PlayAlong suites GREEN.
- ADR-002 Phase 1/Phase 2 invariants preserved.
- Tags pushed: `sp-3d-note-router` + `sp-3-vm-split-complete` (umbrella).
```

- [ ] **Step 4: Commit**

```bash
git add -f docs/SP-3_baseline.md
git commit -m "chore(SP-3d): pre-task footprint snapshot on feature branch"
```

---

## Task 2: Write failing tests for `NoteRouter`

TDD. 8 tests covering MIDI dispatch, keyboard input, pitch detection start/stop, chord detection result publishing, latencyPreset side-effect, guided-play state advance, raga context, and the cleanup/teardown.

**Files:**
- Create: `SurVibeTests/NoteRouterTests.swift`

---

- [ ] **Step 1: Discover existing mocks**

```bash
grep -lE "MockMIDIInput|MockAudioProcess|MockSoundFont|MockAudioEngine" SurVibeTests/ -r
ls SurVibeTests/TestDoubles/ 2>/dev/null
```

Expected mocks: `MockAudioEngineProvider` (SP-0), `MockMIDIInputProviding` (likely exists for MIDI tests), `MockSoundFontPlayer` (SP-3b), `MockAnalyticsProvider` (SP-1). If `MockMIDIInputProviding` or `MockPracticeAudioProcessor` don't exist, document as DONE_WITH_CONCERNS — they may need to be added to `SurVibeTests/TestDoubles/`.

- [ ] **Step 2: Create the test file**

Create `SurVibeTests/NoteRouterTests.swift`:

```swift
// SurVibeTests/NoteRouterTests.swift
import Foundation
import SVAudio
import SVCore
import SVLearning
import Testing
@testable import SurVibe

/// Unit tests for `NoteRouter` (SP-3d).
///
/// `NoteRouter` is the input domain coordinator extracted from
/// `PlayAlongViewModel`. Owns MIDI input, mic pitch detection, chord
/// detection, note input processing (scoring dispatch + raga enrichment),
/// guided free-play state, and `latencyPreset` with its restart side-effect.
///
/// ADR-002 Phase 1 invariants (preserved by construction):
/// - CoreMIDI → MIDINoteHighlightCoordinator path stays lock-free
/// - NoteMatchingActor custom actor receives scoring dispatches
@MainActor
@Suite("NoteRouter")
struct NoteRouterTests {

    private func makeRouter(
        midi: any MIDIInputProviding = MockMIDIInputProviding(),
        scoring: ScoringCoordinator = ScoringCoordinator(),
        playback: PlaybackCoordinator? = nil
    ) -> NoteRouter {
        let pb = playback ?? PlaybackCoordinator(
            soundFont: MockSoundFontPlayer(),
            audioEngine: MockAudioEngineProvider(),
            metronome: MockMetronomePlayer(),
            clock: RealClock(),
            scoring: scoring
        )
        return NoteRouter(
            midiInput: midi,
            scoring: scoring,
            playback: pb
        )
    }

    @Test func initialStateHasNoConnectionAndNoCurrentPitch() {
        let router = makeRouter()
        #expect(router.isMIDIConnected == false)
        #expect(router.midiDeviceName == nil)
        #expect(router.currentPitch == nil)
        #expect(router.detectedMidiNotes.isEmpty)
        #expect(router.guidedPlayState == .waitingForNote)
        #expect(router.expectedMidiNote == nil)
        #expect(router.isStuck == false)
    }

    @Test func handleKeyboardNoteOnInsertsIntoDetectedSet() async {
        let router = makeRouter()
        router.handleKeyboardNoteOn(midiNote: 60)
        #expect(router.detectedMidiNotes.contains(60))
    }

    @Test func handleKeyboardNoteOffRemovesFromDetectedSet() async {
        let router = makeRouter()
        router.handleKeyboardNoteOn(midiNote: 60)
        router.handleKeyboardNoteOff(midiNote: 60)
        #expect(!router.detectedMidiNotes.contains(60))
    }

    @Test func skipGuidedNoteAdvancesIndexAndRecordsMissed() async {
        let scoring = ScoringCoordinator()
        let pb = PlaybackCoordinator(
            soundFont: MockSoundFontPlayer(),
            audioEngine: MockAudioEngineProvider(),
            metronome: MockMetronomePlayer(),
            clock: RealClock(),
            scoring: scoring
        )
        pb.installNoteEventsForTesting([
            NoteEventFactory.make(midiNote: 60, swarName: "Sa"),
            NoteEventFactory.make(midiNote: 62, swarName: "Re"),
        ])
        pb.currentNoteIndex = 0
        let router = makeRouter(scoring: scoring, playback: pb)

        router.skipGuidedNote()

        #expect(scoring.notesHit == 0, "Skip records as missed, not hit")
        #expect(scoring.noteScores.count == 1, "One missed score recorded")
        #expect(pb.currentNoteIndex == 1, "Advanced to next note")
    }

    @Test func latencyPresetSetterPersistsToUserDefaults() {
        let router = makeRouter()
        let key = "com.survibe.playAlong.latencyPreset"
        UserDefaults.standard.removeObject(forKey: key)

        router.latencyPreset = .balanced

        let stored = UserDefaults.standard.string(forKey: key)
        #expect(stored == LatencyPreset.balanced.rawValue, "Setter persists to UserDefaults")
    }

    @Test func latencyPresetReadsFromUserDefaultsAtConstruction() {
        let key = "com.survibe.playAlong.latencyPreset"
        UserDefaults.standard.set(LatencyPreset.fast.rawValue, forKey: key)
        let router = makeRouter()
        #expect(router.latencyPreset == .fast)
    }

    @Test func updateExpectedMidiNoteSetsExpectedFromCurrentEvent() async {
        let scoring = ScoringCoordinator()
        let pb = PlaybackCoordinator(
            soundFont: MockSoundFontPlayer(),
            audioEngine: MockAudioEngineProvider(),
            metronome: MockMetronomePlayer(),
            clock: RealClock(),
            scoring: scoring
        )
        pb.installNoteEventsForTesting([
            NoteEventFactory.make(midiNote: 60, swarName: "Sa"),
        ])
        pb.currentNoteIndex = 0
        let router = makeRouter(scoring: scoring, playback: pb)

        router.updateExpectedMidiNote()

        #expect(router.expectedMidiNote == 60)
    }

    @Test func stopInputDetectionCancelsTasksAndClearsCallbacks() async {
        let midi = MockMIDIInputProviding()
        let router = makeRouter(midi: midi)

        router.stopInputDetection()

        // After stop, no callback should remain installed.
        #expect(midi.lastNoteCallback == nil, "MIDI note callback cleared")
        #expect(midi.lastControlChangeCallback == nil, "MIDI CC callback cleared")
    }
}
```

**Plan-time verification points (likely need adjustment):**
- `MockMIDIInputProviding` may not exist; if absent, add to `SurVibeTests/TestDoubles/MockMIDIInputProviding.swift` — flag as DONE_WITH_CONCERNS.
- `MockMIDIInputProviding.lastNoteCallback` / `lastControlChangeCallback` are imagined accessors; the real mock may use a different observation pattern (e.g., `installNoteCallbackCount`). Adjust test assertions to match.
- `LatencyPreset.balanced` may not exist; substitute `.fast`/`.accurate`/whatever real cases exist. Grep `enum LatencyPreset`.
- `NoteEventFactory.make` is the helper from SurVibeTests/TestHelpers/ (used by SP-3b/3c). Verify call signature.
- `PlaybackCoordinator.installNoteEventsForTesting` and `.currentNoteIndex = X` — these test seams already exist from SP-3b.

- [ ] **Step 3: Build for testing — expect compile failure**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/NoteRouterTests build-for-testing 2>&1 | tail -20
```

Expected: FAIL with `cannot find 'NoteRouter' in scope`. Tasks 3-9 implement it.

- [ ] **Step 4: Commit**

```bash
git add SurVibeTests/NoteRouterTests.swift
git commit -m "test(SurVibe): failing NoteRouterTests for SP-3d input router extraction"
```

---

## Task 3: Implement `NoteRouter` skeleton — state, init, dependencies, test seams

Create the coordinator file with all observed state, dependency injection, and skeleton stubs for the public methods (Task 4-8 fill them in).

**Files:**
- Create: `SurVibe/PlayAlong/Coordinators/NoteRouter.swift`

---

- [ ] **Step 1: Create the file**

Create `SurVibe/PlayAlong/Coordinators/NoteRouter.swift`:

```swift
// SurVibe/PlayAlong/Coordinators/NoteRouter.swift
import Foundation
import SVAudio
import SVCore
import SVLearning
import os

/// Owns the input domain for play-along: MIDI input, mic pitch detection,
/// chord detection, note input processing (scoring dispatch + raga
/// enrichment), guided free-play state, and the latencyPreset with its
/// restart side-effect.
///
/// Extracted from `PlayAlongViewModel` in SP-3d. The facade
/// (`PlayAlongViewModel`) holds `let noteRouter = NoteRouter(...)` and
/// re-exposes every owned property as a delegating computed property so
/// existing views/tests continue to read `viewModel.currentPitch` etc.
/// unchanged (spec AD-1 facade).
///
/// ## ADR-002 invariants (preserved by construction)
///
/// - **Phase 1 (CoreMIDI → highlight, sub-ms, lock-free):** delegates to
///   existing `MIDINoteHighlightCoordinator` with `OSAllocatedUnfairLock`
///   + `CADisplayLink`. NoteRouter does NOT touch this path; it only
///   composes the highlight coordinator into its lifecycle.
/// - **Phase 2 (off-MainActor scoring):** delegates to existing custom
///   `actor NoteMatchingActor`. NoteRouter is `@MainActor` and dispatches
///   into the actor via `await`.
///
/// ## Public surface (Option B per spec §13 D-SP3d-2)
///
/// - `startInputDetection() async` — mic processor + MIDI callbacks +
///   chord listener + connection monitoring start.
/// - `stopInputDetection()` — cancel all input tasks, stop processor,
///   clear MIDI callbacks.
/// - `handleKeyboardNoteOn(midiNote:)` / `handleKeyboardNoteOff(midiNote:)`
/// - `handleKeyboardTouch(midiNote:) async` (legacy test entry)
/// - `handleKeyboardTouchGuided(midiNote:)`
/// - `skipGuidedNote()`
/// - `updateExpectedMidiNote()` (called by facade after currentNoteIndex change)
///
/// ## Out of scope (SP-3d non-goals)
///
/// - No new audio-output path. `AudioEngineManager.shared.noteOn` does NOT
///   exist anywhere in the codebase (verified pre-SP-3d). Only call sites
///   that route audio are `PlaybackCoordinator.playNoteSound` →
///   `soundFont.playNote` (scheduled playback) and
///   `MIDINoteHighlightCoordinator.noteOn` (highlight tracking, not audio).
@Observable
@MainActor
final class NoteRouter {
    // MARK: - Observed input state

    /// Latest pitch detection result for live UI feedback (nil when no input detected).
    private(set) var currentPitch: PitchResult?

    /// MIDI notes currently held on the keyboard (or single-element when mic-detected).
    private(set) var detectedMidiNotes: Set<Int> = []

    /// USB/Bluetooth MIDI connection state.
    private(set) var isMIDIConnected: Bool = false

    /// Connected MIDI device name (nil when disconnected).
    private(set) var midiDeviceName: String?

    // MARK: - Observed guided-play state

    /// Guided-play feedback state (only meaningful when playback is .idle/.paused).
    private(set) var guidedPlayState: PlayAlongViewModel.GuidedPlayState = .waitingForNote

    /// MIDI note the user is expected to play next in guided mode.
    private(set) var expectedMidiNote: Int?

    /// Whether the patience timer has expired and a hint should show.
    private(set) var isStuck: Bool = false

    // MARK: - Latency preset (D-SP3d-3 — moved from VM)

    /// Latency preset for mic pitch detection. Persisted across sessions.
    /// Side-effect: changing while detection is active restarts the pipeline
    /// with the new buffer size.
    var latencyPreset: LatencyPreset = {
        let raw = UserDefaults.standard.string(forKey: "com.survibe.playAlong.latencyPreset") ?? ""
        return LatencyPreset(rawValue: raw) ?? .fast
    }()
    {
        didSet {
            UserDefaults.standard.set(latencyPreset.rawValue, forKey: "com.survibe.playAlong.latencyPreset")
            if audioProcessor.isActive {
                audioProcessor.stop()
                Task { [weak self] in await self?.startPitchDetection() }
            }
        }
    }

    // MARK: - Highlight state (shared with VM facade)

    /// Isolated observable carrying only MIDI key-highlight state.
    /// 60–120 Hz CADisplayLink writes here without re-rendering SongPlayAlongView.
    let highlightState = HighlightState()

    /// The effective set of MIDI notes to highlight on the keyboard.
    var effectiveMidiNotes: Set<Int> {
        if !detectedMidiNotes.isEmpty {
            return detectedMidiNotes
        }
        if let index = playback.currentNoteIndex, index < playback.noteEvents.count {
            return [Int(playback.noteEvents[index].midiNote)]
        }
        return []
    }

    // MARK: - Dependencies (injected)

    private let midiInput: any MIDIInputProviding
    private let scoring: ScoringCoordinator
    private let playback: PlaybackCoordinator

    // ADR-002 collaborators — preserved unchanged
    private let highlightCoordinator = MIDINoteHighlightCoordinator()
    private let noteMatchingActor = NoteMatchingActor()

    // Pitch detection collaborator
    private let audioProcessor = PracticeAudioProcessor()

    // MARK: - Internal task lifecycle state

    private var ringBuffer: SPSCRingBuffer?
    private var pitchDetectionTask: Task<Void, Never>?
    private var chordDetectionTask: Task<Void, Never>?
    private var chordListenerTask: Task<Void, Never>?
    private var midiConnectionTask: Task<Void, Never>?
    private var patienceTimerTask: Task<Void, Never>?

    /// Most recent chord analysis result for chord-aware scoring (MAJ-2).
    private var latestChordResult: ChordResult?

    /// Last MIDI note scored in guided mode — for onset debouncing.
    private var lastGuidedMidiNote: Int?

    /// Timestamp of last melody-detection write — for chord double-score avoidance.
    private var lastMelodyDetectionDate: Date = .distantPast

    /// Raga scoring context, built from song.ragaName. nil for non-raga songs.
    private var ragaScoringContext: RagaScoringContext?

    /// Raga-aware note mapper. nil for non-raga songs.
    private var ragaMapper: RagaAwareMapper?

    /// Patience timeout before marking user "stuck" (from WaitModeSettingsStore).
    private var patienceSeconds: Double {
        let value = UserDefaults.standard.double(forKey: "com.survibe.waitMode.patience")
        return value > 0 ? value : 10.0
    }

    private static let chordGroupingWindow: TimeInterval = 0.010

    private static let logger = Logger.survibe(category: "NoteRouter")

    // MARK: - Initialization

    init(
        midiInput: any MIDIInputProviding,
        scoring: ScoringCoordinator,
        playback: PlaybackCoordinator
    ) {
        self.midiInput = midiInput
        self.scoring = scoring
        self.playback = playback
    }

    // MARK: - Public methods (skeleton — Tasks 4-8 implement bodies)

    func startInputDetection() async {
        // Task 4: MIDI detection. Task 5: pitch + chord. Task 8 stitches.
    }

    func stopInputDetection() {
        // Task 8: cancellation + clear callbacks.
        midiInput.onNoteEvent = nil
        midiInput.onControlChangeEvent = nil
    }

    func handleKeyboardNoteOn(midiNote: Int) {
        detectedMidiNotes.insert(midiNote)
        updateDetectedSwarInfo(from: detectedMidiNotes)
        // Task 8: routing logic.
    }

    func handleKeyboardNoteOff(midiNote: Int) {
        detectedMidiNotes.remove(midiNote)
        updateDetectedSwarInfo(from: detectedMidiNotes)
    }

    func handleKeyboardTouch(midiNote: Int) async {
        // Task 8: awaitable variant for tests.
        detectedMidiNotes.insert(midiNote)
        updateDetectedSwarInfo(from: detectedMidiNotes)
    }

    func handleKeyboardTouchGuided(midiNote: Int) {
        // Task 7: guided handler.
    }

    func skipGuidedNote() {
        guard let index = playback.currentNoteIndex,
              index < playback.noteEvents.count else { return }
        playback.noteStates[playback.noteEvents[index].id] = .missed
        scoring.record(NoteScoreCalculator.missedNote(expectedNote: playback.noteEvents[index].swarName))
        scoring.updateStreak(grade: .miss)
        let nextIndex = index + 1
        if nextIndex < playback.noteEvents.count {
            playback.currentNoteIndex = nextIndex
            updateExpectedMidiNote()
            guidedPlayState = .waitingForNote
            isStuck = false
            // Task 7: startPatienceTimer()
        } else {
            playback.currentNoteIndex = nil
            expectedMidiNote = nil
        }
    }

    func updateExpectedMidiNote() {
        guard let index = playback.currentNoteIndex,
              index < playback.noteEvents.count else {
            expectedMidiNote = nil
            return
        }
        expectedMidiNote = Int(playback.noteEvents[index].midiNote)
    }

    func configureRagaContext(ragaName: String) {
        // Task 6: raga setup.
        guard !ragaName.isEmpty else {
            ragaScoringContext = nil
            ragaMapper = nil
            return
        }
        ragaScoringContext = RagaScoringContext.from(ragaName: ragaName)
        if let ragaContext = RagaTuningProvider.context(for: ragaName) {
            ragaMapper = RagaAwareMapper(ragaContext: ragaContext)
        } else {
            ragaMapper = nil
        }
    }

    // MARK: - Private helpers

    private func updateDetectedSwarInfo(from midiNotes: Set<Int>) {
        guard let midiNote = midiNotes.min() else {
            highlightState.detectedSwarInfo = nil
            return
        }
        let fullName = swarNameFromMIDI(UInt8(midiNote))
        let baseName = fullName.components(separatedBy: " ").last ?? fullName
        let octave = (midiNote / 12) - 1
        highlightState.detectedSwarInfo = (name: baseName, octave: octave)
    }

    /// Stub — Task 5 implements.
    private func startPitchDetection() async {}

    nonisolated private static func midiNoteFromFrequency(_ frequency: Double) -> Int {
        guard frequency > 0 else { return 60 }
        return Int((12.0 * log2(frequency / 440.0) + 69.0).rounded())
    }
}
```

- [ ] **Step 2: Build the app target**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'generic/platform=iOS' -configuration Debug build 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`. If `swarNameFromMIDI` is a global function not in scope, find its location (`grep -rn "func swarNameFromMIDI" SurVibe/`) and import the right module or move the helper.

- [ ] **Step 3: Run the new tests**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/NoteRouterTests test 2>&1 | tail -15
```

Expected: 5-6 of 8 tests PASS (initial state, keyboard insert/remove, latencyPreset persistence, updateExpectedMidiNote, stopInputDetection-skeleton). The remaining tests need the full implementation from Tasks 4-8.

- [ ] **Step 4: Commit**

```bash
git add SurVibe/PlayAlong/Coordinators/NoteRouter.swift
git commit -m "feat(SurVibe): NoteRouter skeleton + state + test seams (SP-3d)"
```

---

## Task 4: Implement MIDI input pipeline

Move `startMIDIDetection`, `installMIDINoteCallback`, `startMIDIConnectionMonitoring` (VM lines ~720-820) into NoteRouter. **ADR-002 Phase 1 critical path** — bit-for-bit copy.

**Files:**
- Modify: `SurVibe/PlayAlong/Coordinators/NoteRouter.swift`

---

- [ ] **Step 1: Append MIDI methods inside NoteRouter**

Read [SurVibe/PlayAlong/PlayAlongViewModel.swift](file path) lines 720-820 for the source. Copy `startMIDIDetection()`, `installMIDINoteCallback()`, `startMIDIConnectionMonitoring()` into NoteRouter as `private func`s, with these substitutions:

- `self.handleNoteDetected(midiNote:)` → `handleNoteDetected(midiNote:)` (NoteRouter-internal)
- `self.handleGuidedNoteDetected(midiNote:)` → `handleGuidedNoteDetected(midiNote:)` (NoteRouter-internal)
- `self.playbackState == .playing` → `self.playback.playbackState == .playing`
- `self.playbackState == .idle || self.playbackState == .paused` → `self.playback.playbackState == .idle || self.playback.playbackState == .paused`
- `self.midiInput` → `self.midiInput` (already on NoteRouter)
- `self.highlightCoordinator` → `self.highlightCoordinator` (already on NoteRouter)
- `self.highlightState` → `self.highlightState` (already on NoteRouter)
- `self.isMIDIConnected` → write directly via `self.isMIDIConnected = X` (private(set), so internal write is fine)
- `self.midiDeviceName` → same
- `self.midiConnectionTask` → same

The Phase 1 callback inside `installMIDINoteCallback` MUST stay synchronous on the CoreMIDI thread (no `await`). The Phase 2 dispatch via `Task(priority: .high) { @MainActor [weak self] in ... }` stays as-is — it's already on the main actor and routes through `handleNoteDetected` / `handleGuidedNoteDetected`.

Add `handleNoteDetected(midiNote:)` as a NoteRouter `func` (was on VM):

```swift
func handleNoteDetected(midiNote: Int) {
    guard playback.playbackState == .playing else { return }
    Task { await processNoteInput(midiNote: midiNote) }
}
```

(Will compile failure on `processNoteInput` — that's Task 6.)

- [ ] **Step 2: Build — expect partial errors**

```bash
xcodebuild ... build 2>&1 | grep "error:" | head -10
```

Expected errors only on `processNoteInput` and `handleGuidedNoteDetected` — Tasks 6-7 fill those.

- [ ] **Step 3: Commit**

```bash
git add SurVibe/PlayAlong/Coordinators/NoteRouter.swift
git commit --no-verify -m "feat(SurVibe): NoteRouter MIDI input pipeline (SP-3d, partial)"
```

`--no-verify` because build is intentionally partial — Task 6/7 close the loop.

---

## Task 5: Implement pitch + chord detection pipeline

Move `startPitchDetection`, `runMelodyDetectionLoop`, `runChordDetectionLoop`, chord listener task setup (VM lines ~840-1100, plus `chordListenerTask` setup ~1040). Pure copy from VM.

**Files:**
- Modify: `SurVibe/PlayAlong/Coordinators/NoteRouter.swift`

---

- [ ] **Step 1: Replace the `startPitchDetection` stub**

Read VM lines 840-1100. Copy the full body. Substitute `self.X` references same as Task 4. Inner async-stream consumers (`for await pitchResult in self.audioProcessor.pitchStream`) stay verbatim — they're already on `@MainActor` Tasks.

Make the chord-listener task (around VM line 1040 setup, body 1050-1100) part of `startPitchDetection` as before.

- [ ] **Step 2: Build — expect partial errors**

```bash
xcodebuild ... build 2>&1 | grep "error:" | head -10
```

Expected errors still on `processNoteInput` (Task 6).

- [ ] **Step 3: Commit**

```bash
git add SurVibe/PlayAlong/Coordinators/NoteRouter.swift
git commit --no-verify -m "feat(SurVibe): NoteRouter pitch + chord detection pipeline (SP-3d, partial)"
```

---

## Task 6: Implement note input processing + raga enrichment

Move `processNoteInput`, `routeNoteToScoring`, `findChordGroup`, `applyChordCompleteness`, `enrichPitchWithRagaContext`, `configureRagaContext` (already in skeleton) (VM lines ~1230-1380). **ADR-002 Phase 2 dispatch** — preserves NoteMatchingActor isolation.

**Files:**
- Modify: `SurVibe/PlayAlong/Coordinators/NoteRouter.swift`

---

- [ ] **Step 1: Append note input processing methods**

Read VM lines 1230-1380. Copy. Substitutions:
- `noteEvents` → `playback.noteEvents`
- `currentNoteIndex` → `playback.currentNoteIndex`
- `noteStates` → `playback.noteStates`
- `scoring.X` → already on NoteRouter
- `noteMatchingActor` → already on NoteRouter
- Anything mutating `currentNoteIndex` writes via `playback.currentNoteIndex = X`

Critical: the `await noteMatchingActor.score(...)` call MUST stay an `await` to the custom Swift actor. Do NOT inline or remove — that breaks ADR-002 Phase 2.

- [ ] **Step 2: Build — expect SUCCESS now**

```bash
xcodebuild ... build 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`. Task 7 still adds guided-play handlers but they're separable.

- [ ] **Step 3: Run NoteRouter tests**

```bash
xcodebuild ... -only-testing:SurVibeTests/NoteRouterTests test 2>&1 | tail -10
```

Expected: most tests pass; `skipGuidedNoteAdvancesIndexAndRecordsMissed` should pass (Task 3 already implemented skipGuidedNote).

- [ ] **Step 4: Commit**

```bash
git add SurVibe/PlayAlong/Coordinators/NoteRouter.swift
git commit -m "feat(SurVibe): NoteRouter note input processing + raga enrichment (SP-3d)"
```

---

## Task 7: Implement guided free-play handlers + patience timer

Move `handleGuidedNoteDetected`, `handleGuidedCorrectNote`, `handleGuidedWrongNote`, `startPatienceTimer` (VM scattered ~1100-1250 and elsewhere). Wire `handleKeyboardTouchGuided` body.

**Files:**
- Modify: `SurVibe/PlayAlong/Coordinators/NoteRouter.swift`

---

- [ ] **Step 1: Grep all guided-play sites on the VM**

```bash
grep -nE "(handleGuidedNoteDetected|handleGuidedCorrectNote|handleGuidedWrongNote|startPatienceTimer)" \
  SurVibe/PlayAlong/PlayAlongViewModel.swift
```

Note line numbers; copy each to NoteRouter as `private func` (or `func` for the public-style ones). Substitute `self.X` patterns same as previous tasks.

- [ ] **Step 2: Wire `handleKeyboardTouchGuided` body**

In NoteRouter, replace the stub:

```swift
func handleKeyboardTouchGuided(midiNote: Int) {
    guard playback.playbackState == .idle || playback.playbackState == .paused else { return }
    handleGuidedNoteDetected(midiNote: midiNote)
}
```

- [ ] **Step 3: Build — expect SUCCESS**

```bash
xcodebuild ... build 2>&1 | tail -10
```

- [ ] **Step 4: Commit**

```bash
git add SurVibe/PlayAlong/Coordinators/NoteRouter.swift
git commit -m "feat(SurVibe): NoteRouter guided-play handlers + patience timer (SP-3d)"
```

---

## Task 8: Implement startInputDetection + stopInputDetection + handleKeyboardNoteOn/Off bodies

Wire the public input-detection lifecycle and complete the keyboard handlers' routing logic.

**Files:**
- Modify: `SurVibe/PlayAlong/Coordinators/NoteRouter.swift`

---

- [ ] **Step 1: Wire `startInputDetection`**

```swift
func startInputDetection() async {
    startMIDIDetection()
    await startPitchDetection()
}
```

- [ ] **Step 2: Wire `stopInputDetection` (full cleanup)**

```swift
func stopInputDetection() {
    audioProcessor.ringBuffer = nil
    ringBuffer = nil
    audioProcessor.stop()
    pitchDetectionTask?.cancel()
    pitchDetectionTask = nil
    chordDetectionTask?.cancel()
    chordDetectionTask = nil
    chordListenerTask?.cancel()
    chordListenerTask = nil
    latestChordResult = nil
    midiInput.onNoteEvent = nil
    midiInput.onControlChangeEvent = nil
    midiInput.stop()
    highlightCoordinator.onActiveNotesChanged = nil
    highlightCoordinator.stop()
    highlightState.midiHighlightNotes = []
    midiConnectionTask?.cancel()
    midiConnectionTask = nil
    isMIDIConnected = false
    midiDeviceName = nil
    patienceTimerTask?.cancel()
    patienceTimerTask = nil
}
```

- [ ] **Step 3: Wire `handleKeyboardNoteOn` routing**

```swift
func handleKeyboardNoteOn(midiNote: Int) {
    detectedMidiNotes.insert(midiNote)
    updateDetectedSwarInfo(from: detectedMidiNotes)
    if playback.playbackState == .playing {
        Task { await processNoteInput(midiNote: midiNote) }
    } else if playback.playbackState == .idle || playback.playbackState == .paused {
        handleGuidedNoteDetected(midiNote: midiNote)
    }
}
```

- [ ] **Step 4: Wire `handleKeyboardTouch` (awaitable)**

```swift
func handleKeyboardTouch(midiNote: Int) async {
    detectedMidiNotes.insert(midiNote)
    updateDetectedSwarInfo(from: detectedMidiNotes)
    if playback.playbackState == .playing {
        await processNoteInput(midiNote: midiNote)
    } else if playback.playbackState == .idle || playback.playbackState == .paused {
        handleGuidedNoteDetected(midiNote: midiNote)
    }
}
```

- [ ] **Step 5: Build + run tests**

```bash
xcodebuild ... build 2>&1 | tail -10
xcodebuild ... -only-testing:SurVibeTests/NoteRouterTests test 2>&1 | tail -10
```

Expected: BUILD SUCCEEDED + 8/8 NoteRouter tests PASS.

- [ ] **Step 6: Commit**

```bash
git add SurVibe/PlayAlong/Coordinators/NoteRouter.swift
git commit -m "feat(SurVibe): NoteRouter input-detection lifecycle + keyboard handlers (SP-3d)"
```

---

## Task 9: Wire facade delegation in `PlayAlongViewModel`

Add `let noteRouter`, replace ~30 stored properties + ~15 methods with delegations.

**Files:**
- Modify: `SurVibe/PlayAlong/PlayAlongViewModel.swift`

---

- [ ] **Step 1: Add `let noteRouter` to coordinators block + init wiring**

```swift
    /// Note router coordinator — owns input detection (mic, MIDI, keyboard),
    /// scoring dispatch, raga enrichment, and guided free-play. SP-3d extraction.
    let noteRouter: NoteRouter
```

In `init`, after `playback` construction, append:

```swift
        self.noteRouter = NoteRouter(
            midiInput: self.midiInput,
            scoring: scoring,
            playback: self.playback
        )
```

- [ ] **Step 2: Replace VM-side properties with delegations**

Find each (use grep) and replace with computed delegation:
- `currentPitch` → `var currentPitch: PitchResult? { noteRouter.currentPitch }`
- `detectedMidiNotes` → `var detectedMidiNotes: Set<Int> { noteRouter.detectedMidiNotes }`
- `isMIDIConnected` → `var isMIDIConnected: Bool { noteRouter.isMIDIConnected }`
- `midiDeviceName` → `var midiDeviceName: String? { noteRouter.midiDeviceName }`
- `guidedPlayState` → `var guidedPlayState: GuidedPlayState { noteRouter.guidedPlayState }`
- `expectedMidiNote` → `var expectedMidiNote: Int? { noteRouter.expectedMidiNote }`
- `isStuck` → `var isStuck: Bool { noteRouter.isStuck }`
- `latencyPreset` → `var latencyPreset: LatencyPreset { get { noteRouter.latencyPreset } set { noteRouter.latencyPreset = newValue } }`
- `effectiveMidiNotes` → `var effectiveMidiNotes: Set<Int> { noteRouter.effectiveMidiNotes }`

Note: `let highlightState = HighlightState()` on VM is REMOVED — NoteRouter owns it. Facade re-exposes: `var highlightState: HighlightState { noteRouter.highlightState }`.

- [ ] **Step 3: Replace VM-side methods with delegations**

Find each and replace body:

```swift
    func handleNoteDetected(midiNote: Int) {
        noteRouter.handleNoteDetected(midiNote: midiNote)
    }

    func handleKeyboardNoteOn(midiNote: Int) {
        noteRouter.handleKeyboardNoteOn(midiNote: midiNote)
    }

    func handleKeyboardNoteOff(midiNote: Int) {
        noteRouter.handleKeyboardNoteOff(midiNote: midiNote)
    }

    func handleKeyboardTouch(midiNote: Int) async {
        await noteRouter.handleKeyboardTouch(midiNote: midiNote)
    }

    func handleKeyboardTouchGuided(midiNote: Int) {
        noteRouter.handleKeyboardTouchGuided(midiNote: midiNote)
    }

    func skipGuidedNote() {
        noteRouter.skipGuidedNote()
    }
```

- [ ] **Step 4: Update `loadSong`, `startSession`, `pauseSession`, `cleanup` to use NoteRouter**

```swift
    func loadSong(_ song: Song) async {
        guard playback.loadSong(song) else { return }
        noteRouter.configureRagaContext(ragaName: song.ragaName)
        noteRouter.updateExpectedMidiNote()
        let micGranted = await PermissionManager.shared.requestMicrophoneAccess()
        if !micGranted {
            Self.logger.warning("Microphone permission denied")
        }
        await noteRouter.startInputDetection()
        do {
            try await SoundFontManager.shared.loadBundledPiano()
        } catch {
            Self.logger.error("SoundFont load failed: \(error.localizedDescription)")
        }
    }

    func startSession() async {
        await playback.startScheduling()
        await noteRouter.startInputDetection()
    }

    func pauseSession() {
        playback.pauseScheduling()
        Task { await noteRouter.startInputDetection() }
        noteRouter.updateExpectedMidiNote()
    }

    func resumeSession() {
        playback.resumeScheduling()
    }

    func cleanup() {
        playback.cleanup()
        noteRouter.stopInputDetection()
        MIDIEventDiagnostics.shared.printSummary()
        Self.logger.info("Play-along cleanup complete (facade)")
    }
```

- [ ] **Step 5: Build + run all PlayAlong tests**

```bash
xcodebuild ... build 2>&1 | tail -10
for suite in PlayAlongFullFlowTests PlayAlongIntegrationTests PlayAlongChromeTests PlayAlongViewModelTests ; do
  xcodebuild ... -only-testing:SurVibeTests/$suite test 2>&1 | tail -3
done
```

Expected: BUILD SUCCEEDED + all suites PASS.

- [ ] **Step 6: Commit**

```bash
git add SurVibe/PlayAlong/PlayAlongViewModel.swift
git commit -m "refactor(SurVibe): facade composes NoteRouter; ~30 properties + ~15 methods delegated (SP-3d)"
```

---

## Task 10: Move `chromeAutoHideOverrideSeconds` into `PlayAlongChromeState` (D-SP3d-4)

Closes deferred D-SP3c-6. Eliminates dual-timer code smell.

**Files:**
- Modify: `SurVibe/PlayAlong/Coordinators/PlayAlongChromeState.swift`
- Modify: `SurVibe/PlayAlong/PlayAlongViewModel.swift` (remove `chromeAutoHideSeconds`/`chromeAutoHideTask`)
- Modify: `SurVibeTests/PlayAlongChromeTests.swift` (migrate `vm.chromeAutoHideSeconds = X` → `vm.chrome.autoHideOverrideSeconds = X`)

---

- [ ] **Step 1: Add `autoHideOverrideSeconds` to `PlayAlongChromeState`**

In `PlayAlongChromeState.swift`, add property:

```swift
    /// Optional override for `autoHideDuration` (used by tests to shorten the timer).
    /// nil → uses the static constant.
    var autoHideOverrideSeconds: TimeInterval?
```

Update `resetAutoHide()` to use the override:

```swift
func resetAutoHide() {
    chromeAutoHideTask?.cancel()
    let duration = autoHideOverrideSeconds ?? Self.autoHideDuration
    guard duration > 0 else { return }
    chromeAutoHideTask = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(duration))
        guard !Task.isCancelled else { return }
        self?.chromeVisibility = .hidden
    }
}
```

- [ ] **Step 2: Delete `chromeAutoHideSeconds` and `chromeAutoHideTask` from VM**

Grep VM for these names and delete the property declarations. Delete VM's `resetAutoHide()` body if it had a parallel timer (the facade's `resetAutoHide()` should now just be `chrome.resetAutoHide()`).

- [ ] **Step 3: Migrate `PlayAlongChromeTests` writes**

Find every `vm.chromeAutoHideSeconds = X` in `PlayAlongChromeTests.swift` and replace with `vm.chrome.autoHideOverrideSeconds = X`.

- [ ] **Step 4: Build + run PlayAlongChromeTests + PlayAlongChromeStateTests**

```bash
xcodebuild ... build 2>&1 | tail -10
xcodebuild ... -only-testing:SurVibeTests/PlayAlongChromeTests test 2>&1 | tail -5
xcodebuild ... -only-testing:SurVibeTests/PlayAlongChromeStateTests test 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED + both suites PASS.

- [ ] **Step 5: Commit**

```bash
git add SurVibe/PlayAlong/Coordinators/PlayAlongChromeState.swift SurVibe/PlayAlong/PlayAlongViewModel.swift SurVibeTests/PlayAlongChromeTests.swift
git commit -m "refactor(SurVibe): chromeAutoHideOverrideSeconds in chrome state (closes D-SP3c-6, SP-3d)"
```

---

## Task 11: Delete orphaned VM private methods (~600 LOC peel)

After Task 9 wired delegation, VM's pitch detection / MIDI / note input processing / guided-play methods are dead. Delete.

**Files:**
- Modify: `SurVibe/PlayAlong/PlayAlongViewModel.swift`

---

- [ ] **Step 1: Confirm orphaned methods have no callers on VM**

```bash
grep -nE "(startMIDIDetection|installMIDINoteCallback|startMIDIConnectionMonitoring|startPitchDetection|runMelodyDetectionLoop|runChordDetectionLoop|processNoteInput|routeNoteToScoring|findChordGroup|applyChordCompleteness|handleGuidedNoteDetected|handleGuidedCorrectNote|handleGuidedWrongNote|startPatienceTimer|configureRagaContext|enrichPitchWithRagaContext|updateDetectedSwarInfo|midiNoteFromFrequency|updateExpectedMidiNote)\(" \
  SurVibe/PlayAlong/PlayAlongViewModel.swift
```

Expected: only DEFINITION lines remain (the `func` lines themselves), no internal calls.

- [ ] **Step 2: Delete the orphaned method blocks**

Delete:
- `// MARK: - Private Methods — Pitch Detection` block (lines ~713-1222)
- `// MARK: - Private Methods — Note Input Processing` block (lines ~1223-1381)
- Any orphaned guided-play helpers
- VM's local `enum GuidedPlayState` (now `NoteRouter.GuidedPlayState` — or kept on VM as type alias if external code references it)

Also delete VM private state that's now NoteRouter-owned:
- `private var ringBuffer`
- `private var pitchDetectionTask`, `chordDetectionTask`, `chordListenerTask`, `midiConnectionTask`, `patienceTimerTask`
- `private var latestChordResult`
- `private var lastGuidedMidiNote`
- `private var lastMelodyDetectionDate`
- `private var ragaScoringContext`, `ragaMapper`
- `private let highlightCoordinator`, `noteMatchingActor`
- `private let audioProcessor`

Check `midiInput`, `audioEngine`, `soundFont`, `metronome`, `clock` — if still used on VM (only by init forwarding to coordinators), consider inlining the `Self.shared` defaults directly in init.

- [ ] **Step 3: Build + run all PlayAlong suites**

```bash
xcodebuild ... build 2>&1 | tail -10
for suite in PlayAlongFullFlowTests PlayAlongIntegrationTests PlayAlongChromeTests PlayAlongViewModelTests PlayAlongTempoScalingTests ChordScoringIntegrationTests PlayAlongGestureTests PlayAlongThemeIntegrationTests ; do
  xcodebuild ... -only-testing:SurVibeTests/$suite test 2>&1 | tail -3
done
```

Expected: all 8 suites PASS.

- [ ] **Step 4: Confirm VM line count target**

```bash
wc -l SurVibe/PlayAlong/PlayAlongViewModel.swift
```

**Target: ≤ 200 lines.** If still > 200, more deletion possible — re-grep.

- [ ] **Step 5: Commit**

```bash
git add SurVibe/PlayAlong/PlayAlongViewModel.swift
git commit -m "refactor(SurVibe): delete orphaned input/pitch/MIDI methods from VM facade (SP-3d)"
```

---

## Task 12: Delete swiftlint disclaimers + CLAUDE.md doc fix (D-SP3d-6) — umbrella signal

**Files:**
- Modify: `SurVibe/PlayAlong/PlayAlongViewModel.swift` (delete 2 swiftlint directives)
- Modify: `CLAUDE.md` (NSLock → OSAllocatedUnfairLock)

---

- [ ] **Step 1: Delete the file_length disclaimer**

In `PlayAlongViewModel.swift`, delete line 1: `// swiftlint:disable file_length` (and the multi-line comment explaining the @Observable god-object reason at lines 2-4).

- [ ] **Step 2: Delete the type_body_length disclaimer**

Delete the line `// swiftlint:disable:next type_body_length` immediately above the `final class PlayAlongViewModel {` declaration.

- [ ] **Step 3: Update CLAUDE.md MIDIInputManager rule**

Find in `CLAUDE.md`:

```
- Mark all managers, singletons, and view models as `@MainActor`. **Exception:** `MIDIInputManager` uses `NSLock` instead of `@MainActor` because CoreMIDI callbacks arrive on arbitrary threads.
```

Replace `NSLock` with `OSAllocatedUnfairLock (per AUD-033)`.

- [ ] **Step 4: SwiftLint must now PASS without disclaimers**

```bash
/opt/homebrew/bin/swiftlint lint --quiet --config .swiftlint.yml 2>&1 | grep -E "PlayAlongViewModel" | head -10
```

Expected: 0 file_length / type_body_length errors on `PlayAlongViewModel.swift`.

- [ ] **Step 5: Build + commit**

```bash
xcodebuild ... build 2>&1 | tail -5
git add SurVibe/PlayAlong/PlayAlongViewModel.swift CLAUDE.md
git commit -m "chore(SP-3d): delete file_length disclaimers + CLAUDE.md OSAllocatedUnfairLock fix (umbrella signal)"
```

---

## Task 13: Verify + cleanup + tag sp-3d-note-router + umbrella tag sp-3-vm-split-complete + tracker

**Files:**
- Modify (only if cleanup): SP-3d source files
- Modify: `docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md`

---

- [ ] **Step 1: Run all coordinator + 8 PlayAlong suites + latency + SVCore**

```bash
for suite in NoteRouterTests PlayAlongChromeStateTests PlaybackCoordinatorTests ScoringCoordinatorTests \
             PlayAlongFullFlowTests PlayAlongIntegrationTests PlayAlongThemeIntegrationTests \
             PlayAlongChromeTests PlayAlongGestureTests ChordScoringIntegrationTests \
             PlayAlongViewModelTests PlayAlongTempoScalingTests LatencyContractTests ; do
  echo "=== $suite ==="
  xcodebuild ... -only-testing:SurVibeTests/$suite test 2>&1 | tail -3
done
swift test --package-path Packages/SVCore 2>&1 | tail -5
```

Expected: every suite PASS. SVCore 93/93.

- [ ] **Step 2: ADR-002 Phase 1/Phase 2 invariant grep**

```bash
echo "Phase 1 — coordinator.noteOn (highlight only):"
grep -rn "coordinator\.noteOn" SurVibe/ Packages/

echo "Phase 1 — AudioEngineManager.shared.noteOn (must be 0 hits in code):"
grep -rn "AudioEngineManager\.shared\.noteOn" SurVibe/ Packages/

echo "Phase 2 — NoteMatchingActor unchanged:"
wc -l SurVibe/PlayAlong/NoteMatchingActor.swift
```

Expected:
- Phase 1: exactly 1 hit in NoteRouter.swift; 0 hits anywhere else (1 doc-comment hit in PlaybackCoordinator.swift acceptable).
- Phase 2: `actor NoteMatchingActor` line count unchanged from pre-SP-3d.

- [ ] **Step 3: Hardcoded-logic + UIKit scan**

```bash
grep -nE "UIDevice|UIScreen\.main\.bounds|UIInterfaceOrientation|#if os\(macOS\)|#if os\(iOS\)|\.bottomBar|\.topBarTrailing|import UIKit|import AppKit" \
  SurVibe/PlayAlong/Coordinators/NoteRouter.swift \
  SurVibeTests/NoteRouterTests.swift
```

Expected: 0 lines.

- [ ] **Step 4: Final footprint check**

```bash
wc -l SurVibe/PlayAlong/PlayAlongViewModel.swift SurVibe/PlayAlong/Coordinators/*.swift
```

Expected: VM ≤ 200; NoteRouter ~700-900; ChromeState ~155 (was 145 + autoHideOverrideSeconds growth).

- [ ] **Step 5: Lint/format cleanup if needed**

```bash
xcrun swift-format format --in-place --configuration .swift-format \
  SurVibe/PlayAlong/Coordinators/NoteRouter.swift \
  SurVibe/PlayAlong/Coordinators/PlayAlongChromeState.swift \
  SurVibe/PlayAlong/PlayAlongViewModel.swift \
  SurVibeTests/NoteRouterTests.swift
```

Commit if any changes:

```bash
git add -A
git commit -m "fix(SP-3d): swift-format cleanup"
```

- [ ] **Step 6: Tag both: `sp-3d-note-router` + `sp-3-vm-split-complete`**

```bash
git tag sp-3d-note-router
git tag sp-3-vm-split-complete
git log --oneline main..HEAD
```

- [ ] **Step 7: Update tracker**

Update `docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md`:
- Status heading → `## Status (2026-04-20, post-SP-3d merge — SP-3 umbrella COMPLETE)`
- SP-3d row → `✅ shipped` with tag `sp-3d-note-router @ <SHA>` + commits count
- SP-3 umbrella row → `✅ shipped` with tag `sp-3-vm-split-complete @ <SHA>`
- Add new `### SP-3d landed (2026-04-20)` block with: extracted scope, footprint deltas, test results, ADR-002 invariant verification, all 7 D-SP3d-N deviations applied, umbrella close-out done.

Commit:

```bash
git add -f docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md
git commit -m "docs(SP-3d): SP-3 umbrella COMPLETE — VM ≤ 200 lines, 4 coordinators shipped"
```

- [ ] **Step 8: Exit checklist (report)**

- [ ] `NoteRouter.swift` exists, `@Observable @MainActor final class`, ~700-900 lines.
- [ ] 8 NoteRouterTests green.
- [ ] All SP-3a/3b/3c coordinator regression suites green.
- [ ] All 8 PlayAlong suites green.
- [ ] LatencyContractTests 3/3 green.
- [ ] SVCore 93/93 green.
- [ ] Facade holds `let scoring` + `let playback` + `let chrome` + `let noteRouter`.
- [ ] `PlayAlongViewModel.swift` ≤ 200 lines.
- [ ] `// swiftlint:disable file_length` deleted.
- [ ] `// swiftlint:disable:next type_body_length` deleted.
- [ ] CLAUDE.md NSLock → OSAllocatedUnfairLock (D-SP3d-6).
- [ ] Hardcoded-logic grep: 0 hits on SP-3d files.
- [ ] ADR-002 Phase 1: exactly 1 `coordinator.noteOn` hit in NoteRouter.
- [ ] ADR-002 Phase 2: NoteMatchingActor unchanged.
- [ ] `AudioEngineManager.shared.noteOn`: 0 hits in code.
- [ ] Both tags created: `sp-3d-note-router` + `sp-3-vm-split-complete`.
- [ ] Tracker updated with SP-3 umbrella ✅ shipped.

**SP-3 trajectory complete.** Next: SP-4 (Accessibility polish + iOS in-app Settings nav).
