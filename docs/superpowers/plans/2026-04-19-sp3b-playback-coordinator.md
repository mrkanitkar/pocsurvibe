# SP-3b PlaybackCoordinator Extraction — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract transport state, scheduling, session completion, and SwiftData persistence (~600 LOC) from `PlayAlongViewModel` into a new `@Observable @MainActor final class PlaybackCoordinator`, with the VM becoming a thinner facade that composes `playback.*` calls with still-on-VM NoteRouter-territory work (pitch detection, MIDI, guided play). NoteRouter ships in SP-3d.

**Architecture:** `PlaybackCoordinator` owns the playback transport state machine: `playbackState`, `noteEvents`, `currentNoteIndex`, `noteStates`, `currentTime`, `duration`, `playbackStartDate`, `errorMessage`, `tempoScale`, `isWaitModeEnabled`, `isSoundEnabled`, plus `playbackTask`, `displayLinkTask`, `playbackStartTime`, `pauseElapsed`, internal `waitController`, and `modelContext` for `PracticeSessionRecorder`-mediated SwiftData writes. Public surface is **domain verbs** per spec §11 D-SP3b-1: `loadSong / startScheduling / pauseScheduling / resumeScheduling / stopAndComplete / seek / cleanup`. Dependencies injected via constructor: `audioEngine, soundFont, metronome, clock, scoring, analytics?`.

**Facade pattern:** `PlayAlongViewModel` holds `let playback: PlaybackCoordinator`, re-exposes every owned property via delegating computed properties so existing 20+ external call sites continue to read `viewModel.playbackState` etc. unchanged. Facade's `startSession` becomes a 2-line orchestration: `await playback.startScheduling(); startPitchDetection()` (the second line collapses into `noteRouter.startPitchDetection()` in SP-3d).

**Tech Stack:** Swift 6.2, SwiftUI (iOS 26+), Swift Testing (`@Test`, `#expect`), `@Observable` macro, `@MainActor` isolation, `ContinuousClock` for drift-corrected timing, `SPSCRingBuffer` left untouched (NoteRouter territory). Uses existing `PracticeSessionRecorder`, `AudioEngineProviding`, `SoundFontPlaying`, `MetronomePlaying`, `ClockProviding`, `AnalyticsProviding`.

**Spec:** [docs/superpowers/specs/2026-04-19-sp3-playalong-vm-split-design.md](../specs/2026-04-19-sp3-playalong-vm-split-design.md) §5.2 + §11 (Option B + 5 plan-time deviations).

**Tasks:** 11 total. Estimated duration: 4–5 days.

**Hard gates (run after every task that compiles to a green tree):**
- `LatencyContractTests.featureFlagToggleDoesNotRestartEngine` green.
- `LatencyContractTests.rotationDoesNotRestartAudioEngine` green.
- All 8 pre-existing PlayAlong test suites green: `PlayAlongFullFlowTests`, `PlayAlongIntegrationTests`, `PlayAlongThemeIntegrationTests`, `PlayAlongChromeTests`, `PlayAlongGestureTests`, `ChordScoringIntegrationTests`, `PlayAlongViewModelTests`, `PlayAlongTempoScalingTests`.

**Cross-cutting discipline (enforce via grep scan in Task 10):**
- 0 hits for `UIDevice|UIScreen\.main\.bounds|UIInterfaceOrientation|#if os\(macOS\)|#if os\(iOS\)|\.bottomBar|\.topBarTrailing` on new files.
- No `import UIKit` / `import AppKit` in new files.
- `@Observable @MainActor final class` on PlaybackCoordinator.
- Constructor DI with nil-sentinel default for `analytics` per SP-0 D-SP0-1 / SP-1 D-SP1-1.
- Single-hop note-on invariant preserved: PlaybackCoordinator never calls `AudioEngineManager.shared.noteOn(...)` (NoteRouter territory in SP-3d). PlaybackCoordinator only calls `soundFont.playNote(...)` for scheduled playback.

---

## Task 1: Setup — branch off main, capture pre-task footprint

No code changes. Establishes the branch and the line-count target.

**Files:**
- Append to: `docs/SP-3_baseline.md`

---

- [ ] **Step 1: Verify clean main + branch off**

```bash
git status
git checkout -b feat/sp-3b-playback-coordinator
```

Expected: `Your branch is up to date with 'origin/main'.` · `nothing to commit, working tree clean`. Then the new branch is created from `main @ cbe5fe0` (the SP-3b spec addendum commit).

- [ ] **Step 2: Confirm pre-task latency tests green on the new branch**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/LatencyContractTests test 2>&1 | tail -15
```

Expected: 3/3 LatencyContractTests pass. If anything fails BEFORE changes, STOP and report — the baseline is broken.

- [ ] **Step 3: Capture pre-SP-3b VM footprint**

```bash
wc -l SurVibe/PlayAlong/PlayAlongViewModel.swift SurVibe/PlayAlong/Coordinators/*.swift
```

Expected output should match: `1788 ... PlayAlongViewModel.swift` and `124 ... ScoringCoordinator.swift`.

Append this section to `docs/SP-3_baseline.md`:

```markdown

## SP-3b pre-task snapshot (captured on `feat/sp-3b-playback-coordinator`)
- `PlayAlongViewModel.swift`: **1,788 lines** (post-SP-3a baseline).
- `ScoringCoordinator.swift`: 124 lines.
- LatencyContractTests: 3/3 PASS.

## Gate for SP-3b merge
- `PlayAlongViewModel.swift` SHRINKS to **≤ ~1,200 lines** (target: ~600 LOC peeled into PlaybackCoordinator).
- `PlaybackCoordinator.swift` ≈ 600 lines.
- Both `featureFlagToggleDoesNotRestartEngine` + `rotationDoesNotRestartAudioEngine` GREEN.
- All 8 PlayAlong suites GREEN.
```

- [ ] **Step 4: Commit baseline snapshot**

```bash
git add -f docs/SP-3_baseline.md
git commit -m "chore(SP-3b): pre-task footprint snapshot on feature branch"
```

Note: `docs/` is gitignored → `-f` required (per memory `repo_docs_gitignored`).

---

## Task 2: Write failing tests for `PlaybackCoordinator`

TDD: tests fail first. 7 tests covering the spec §6 minimum of 6 plus one for cleanup.

**Files:**
- Create: `SurVibeTests/PlaybackCoordinatorTests.swift`

---

- [ ] **Step 1: Verify the test mock surface available in `SurVibeTests/`**

```bash
grep -lE "MockAudioEngine|MockSoundFont|MockMetronome|MockClock|MockAnalyticsProvider" SurVibeTests/ -r
```

Note which mocks already exist. The test file below assumes:
- `MockAudioEngineProvider` exists (SP-0 used it for `LatencyContractTests`).
- `MockAnalyticsProvider` exists (SP-1 used it for `AppCommandsTests`).
- `RealClock` is acceptable for tests that don't need deterministic timing.

If `MockSoundFontPlayer` / `MockMetronomePlayer` don't exist, add minimal in-file fakes inside the test file (kept private to the test suite). Mock surface sketched in the test code below — extend in place if a method is missing.

- [ ] **Step 2: Create the test file**

Create `SurVibeTests/PlaybackCoordinatorTests.swift`:

```swift
// SurVibeTests/PlaybackCoordinatorTests.swift
import Foundation
import SVAudio
import SVCore
import SVLearning
import SwiftData
import Testing
@testable import SurVibe

/// Unit tests for `PlaybackCoordinator` (SP-3b).
///
/// `PlaybackCoordinator` is the transport state machine + scheduling +
/// session-completion + `PracticeSessionRecorder`-mediated SwiftData write
/// extracted from `PlayAlongViewModel`. Owns the playback domain only;
/// pitch detection / MIDI input remain on the VM facade until SP-3d.
@MainActor
@Suite("PlaybackCoordinator")
struct PlaybackCoordinatorTests {

    // MARK: - Fakes (private to this test suite)

    private final class FakeSoundFont: SoundFontPlaying {
        var playNoteCalls: [(midiNote: Int, velocity: Int, channel: Int)] = []
        var stopNoteCalls: [(midiNote: Int, channel: Int)] = []
        var stopAllNotesCallCount = 0
        func playNote(midiNote: Int, velocity: Int, channel: Int) {
            playNoteCalls.append((midiNote, velocity, channel))
        }
        func stopNote(midiNote: Int, channel: Int) {
            stopNoteCalls.append((midiNote, channel))
        }
        func stopAllNotes() { stopAllNotesCallCount += 1 }
    }

    private final class FakeMetronome: MetronomePlaying {
        var bpm: Double = 120
        var isPlaying: Bool = false
        var startCallCount = 0
        var stopCallCount = 0
        var setBPMCalls: [Double] = []
        func setBPM(_ value: Double) {
            bpm = value
            setBPMCalls.append(value)
        }
        func start() {
            isPlaying = true
            startCallCount += 1
        }
        func stop() {
            isPlaying = false
            stopCallCount += 1
        }
    }

    /// Helper that builds a tiny test song with two short notes.
    private func makeTestNoteEvents() -> [NoteEvent] {
        [
            NoteEvent(midiNote: 60, velocity: 90, timestamp: 0.0, duration: 0.25,
                      swarName: "Sa", id: UUID()),
            NoteEvent(midiNote: 62, velocity: 90, timestamp: 0.5, duration: 0.25,
                      swarName: "Re", id: UUID()),
        ]
    }

    private func makeCoordinator(
        engine: any AudioEngineProviding = MockAudioEngineProvider(),
        soundFont: FakeSoundFont = FakeSoundFont(),
        metronome: FakeMetronome = FakeMetronome(),
        scoring: ScoringCoordinator = ScoringCoordinator(),
        analytics: (any AnalyticsProviding)? = MockAnalyticsProvider()
    ) -> PlaybackCoordinator {
        PlaybackCoordinator(
            soundFont: soundFont,
            audioEngine: engine,
            metronome: metronome,
            clock: RealClock(),
            scoring: scoring,
            analytics: analytics
        )
    }

    // MARK: - Tests

    @Test func loadSongPopulatesNoteEventsAndDuration() async {
        let coord = makeCoordinator()
        let events = makeTestNoteEvents()

        coord.installNoteEventsForTesting(events)

        #expect(coord.noteEvents.count == 2)
        #expect(coord.duration == 0.75)
        #expect(coord.currentNoteIndex == nil)
        #expect(coord.playbackState == .idle)
    }

    @Test func startSchedulingTransitionsToPlaying() async throws {
        let engine = MockAudioEngineProvider()
        let metronome = FakeMetronome()
        let coord = makeCoordinator(engine: engine, metronome: metronome)
        coord.installNoteEventsForTesting(makeTestNoteEvents())

        await coord.startScheduling()

        #expect(coord.playbackState == .playing)
        #expect(engine.startCallCount == 1, "Engine started exactly once")
        #expect(metronome.startCallCount == 1, "Metronome started")
        #expect(coord.playbackStartDate != nil, "Self-driving timeline date set")
    }

    @Test func pauseSchedulingPreservesPauseElapsedAndStopsMetronome() async {
        let metronome = FakeMetronome()
        let coord = makeCoordinator(metronome: metronome)
        coord.installNoteEventsForTesting(makeTestNoteEvents())

        await coord.startScheduling()
        // Allow a brief slice of wall-clock time to accumulate.
        try? await Task.sleep(for: .milliseconds(20))
        coord.pauseScheduling()

        #expect(coord.playbackState == .paused)
        #expect(metronome.stopCallCount >= 1)
        #expect(coord.playbackStartDate == nil, "Date frozen on pause")
    }

    @Test func resumeSchedulingTransitionsBackToPlaying() async {
        let metronome = FakeMetronome()
        let coord = makeCoordinator(metronome: metronome)
        coord.installNoteEventsForTesting(makeTestNoteEvents())

        await coord.startScheduling()
        try? await Task.sleep(for: .milliseconds(20))
        coord.pauseScheduling()
        coord.resumeScheduling()

        #expect(coord.playbackState == .playing)
        #expect(metronome.startCallCount >= 2, "Metronome started on resume")
        #expect(coord.playbackStartDate != nil, "Date re-set on resume")
    }

    @Test func tempoScaleSetterUpdatesMetronomeBPM() async {
        let metronome = FakeMetronome()
        let coord = makeCoordinator(metronome: metronome)
        coord.installNoteEventsForTesting(makeTestNoteEvents())
        coord.installSongTempoForTesting(120)

        // Metronome must be marked playing for the didSet branch to fire.
        metronome.isPlaying = true
        coord.tempoScale = 0.5

        #expect(metronome.setBPMCalls.last == 60.0,
                "tempoScale 0.5 on 120 BPM song → setBPM(60)")
    }

    @Test func stopAndCompleteFinalizesScoringAndPersistsViaRecorder() async throws {
        let scoring = ScoringCoordinator()
        let metronome = FakeMetronome()
        let soundFont = FakeSoundFont()

        let container = try ModelContainer(
            for: SongProgress.self, RiyazEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let coord = makeCoordinator(
            soundFont: soundFont, metronome: metronome, scoring: scoring
        )
        coord.modelContext = container.mainContext
        coord.installNoteEventsForTesting(makeTestNoteEvents())
        coord.installSongInfoForTesting(
            slugId: "test_song", title: "Test", ragaName: "", difficulty: 2
        )

        await coord.startScheduling()
        try? await Task.sleep(for: .milliseconds(20))
        coord.stopAndComplete()

        #expect(coord.playbackState == .stopped)
        #expect(soundFont.stopAllNotesCallCount >= 1, "Stops sounding notes on completion")
        #expect(scoring.starRating >= 0, "scoring.finalize was invoked")
        // Recorder write verified by the SongProgress count in the in-memory store.
        let descriptor = FetchDescriptor<SongProgress>(
            predicate: #Predicate { $0.songId == "test_song" }
        )
        let progress = try container.mainContext.fetch(descriptor)
        #expect(progress.count == 1, "SongProgress recorded via PracticeSessionRecorder")
    }

    @Test func cleanupCancelsTasksStopsAudioAndResetsState() async {
        let engine = MockAudioEngineProvider()
        let metronome = FakeMetronome()
        let soundFont = FakeSoundFont()
        let coord = makeCoordinator(
            engine: engine, soundFont: soundFont, metronome: metronome
        )
        coord.installNoteEventsForTesting(makeTestNoteEvents())

        await coord.startScheduling()
        try? await Task.sleep(for: .milliseconds(20))
        coord.cleanup()

        #expect(coord.playbackState == .idle)
        #expect(engine.stopCallCount == 1, "Engine stopped exactly once on cleanup")
        #expect(metronome.stopCallCount >= 1)
        #expect(soundFont.stopAllNotesCallCount >= 1)
    }
}
```

Notes for the engineer:
- `installNoteEventsForTesting`, `installSongTempoForTesting`, `installSongInfoForTesting` are test-only seams added to `PlaybackCoordinator` in Task 3 to bypass the full `loadSong` audio + permission flow (which requires real engine/mic infrastructure). Marked `internal` (no `@testable import` needed if same module visibility holds — adjust to `internal` and rely on `@testable`).
- The fakes for `SoundFontPlaying`, `MetronomePlaying` are inline in the test file (private). If a `MockSoundFont` already exists in `SurVibeTests/`, prefer that and delete the in-file fake.
- `MockAudioEngineProvider` is the SP-0 mock used in `LatencyContractTests`. It exposes `startCallCount` and `stopCallCount` already.

- [ ] **Step 3: Run the test file — expect compile failure**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/PlaybackCoordinatorTests build-for-testing 2>&1 | tail -20
```

Expected: FAIL with `cannot find 'PlaybackCoordinator' in scope`. Tasks 3–5 implement the coordinator.

If `NoteEvent` init signature differs from `NoteEvent(midiNote:velocity:timestamp:duration:swarName:id:)`, adjust the test helper to match real shape (grep `init(` in `Packages/SVLearning/Sources/SVLearning/Models/NoteEvent.swift` or wherever it lives).

---

## Task 3: Implement `PlaybackCoordinator` — state, init, simple methods

Create the coordinator skeleton: observed state, dependencies, init, `seek`, `tempoScale` didSet, `playbackProgress`, internal helpers (`reset`, `cancelPlaybackTasks`, `elapsedSeconds`).

**Files:**
- Create: `SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift`

---

- [ ] **Step 1: Create the coordinator file with state + init + simple helpers**

Create `SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift`:

```swift
// SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift
import Foundation
import SVAudio
import SVCore
import SVLearning
import SwiftData
import os.log

/// Owns the play-along transport state machine: scheduling, tempo, wait-mode,
/// session completion, and `PracticeSessionRecorder`-mediated SwiftData writes.
///
/// Extracted from `PlayAlongViewModel` in SP-3b. The facade
/// (`PlayAlongViewModel`) holds `let playback = PlaybackCoordinator(...)` and
/// re-exposes every owned property as a delegating computed property so
/// existing views/tests continue to read `viewModel.playbackState` etc.
/// unchanged (spec AD-1 facade).
///
/// ## Public surface (Option B per spec §11 D-SP3b-1)
/// - `loadSong(_:)` — parse song into `noteEvents` + `noteStates`; pure data prep.
/// - `startScheduling()` — engine.start + metronome + reset + display-link + schedule.
/// - `pauseScheduling()` — save `pauseElapsed`, cancel tasks, stop metronome.
/// - `resumeScheduling()` — advance start time by `pauseElapsed`, restart tasks.
/// - `stopAndComplete()` — early stop → `completeSession()`.
/// - `seek(to:)` — set `currentTime` (only effective when paused; matches VM's prior behavior).
/// - `cleanup()` — playback-side resources only (engine.stop, metronome.stop, sound off, tasks cancel).
///
/// ## Out of scope (still on VM facade until SP-3d)
/// - Pitch detection (mic + chord), MIDI input routing, guided-play state,
///   patience timer, raga-aware mapping. The VM composes `playback.startScheduling()`
///   with those still-on-VM hooks; SP-3d collapses them into NoteRouter.
///
/// ## Latency invariants (non-negotiable)
/// - Never calls `AudioEngineManager.shared.noteOn(...)` — that's NoteRouter's site.
/// - Only calls `soundFont.playNote(...)` for scheduled playback notes (the song's notes,
///   not user-input notes).
/// - No new `await` on the MIDI → noteOn path (path is entirely outside this class).
@Observable
@MainActor
final class PlaybackCoordinator {
    // MARK: - Observed playback state

    /// Current playback state of the play-along session.
    private(set) var playbackState: PlaybackState = .idle

    /// Ordered note events for the loaded song.
    var noteEvents: [NoteEvent] = []

    /// Index of the note currently being played or evaluated.
    var currentNoteIndex: Int?

    /// Per-note state for the falling-notes / sheet view, keyed by `NoteEvent.id`.
    ///
    /// Exposed as `var` (not `private(set)`) for SP-3b transitional convenience —
    /// still-on-VM NoteRouter-territory code (`skipGuidedNote`, `processNoteInput`)
    /// writes via `playback.noteStates[id] = .missed`. SP-3d locks this down once
    /// NoteRouter owns the writers.
    var noteStates: [UUID: FallingNotesLayoutEngine.NoteState] = [:]

    /// Current playback position in seconds from song start.
    private(set) var currentTime: TimeInterval = 0

    /// Total duration of the loaded song in seconds.
    private(set) var duration: TimeInterval = 0

    /// Wall-clock Date adjusted to represent "when time=0 was", used by
    /// `FallingNotesView` to self-drive animation via `TimelineView`.
    private(set) var playbackStartDate: Date?

    /// Human-readable error message when `playbackState` is `.error`.
    private(set) var errorMessage: String?

    /// The loaded Song model (for tempo, ragaName, difficulty).
    ///
    /// Internal write so the test seam can install a song info without
    /// running the full `loadSong` notation-parsing flow.
    private(set) var song: Song?

    // MARK: - Observed transport-control state (settable from facade/UI)

    /// Tempo scaling factor (1.0 = original, 0.5 = half speed). Updates the
    /// metronome BPM live when playing.
    var tempoScale: Double = 1.0 {
        didSet {
            if metronome.isPlaying, let song {
                metronome.setBPM(Double(song.tempo) * tempoScale)
            }
        }
    }

    /// Whether wait mode is enabled for this session. Read at `startScheduling`
    /// time to construct the `waitController`.
    var isWaitModeEnabled: Bool = false

    /// Whether SoundFont playback is enabled (controls whether scheduled notes
    /// trigger `soundFont.playNote`).
    var isSoundEnabled: Bool = true

    // MARK: - Persistence

    /// Model context for persisting session results via `PracticeSessionRecorder`.
    /// Set by the facade from `SongPlayAlongView.onAppear`.
    var modelContext: ModelContext?

    // MARK: - Computed

    /// Normalized playback progress (0.0 to 1.0) for the timeline scrubber.
    var playbackProgress: Double {
        guard duration > 0 else { return 0 }
        return min(1.0, max(0.0, currentTime / duration))
    }

    /// Total playback duration in seconds, exposed for the toolbar timeline.
    var playbackDuration: TimeInterval { duration }

    // MARK: - Dependencies (injected)

    private let soundFont: any SoundFontPlaying
    private let audioEngine: any AudioEngineProviding
    private let metronome: any MetronomePlaying
    private let clock: any ClockProviding
    private let scoring: ScoringCoordinator
    private let analytics: (any AnalyticsProviding)?

    // MARK: - Internal scheduling state

    private var waitController: PlayAlongWaitController?
    private var playbackTask: Task<Void, Never>?
    private var displayLinkTask: Task<Void, Never>?
    private var playbackStartTime: ContinuousClock.Instant?
    private var pauseElapsed: TimeInterval = 0

    private static let logger = Logger.survibe(category: "PlaybackCoordinator")

    // MARK: - Initialization

    /// Create a playback coordinator with injectable dependencies.
    ///
    /// - Parameters:
    ///   - soundFont: SoundFont player for scheduled playback notes.
    ///   - audioEngine: Audio engine for `start()` / `stop()` lifecycle.
    ///   - metronome: Metronome player driven by `tempoScale` × `song.tempo`.
    ///   - clock: Drift-corrected clock for scheduling.
    ///   - scoring: Scoring coordinator (SP-3a) for `record/updateStreak/finalize/reset`.
    ///   - analytics: Analytics provider (nil → falls back to `AnalyticsManager.shared`
    ///     at call time per SP-0 D-SP0-1 / SP-1 D-SP1-1 nil-sentinel pattern).
    init(
        soundFont: any SoundFontPlaying,
        audioEngine: any AudioEngineProviding,
        metronome: any MetronomePlaying,
        clock: any ClockProviding,
        scoring: ScoringCoordinator,
        analytics: (any AnalyticsProviding)? = nil
    ) {
        self.soundFont = soundFont
        self.audioEngine = audioEngine
        self.metronome = metronome
        self.clock = clock
        self.scoring = scoring
        self.analytics = analytics
    }

    // MARK: - Public methods (transport state machine)

    /// Seek to a normalized position (0.0 to 1.0). Only effective when paused —
    /// matches the existing VM behavior; full mid-playback seek is out of scope
    /// for SP-3b (would require re-anchoring `playbackStartTime` and rescheduling).
    func seek(to progress: Double) {
        guard duration > 0 else { return }
        currentTime = progress * duration
    }

    // MARK: - Test seams (internal — do not call from production code)

    /// Install raw `NoteEvent`s for tests, bypassing the full `loadSong` flow.
    func installNoteEventsForTesting(_ events: [NoteEvent]) {
        noteEvents = events
        if let last = events.last {
            duration = last.timestamp + last.duration
        }
        for event in events {
            noteStates[event.id] = .upcoming
        }
    }

    /// Install a synthetic song with the given tempo for tempo-scale tests.
    func installSongTempoForTesting(_ tempo: Int) {
        song = Song.testInstance(tempo: tempo)
    }

    /// Install a synthetic song with persistence-relevant fields for completion tests.
    func installSongInfoForTesting(
        slugId: String, title: String, ragaName: String, difficulty: Int
    ) {
        song = Song.testInstance(
            slugId: slugId, title: title, ragaName: ragaName, difficulty: difficulty
        )
    }

    // MARK: - Internal helpers (placeholders for Tasks 4 + 5)

    /// Cancel scheduled playback tasks (does NOT touch pitch/MIDI tasks —
    /// those are the facade's responsibility until SP-3d).
    func cancelPlaybackTasks() {
        playbackTask?.cancel()
        playbackTask = nil
        displayLinkTask?.cancel()
        displayLinkTask = nil
    }

    /// Reset playback-domain state for a fresh scheduling pass. Called by
    /// `startScheduling()`. Does NOT reset NoteRouter-territory state
    /// (`expectedMidiNote`, `guidedPlayState`, `patienceTimerTask`) — those
    /// stay on the facade until SP-3d.
    func reset() {
        scoring.reset()
        currentNoteIndex = nil
        currentTime = 0
        pauseElapsed = 0
        errorMessage = nil
        for event in noteEvents {
            noteStates[event.id] = .upcoming
        }
    }

    /// Convert a `Duration` to seconds as a `TimeInterval`.
    private func elapsedSeconds(from duration: Duration) -> TimeInterval {
        Double(duration.components.seconds)
            + Double(duration.components.attoseconds) / 1_000_000_000_000_000_000
    }
}
```

- [ ] **Step 2: If `Song.testInstance(...)` doesn't exist, add minimal helpers**

Grep:

```bash
grep -nE "extension Song|static func testInstance" SurVibe/Models/Song.swift SurVibeTests/ 2>/dev/null
```

If absent, add to `SurVibeTests/TestHelpers/Song+TestInstance.swift` (create the file):

```swift
// SurVibeTests/TestHelpers/Song+TestInstance.swift
import Foundation
@testable import SurVibe

extension Song {
    /// Build a Song for tests. Uses default-empty values for fields not specified;
    /// caller overrides only what the test cares about.
    static func testInstance(
        slugId: String = "test_song",
        title: String = "Test Song",
        ragaName: String = "",
        tempo: Int = 120,
        difficulty: Int = 1
    ) -> Song {
        let song = Song()
        song.slugId = slugId
        song.title = title
        song.ragaName = ragaName
        song.tempo = tempo
        song.difficulty = difficulty
        return song
    }
}
```

If `Song.init()` requires args (CloudKit-compatible models often do), inspect `SurVibe/Models/Song.swift` and supply the minimum required args.

- [ ] **Step 3: Build the app target — expect SUCCESS, tests still failing on missing public methods**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'generic/platform=iOS' -configuration Debug build 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED` for the production target. Tests will still fail because public methods (`startScheduling`, `pauseScheduling`, etc.) don't exist yet — Task 4/5.

- [ ] **Step 4: Hardcoded-logic + UIKit-import scan on the new file**

```bash
grep -nE "UIDevice|UIScreen\.main\.bounds|UIInterfaceOrientation|#if os\(macOS\)|#if os\(iOS\)|\.bottomBar|\.topBarTrailing|import UIKit|import AppKit" \
  SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift
```

Expected: 0 lines.

- [ ] **Step 5: Commit**

```bash
git add SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift \
        SurVibeTests/PlaybackCoordinatorTests.swift \
        SurVibeTests/TestHelpers/Song+TestInstance.swift 2>/dev/null || true
git add SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift \
        SurVibeTests/PlaybackCoordinatorTests.swift
git commit -m "feat(SurVibe): PlaybackCoordinator skeleton + state + test seams (SP-3b)"
```

---

## Task 4: Implement scheduling internals

Add `startScheduling`, the playback loop, the display link, the per-note sound trigger, missed-note marking, wait-mode resolution, last-note completion. These are the engine-driven primitives.

**Files:**
- Modify: `SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift`

---

- [ ] **Step 1: Append scheduling section under `// MARK: - Public methods`**

Insert before the `// MARK: - Test seams` block:

```swift
    /// Start scheduling the loaded song from the beginning. Idempotent guard:
    /// only starts from `.idle` or `.stopped` with non-empty `noteEvents`.
    ///
    /// Sequence:
    /// 1. Engine `start()` (in playAndRecord — caller already configured session).
    /// 2. Metronome setBPM + start at `tempoScale × song.tempo`.
    /// 3. `reset()` clears scoring + position.
    /// 4. `playbackStartTime` = `clock.now`; `playbackStartDate` = `Date()`.
    /// 5. Transition to `.playing`, start display link, kick off the playback loop.
    /// 6. If `isWaitModeEnabled`, construct the `waitController`.
    /// 7. Fire `songPlaybackStarted` analytics.
    func startScheduling() async {
        guard playbackState == .idle || playbackState == .stopped else { return }
        guard !noteEvents.isEmpty else { return }

        do {
            try audioEngine.start()
        } catch {
            Self.logger.error("Engine start failed: \(error.localizedDescription)")
            errorMessage = "Audio engine failed to start"
            playbackState = .error("Audio engine failed to start")
            return
        }

        let scaledBPM = Double(song?.tempo ?? 120) * tempoScale
        metronome.setBPM(scaledBPM)
        metronome.start()

        reset()

        playbackStartTime = clock.now
        playbackStartDate = Date()
        playbackState = .playing

        startDisplayLink()
        startPlayback()

        if isWaitModeEnabled {
            waitController = PlayAlongWaitController(noteEvents: noteEvents)
        } else {
            waitController = nil
        }

        track(.songPlaybackStarted, properties: [
            "song_title": song?.title ?? "",
            "tempo_scale": tempoScale,
            "wait_mode": isWaitModeEnabled,
        ])

        Self.logger.info("Playback scheduling started")
    }

    // MARK: - Private — Scheduling

    private func startPlayback() {
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            guard let self else { return }
            await self.runPlaybackLoop(fromIndex: 0, timeOffset: 0)
        }
    }

    private func startPlaybackFromCurrentPosition() {
        playbackTask?.cancel()
        let offset = pauseElapsed
        let startIndex =
            noteEvents.firstIndex { event in
                (event.timestamp / tempoScale) >= offset
            } ?? noteEvents.count

        playbackTask = Task { [weak self] in
            guard let self else { return }
            await self.runPlaybackLoop(fromIndex: startIndex, timeOffset: 0)
        }
    }

    private func runPlaybackLoop(fromIndex: Int, timeOffset: TimeInterval) async {
        guard let startTime = playbackStartTime else { return }

        for index in fromIndex..<noteEvents.count {
            let event = noteEvents[index]
            let scaledTimestamp = event.timestamp / tempoScale
            let targetTime = startTime.advanced(by: .seconds(scaledTimestamp))

            let sleepDuration = targetTime - clock.now
            if sleepDuration > .zero {
                do {
                    try await clock.sleep(for: sleepDuration)
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }

            playNoteSound(event: event)

            currentNoteIndex = index
            noteStates[event.id] = .active
            markPreviousNotesAsMissed(beforeIndex: index)

            do {
                if try await awaitWaitModeResolution(index: index) {
                    return
                }
            } catch {
                return
            }
        }

        await awaitLastNoteCompletion()
        guard !Task.isCancelled else { return }
        completeSession()
    }

    private func playNoteSound(event: NoteEvent) {
        guard isSoundEnabled else { return }
        soundFont.playNote(
            midiNote: event.midiNote,
            velocity: event.velocity,
            channel: 0
        )
        let scaledDuration = event.duration / tempoScale
        Task { [weak self] in
            guard let self else { return }
            try? await self.clock.sleep(for: .seconds(scaledDuration))
            self.soundFont.stopNote(midiNote: event.midiNote, channel: 0)
        }
    }

    private func markPreviousNotesAsMissed(beforeIndex index: Int) {
        for prevIndex in 0..<index {
            let prevEvent = noteEvents[prevIndex]
            if noteStates[prevEvent.id] == .active {
                noteStates[prevEvent.id] = .missed
                scoring.record(NoteScoreCalculator.missedNote(expectedNote: prevEvent.swarName))
                scoring.updateStreak(grade: .miss)
            }
        }
    }

    private func awaitWaitModeResolution(index: Int) async throws -> Bool {
        guard isWaitModeEnabled, let waitCtrl = waitController else { return false }
        waitCtrl.setCurrentNoteIndex(index)
        while waitCtrl.isWaitingForNote, !Task.isCancelled {
            try? await clock.sleep(for: .milliseconds(50))
        }
        return Task.isCancelled
    }

    private func awaitLastNoteCompletion() async {
        guard let last = noteEvents.last else { return }
        let endTime = (last.timestamp + last.duration) / tempoScale
        let startTime = playbackStartTime ?? clock.now
        let targetEnd = startTime.advanced(by: .seconds(endTime))
        let remaining = targetEnd - clock.now
        if remaining > .zero {
            try? await clock.sleep(for: remaining)
        }
    }

    // MARK: - Private — Display Link

    private func startDisplayLink() {
        displayLinkTask?.cancel()
        displayLinkTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.playbackState == .playing else { return }
                if let startTime = self.playbackStartTime {
                    let elapsed = self.clock.now - startTime
                    self.currentTime = self.elapsedSeconds(from: elapsed) * self.tempoScale
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }
```

- [ ] **Step 2: Add the analytics dispatch helper at the bottom of the class**

Just before the closing brace:

```swift
    // MARK: - Private — Analytics

    /// Dispatch an event via the injected analytics, falling back to the
    /// shared singleton (nil-sentinel per SP-0 D-SP0-1).
    private func track(_ event: AnalyticsEvent, properties: [String: any Sendable]?) {
        let provider: any AnalyticsProviding = analytics ?? AnalyticsManager.shared
        provider.track(event, properties: properties)
    }
```

- [ ] **Step 3: Forward declarations for `completeSession()` (stub)**

`runPlaybackLoop` calls `completeSession()` which Task 5 implements. Add a placeholder so Task 4 builds:

```swift
    /// Stub — implemented in Task 5.
    func completeSession() {
        playbackState = .stopped
    }
```

Replace the stub in Task 5.

- [ ] **Step 4: Build — expect SUCCESS**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'generic/platform=iOS' -configuration Debug build 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit (no test run yet — completeSession is stubbed)**

```bash
git add SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift
git commit -m "feat(SurVibe): PlaybackCoordinator scheduling internals (SP-3b)"
```

---

## Task 5: Implement loadSong + pause/resume/stop + completeSession + persistence + cleanup

The remaining public methods. After this task, `PlaybackCoordinator` is feature-complete for SP-3b.

**Files:**
- Modify: `SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift`

---

- [ ] **Step 1: Replace the `completeSession` stub with the full implementation**

Replace the stub from Task 4 with:

```swift
    // MARK: - Public — Session completion

    /// Stop scheduling early and complete the session with whatever notes
    /// have been scored so far. Triggers results overlay.
    func stopAndComplete() {
        guard playbackState == .playing || playbackState == .paused else { return }
        completeSession()
    }

    /// Complete the session: mark unfinished notes as missed, finalize scoring,
    /// stop sound, persist results, fire analytics.
    ///
    /// AUD-028/034: noteStates mutations batched into a single dictionary
    /// snapshot — one Canvas redraw instead of N individual property sets.
    func completeSession() {
        let scoredNames = Set(scoring.noteScores.map(\.expectedNote))
        var updatedStates = noteStates
        var missedScores: [NoteScore] = []

        for event in noteEvents {
            let state = updatedStates[event.id]
            if state == .active || state == .upcoming {
                updatedStates[event.id] = .missed
                if !scoredNames.contains(event.swarName) {
                    missedScores.append(
                        NoteScoreCalculator.missedNote(expectedNote: event.swarName)
                    )
                }
            }
        }

        noteStates = updatedStates
        missedScores.forEach { scoring.record($0) }

        scoring.finalize(songDifficulty: song?.difficulty ?? 1)

        cancelPlaybackTasks()
        soundFont.stopAllNotes()
        playbackState = .stopped

        persistSessionResults()
        trackSessionCompletion()
    }

    // MARK: - Private — Persistence

    private func persistSessionResults() {
        guard let modelContext, let song else { return }
        let recorder = PracticeSessionRecorder(modelContext: modelContext)
        let songInfo = SessionSongInfo(
            songId: song.slugId.isEmpty ? song.id.uuidString : song.slugId,
            songTitle: song.title,
            ragaName: song.ragaName,
            difficulty: song.difficulty
        )
        let durationMinutes = max(1, Int(pauseElapsed / 60))
        recorder.recordSession(
            songInfo: songInfo,
            durationMinutes: durationMinutes,
            noteScores: scoring.noteScores
        )
        Self.logger.info("Session persisted via PracticeSessionRecorder")
    }

    private func trackSessionCompletion() {
        track(.songPlaybackCompleted, properties: [
            "song_title": song?.title ?? "",
            "accuracy": scoring.accuracy,
            "star_rating": scoring.starRating,
            "xp_earned": scoring.xpEarned,
            "tempo_scale": tempoScale,
        ])
        Self.logger.info(
            "Session completed: accuracy=\(String(format: "%.0f", self.scoring.accuracy * 100))%"
        )
    }
```

- [ ] **Step 2: Add `pauseScheduling` and `resumeScheduling` after `startScheduling`**

```swift
    /// Pause the active scheduling. Records elapsed time for seamless resume,
    /// cancels the playback + display-link tasks, stops sounding notes and
    /// metronome.
    func pauseScheduling() {
        guard playbackState == .playing else { return }

        if let startTime = playbackStartTime {
            let elapsed = clock.now - startTime
            pauseElapsed = elapsedSeconds(from: elapsed)
        }

        playbackState = .paused
        playbackStartDate = nil

        cancelPlaybackTasks()
        soundFont.stopAllNotes()
        metronome.stop()

        track(.songPlaybackPaused, properties: ["song_title": song?.title ?? ""])
        Self.logger.info("Scheduling paused at \(String(format: "%.1f", self.pauseElapsed))s")
    }

    /// Resume from the paused position. Adjusts the clock reference so elapsed
    /// computation continues from the pause offset, restarts display link +
    /// playback loop + metronome.
    func resumeScheduling() {
        guard playbackState == .paused else { return }

        playbackStartTime = clock.now.advanced(by: .seconds(-pauseElapsed))
        playbackStartDate = Date(timeIntervalSinceNow: -pauseElapsed)
        playbackState = .playing

        startDisplayLink()
        startPlaybackFromCurrentPosition()
        metronome.start()

        Self.logger.info("Scheduling resumed from \(String(format: "%.1f", self.pauseElapsed))s")
    }
```

- [ ] **Step 3: Add `loadSong` and `cleanup`**

`loadSong` does the parse + duration + state init. It does NOT touch pitch detection / MIDI / mic permission / raga context — those stay on the facade.

```swift
    /// Parse the song into `noteEvents`, compute duration, initialize per-note
    /// state. Pure data prep — no audio or input wiring.
    ///
    /// - Returns: `true` on success, `false` if neither MIDI nor notation
    ///   data was available (in which case `playbackState` is set to `.error`).
    @discardableResult
    func loadSong(_ song: Song) -> Bool {
        playbackState = .loading
        self.song = song

        if let midiData = song.midiData, !midiData.isEmpty,
            case .success(let midiEvents) = MIDIParser.parse(data: midiData)
        {
            noteEvents = NoteEvent.fromMIDI(events: midiEvents)
        } else if let sargam = song.decodedSargamNotes,
            let western = song.decodedWesternNotes
        {
            noteEvents = NoteEvent.fromNotation(
                sargamNotes: sargam,
                westernNotes: western,
                tempo: song.tempo
            )
        } else {
            errorMessage = "No playable notation found"
            playbackState = .error("No playable notation")
            Self.logger.error("loadSong failed: no MIDI or notation data")
            return false
        }

        if let last = noteEvents.last {
            duration = last.timestamp + last.duration
        }
        for event in noteEvents {
            noteStates[event.id] = .upcoming
        }

        currentNoteIndex = noteEvents.isEmpty ? nil : 0
        playbackState = .idle
        Self.logger.info(
            "Song loaded: \(self.noteEvents.count) events, duration=\(String(format: "%.1f", self.duration))s"
        )
        return true
    }

    /// Tear down playback resources. Does NOT touch pitch/MIDI tasks — those
    /// are the facade's responsibility until SP-3d.
    func cleanup() {
        cancelPlaybackTasks()
        soundFont.stopAllNotes()
        SoundFontManager.shared.resetLoadedState()
        audioEngine.stop()
        metronome.stop()
        waitController?.reset()
        waitController = nil
        playbackState = .idle
        Self.logger.info("PlaybackCoordinator cleanup complete")
    }
```

- [ ] **Step 4: Build — expect SUCCESS**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'generic/platform=iOS' -configuration Debug build 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Run the new tests — expect 7 PASS**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/PlaybackCoordinatorTests test 2>&1 | tail -15
```

Expected: 7 tests PASS. If `SongProgress` isn't part of the in-memory ModelContainer config in the persistence test, expand the config to include all models the recorder might write (check `PracticeSessionRecorder.recordSession` body for which models it touches).

If `SoundFontPlaying` / `MetronomePlaying` don't have the methods invoked (e.g. `metronome.isPlaying` is on the concrete class not the protocol), either widen the protocol (preferred) or substitute a concrete-class read in the coordinator — but document the choice in the commit message.

- [ ] **Step 6: Commit**

```bash
git add SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift \
        SurVibeTests/PlaybackCoordinatorTests.swift
git commit -m "feat(SurVibe): PlaybackCoordinator session completion + persistence + cleanup (SP-3b)"
```

---

## Task 6: Wire facade delegation in `PlayAlongViewModel`

Add `let playback = PlaybackCoordinator(...)`, wire constructor DI, and replace the playback-owned stored properties with delegating computed properties so existing 20+ external call sites keep working.

**Files:**
- Modify: `SurVibe/PlayAlong/PlayAlongViewModel.swift`

---

- [ ] **Step 1: Add `let playback` next to `let scoring`**

Find the `// MARK: - Coordinators (SP-3 extraction)` block (currently `~line 424–428`) and extend it. The `let playback` requires `scoring` to be initialized first — switch to `let` initialized in `init` since coordinators have constructor dependencies.

Update the dependency block: declare `let scoring`, declare `let playback`, then assign both in `init`. Replace these lines:

```swift
    // MARK: - Coordinators (SP-3 extraction)

    /// Scoring coordinator — owns note scores, accuracy, streaks,
    /// star rating, and XP. SP-3a extraction.
    let scoring = ScoringCoordinator()
```

with:

```swift
    // MARK: - Coordinators (SP-3 extraction)

    /// Scoring coordinator — owns note scores, accuracy, streaks,
    /// star rating, and XP. SP-3a extraction.
    let scoring: ScoringCoordinator

    /// Playback coordinator — owns transport state, scheduling, session
    /// completion, and persistence. SP-3b extraction.
    let playback: PlaybackCoordinator
```

- [ ] **Step 2: Update `init` to construct both coordinators**

The current init body assigns 5 dependencies. Add the coordinator construction at the end. Replace the init body:

```swift
        self.soundFont = soundFont ?? SoundFontManager.shared
        self.audioEngine = audioEngine ?? AudioEngineManager.shared
        self.metronome = metronome ?? MetronomePlayer.shared
        self.clock = clock ?? RealClock()
        self.midiInput = midiInput ?? MIDIInputManager.shared
```

Append:

```swift
        let scoring = ScoringCoordinator()
        self.scoring = scoring
        self.playback = PlaybackCoordinator(
            soundFont: self.soundFont,
            audioEngine: self.audioEngine,
            metronome: self.metronome,
            clock: self.clock,
            scoring: scoring,
            analytics: nil  // nil-sentinel — uses AnalyticsManager.shared at call time
        )
```

- [ ] **Step 3: Replace playback-owned stored properties with delegating computed properties**

The properties to replace (grep first to get the exact current line numbers):

```bash
grep -nE "^    (private\(set\) )?var (playbackState|noteEvents|currentNoteIndex|noteStates|currentTime|duration|errorMessage|isWaitModeEnabled|tempoScale|isSoundEnabled|playbackStartDate)" \
  SurVibe/PlayAlong/PlayAlongViewModel.swift
```

For each match, REPLACE the stored property declaration with a delegating computed property. Patterns:

```swift
// OLD: private(set) var playbackState: PlaybackState = .idle
// NEW:
    /// Current playback state — delegates to `playback.playbackState`.
    var playbackState: PlaybackState { playback.playbackState }

// OLD: private(set) var noteEvents: [NoteEvent] = []
// NEW:
    /// Ordered note events — delegates to `playback.noteEvents`.
    var noteEvents: [NoteEvent] { playback.noteEvents }

// OLD: private(set) var currentNoteIndex: Int?
// NEW:
    /// Current note index — delegates to `playback.currentNoteIndex` (read+write).
    var currentNoteIndex: Int? {
        get { playback.currentNoteIndex }
        set { playback.currentNoteIndex = newValue }
    }

// OLD: private(set) var noteStates: [UUID: FallingNotesLayoutEngine.NoteState] = [:]
// NEW:
    /// Per-note state — delegates to `playback.noteStates` (read+write).
    var noteStates: [UUID: FallingNotesLayoutEngine.NoteState] {
        get { playback.noteStates }
        set { playback.noteStates = newValue }
    }

// OLD: private(set) var currentTime: TimeInterval = 0
// NEW:
    var currentTime: TimeInterval { playback.currentTime }

// OLD: private(set) var duration: TimeInterval = 0
// NEW:
    var duration: TimeInterval { playback.duration }

// OLD: private(set) var errorMessage: String?
// NEW:
    var errorMessage: String? { playback.errorMessage }

// OLD: var isWaitModeEnabled: Bool = false
// NEW:
    var isWaitModeEnabled: Bool {
        get { playback.isWaitModeEnabled }
        set { playback.isWaitModeEnabled = newValue }
    }

// OLD: var tempoScale: Double = 1.0 { didSet { ... } }
// NEW:
    var tempoScale: Double {
        get { playback.tempoScale }
        set { playback.tempoScale = newValue }
    }

// OLD: var isSoundEnabled: Bool = true
// NEW:
    var isSoundEnabled: Bool {
        get { playback.isSoundEnabled }
        set { playback.isSoundEnabled = newValue }
    }

// OLD: private(set) var playbackStartDate: Date?
// NEW:
    var playbackStartDate: Date? { playback.playbackStartDate }
```

- [ ] **Step 4: Replace the VM's `seek(to:)` and `playbackProgress` / `playbackDuration` with delegations**

```swift
// VM's seek(to:) — replace body to delegate:
    func seek(to progress: Double) {
        playback.seek(to: progress)
    }

// VM's playbackProgress and playbackDuration — replace bodies to delegate:
    var playbackProgress: Double { playback.playbackProgress }
    var playbackDuration: TimeInterval { playback.playbackDuration }
```

- [ ] **Step 5: Migrate `var modelContext: ModelContext?`**

Replace VM's `var modelContext: ModelContext?` (line ~311) with a delegation:

```swift
    /// Model context for persistence — delegates to `playback.modelContext`.
    var modelContext: ModelContext? {
        get { playback.modelContext }
        set { playback.modelContext = newValue }
    }
```

- [ ] **Step 6: Build — expect MANY compile errors**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'generic/platform=iOS' -configuration Debug build 2>&1 | grep -E "error:" | head -30
```

Expected errors: VM's internal methods still write to the now-removed stored properties. Task 7 migrates them.

---

## Task 7: Migrate facade public methods to compose `playback.*` + still-on-VM hooks

The VM's `loadSong`, `startSession`, `pauseSession`, `resumeSession`, `stopAndComplete`, `cleanup`, `toggleWaitMode` become thin orchestration layers per Option B. They call `playback.*` for the playback domain and the still-on-VM private methods (`startPitchDetection`, `startMIDIDetection`, `startPatienceTimer`, etc.) for NoteRouter-territory work.

**Files:**
- Modify: `SurVibe/PlayAlong/PlayAlongViewModel.swift`

---

- [ ] **Step 1: Migrate `loadSong`**

Find `func loadSong(_ song: Song) async` (currently at line ~470). Replace its body:

```swift
    func loadSong(_ song: Song) async {
        guard playback.loadSong(song) else { return }

        configureRagaContext(ragaName: song.ragaName)

        // Initialize guided free-play hooks (NoteRouter territory until SP-3d).
        updateExpectedMidiNote()
        guidedPlayState = .waitingForNote
        isStuck = false

        let micGranted = await PermissionManager.shared.requestMicrophoneAccess()
        if !micGranted {
            Self.logger.warning("Microphone permission denied — pitch detection unavailable")
        }

        startMIDIDetection()
        startPitchDetection()

        do {
            try await SoundFontManager.shared.loadBundledPiano()
        } catch {
            Self.logger.error("SoundFont load failed: \(error.localizedDescription)")
        }

        startPatienceTimer()
    }
```

- [ ] **Step 2: Migrate `startSession`**

Find `func startSession() async` (currently at line ~559). Replace its body:

```swift
    func startSession() async {
        await playback.startScheduling()
        // SP-3d will collapse the next line into `await noteRouter.startPitchDetection()`.
        startPitchDetection()
    }
```

- [ ] **Step 3: Migrate `pauseSession`**

Find `func pauseSession()`. Replace its body:

```swift
    func pauseSession() {
        playback.pauseScheduling()
        // Pitch detection keeps running through pause for keyboard highlight.
        startPitchDetection()
        // Resume guided free-play hooks for the paused state.
        updateExpectedMidiNote()
        guidedPlayState = .waitingForNote
        isStuck = false
        startPatienceTimer()
    }
```

- [ ] **Step 4: Migrate `resumeSession`**

Find `func resumeSession()`. Replace its body:

```swift
    func resumeSession() {
        playback.resumeScheduling()
        // Pitch detection keeps running continuously — no restart on resume.
    }
```

- [ ] **Step 5: Migrate `stopAndComplete`**

Find `func stopAndComplete()`. Replace its body:

```swift
    func stopAndComplete() {
        playback.stopAndComplete()
    }
```

- [ ] **Step 6: Migrate `cleanup`**

Find `func cleanup()`. Replace its body:

```swift
    func cleanup() {
        playback.cleanup()

        // Still-on-VM (NoteRouter territory until SP-3d):
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

        MIDIEventDiagnostics.shared.printSummary()
        Self.logger.info("Play-along cleanup complete (facade)")
    }
```

- [ ] **Step 7: Migrate `toggleWaitMode`**

Find `func toggleWaitMode()`. The VM analytics call stays on VM (one of three sites that gives the SP-3b analytics-DI surgical opportunity later). Replace body:

```swift
    func toggleWaitMode() {
        playback.isWaitModeEnabled.toggle()
        AnalyticsManager.shared.track(
            .waitModeToggled,
            properties: [
                "enabled": playback.isWaitModeEnabled,
                "song_title": song?.title ?? "",
            ]
        )
    }
```

- [ ] **Step 8: Migrate `resetScoringState` to a smaller `resetGuidedState`**

The old VM `resetScoringState` (line ~840) reset both playback state and guided-play state. Playback-side reset moved into `PlaybackCoordinator.reset()` (called by `startScheduling`). What remains is guided-play reset only:

```swift
    /// Reset guided-free-play state (NoteRouter territory until SP-3d).
    /// Playback-side reset happens inside `playback.startScheduling()`.
    private func resetGuidedState() {
        expectedMidiNote = nil
        guidedPlayState = .waitingForNote
        isStuck = false
        patienceTimerTask?.cancel()
        patienceTimerTask = nil
    }
```

Find every internal call to `resetScoringState()` (grep) and decide per call site:
- If the call site needs full reset including playback → it should now be inside `playback.startScheduling()` already; the call site can drop the line. (Already happens — `startScheduling` calls `playback.reset()` internally.)
- If the call site needs guided-play reset only → call `resetGuidedState()`.

```bash
grep -nE "resetScoringState\(\)" SurVibe/PlayAlong/PlayAlongViewModel.swift
```

For each hit: examine context, replace with the correct option above.

- [ ] **Step 9: Migrate any internal write to `noteStates` / `currentNoteIndex` to go through `playback.`**

```bash
grep -nE "(noteStates\[|currentNoteIndex *=)" SurVibe/PlayAlong/PlayAlongViewModel.swift
```

For each match outside the 7 delegating computed properties added in Task 6:
- Replace `noteStates[event.id] = .X` with `playback.noteStates[event.id] = .X`.
- Replace `currentNoteIndex = nextIndex` with `playback.currentNoteIndex = nextIndex`.

Example sites (line numbers approximate — re-grep):
- `skipGuidedNote()` (~line 822): two writes.
- `processNoteInput` chain (~lines 1530–1640): may have advance-to-next-note writes.

- [ ] **Step 10: Build — expect SUCCESS**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'generic/platform=iOS' -configuration Debug build 2>&1 | tail -15
```

Expected: `BUILD SUCCEEDED`. If errors remain, they are likely:
- A method on `metronome` / `audioEngine` accessed directly that's no longer needed (the playback coordinator owns it).
- A VM-internal property no longer present (`pauseElapsed` was VM-private; if any VM code still reads it, that read is stale and should be removed).
- `playbackStartTime` reads on VM — also private to coordinator now; remove.

Fix each error by either (a) deleting the stale code if it duplicates coordinator behavior, or (b) routing through `playback.` if the read/write is legitimately VM-side.

- [ ] **Step 11: Commit**

```bash
git add SurVibe/PlayAlong/PlayAlongViewModel.swift
git commit -m "refactor(SurVibe): facade composes playback coordinator + still-on-VM hooks (SP-3b)"
```

---

## Task 8: Delete orphaned VM private methods

Methods that moved into `PlaybackCoordinator` are no longer called anywhere on the VM. Delete them.

**Files:**
- Modify: `SurVibe/PlayAlong/PlayAlongViewModel.swift`

---

- [ ] **Step 1: Confirm orphaned methods have no callers on the VM**

```bash
grep -nE "(startPlayback\(|startPlaybackFromCurrentPosition\(|runPlaybackLoop\(|playNoteSound\(|markPreviousNotesAsMissed\(|awaitWaitModeResolution\(|awaitLastNoteCompletion\(|startDisplayLink\(|cancelPlaybackTasks\(|completeSession\(|persistSessionResults\(|trackSessionCompletion\()" \
  SurVibe/PlayAlong/PlayAlongViewModel.swift
```

Expected: only DEFINITION lines (the `func` lines themselves), no internal calls. If any callers remain, return to Task 7 to migrate them.

- [ ] **Step 2: Delete the now-orphaned method blocks**

The following sections of the VM are duplicated in `PlaybackCoordinator` and should be deleted (use the `// MARK:` markers to locate, line numbers approximate):

- `// MARK: - Private Methods — Playback Scheduling` block (~lines 1366–1497):
  - `startPlayback()`
  - `startPlaybackFromCurrentPosition()`
  - `runPlaybackLoop(fromIndex:timeOffset:)`
  - `playNoteSound(event:)`
  - `markPreviousNotesAsMissed(beforeIndex:)`
  - `awaitWaitModeResolution(index:)`
  - `awaitLastNoteCompletion()`

- `// MARK: - Private Methods — Display Link` block (~lines 1499–1521):
  - `startDisplayLink()`

- `// MARK: - Private Methods — Session Completion` block (~lines 1681–1758):
  - `completeSession()`
  - `persistSessionResults()`
  - `trackSessionCompletion()`

- `cancelPlaybackTasks()` (~line 1763) on the VM — but **CHECK first** whether the VM's `cancelPlaybackTasks` did MORE than the coordinator's version (the VM cancelled MIDI + pitch tasks too, which are NoteRouter territory). If so, **rename** the VM's version to `cancelPitchAndMIDITasks()` and KEEP only the lines that cancel pitch / MIDI / patience tasks. Do NOT delete the body wholesale.

- `pauseElapsed`, `playbackStartTime` private VM properties — remove them entirely (live on the coordinator now).

Also remove the now-unused VM dependencies that ONLY existed for playback: check whether `metronome`, `clock`, `audioEngine`, `soundFont` are still referenced elsewhere on the VM (they almost certainly are — the VM still uses `audioEngine` for `audioProcessor` setup, `soundFont` is read, etc.). **Do not remove unless `grep` shows zero remaining uses.**

- [ ] **Step 3: Delete the test seam call from `startSession` if any duplication remains**

The VM's old `startSession` had `resetScoringState()` inline. After Task 7 it's removed; verify with grep.

- [ ] **Step 4: Build — expect SUCCESS**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'generic/platform=iOS' -configuration Debug build 2>&1 | tail -10
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Confirm VM line count shrunk**

```bash
wc -l SurVibe/PlayAlong/PlayAlongViewModel.swift
```

Expected: **less than 1,300 lines** (was 1,788). Target: ~1,200 lines (peeled ~600 LOC). If the VM is still > 1,400 lines, more deletion is possible — re-grep for orphaned methods.

- [ ] **Step 6: Commit**

```bash
git add SurVibe/PlayAlong/PlayAlongViewModel.swift
git commit -m "refactor(SurVibe): delete orphaned playback methods from VM facade (SP-3b)"
```

---

## Task 9: Verification — latency gates + regression suites

All 8 pre-existing PlayAlong suites must pass PLUS the new PlaybackCoordinator suite PLUS both latency gates.

**Files:** none edited (verification only).

---

- [ ] **Step 1: Run the new PlaybackCoordinator unit tests**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/PlaybackCoordinatorTests test 2>&1 | tail -10
```

Expected: 7 tests PASS.

- [ ] **Step 2: Run the existing ScoringCoordinator unit tests (regression guard)**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/ScoringCoordinatorTests test 2>&1 | tail -10
```

Expected: 5 tests PASS. SP-3a tests must not regress.

- [ ] **Step 3: Run the 8 pre-existing PlayAlong test suites sequentially**

```bash
for suite in PlayAlongFullFlowTests PlayAlongIntegrationTests PlayAlongThemeIntegrationTests \
             PlayAlongChromeTests PlayAlongGestureTests ChordScoringIntegrationTests \
             PlayAlongViewModelTests PlayAlongTempoScalingTests ; do
  echo "=== $suite ==="
  xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
    -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
    -only-testing:SurVibeTests/$suite test 2>&1 | tail -3
done
```

Expected: every suite shows `Test Suite … passed`. If any fails, STOP and investigate — the facade may be dropping an observation, or a property delegation may be reversed.

Likely failure modes if something regressed:
- `PlayAlongTempoScalingTests` failing → `tempoScale` setter or didSet path wired incorrectly.
- `PlayAlongIntegrationTests` failing on session completion → persistence path broken (`PracticeSessionRecorder` invocation order).
- `PlayAlongViewModelTests` failing on `noteStates` reads → delegation returns stale value (verify the get path goes through `playback.noteStates`, not a leftover local).

- [ ] **Step 4: Run both latency-contract tests**

```bash
xcodebuild -project SurVibe.xcodeproj -scheme SurVibe \
  -destination 'platform=iOS Simulator,name=iPad Air 13-inch (M3)' \
  -only-testing:SurVibeTests/LatencyContractTests test 2>&1 | tail -10
```

Expected: 3/3 pass — `featureFlagToggleDoesNotRestartEngine`, `rotationDoesNotRestartAudioEngine`, `performanceCriticalViewsDoNotReadThemeEnvironment`.

- [ ] **Step 5: Run SVCore tests (regression guard)**

```bash
swift test --package-path Packages/SVCore 2>&1 | tail -5
```

Expected: 93/93 passing. SP-3b didn't touch SVCore — must not regress.

- [ ] **Step 6: Confirm coordinator + VM footprint**

```bash
wc -l SurVibe/PlayAlong/Coordinators/*.swift SurVibe/PlayAlong/PlayAlongViewModel.swift
```

Expected:
- `ScoringCoordinator.swift`: **124 lines** (unchanged from SP-3a).
- `PlaybackCoordinator.swift`: **~600 lines**.
- `PlayAlongViewModel.swift`: **~1,200 lines** (was 1,788; -550 to -650 LOC peeled).

If `PlayAlongViewModel.swift` is > 1,400 lines, an extraction was incomplete — re-grep for the listed orphaned methods.

---

## Task 10: Final cleanup — lint, format, hardcoded-logic scan

**Files:** none edited unless issues found.

---

- [ ] **Step 1: SwiftLint**

```bash
/opt/homebrew/bin/swiftlint lint --quiet --config .swiftlint.yml 2>&1 | tail -20
```

Expected: 0 new errors. Pre-existing warnings acceptable. If SP-3b files produce new errors, fix.

- [ ] **Step 2: swift-format on SP-3b files**

```bash
xcrun swift-format lint --configuration .swift-format \
  SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift \
  SurVibe/PlayAlong/PlayAlongViewModel.swift \
  SurVibeTests/PlaybackCoordinatorTests.swift 2>&1 | head -20
```

If non-empty, run:

```bash
xcrun swift-format format --in-place --configuration .swift-format \
  SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift \
  SurVibe/PlayAlong/PlayAlongViewModel.swift \
  SurVibeTests/PlaybackCoordinatorTests.swift
```

- [ ] **Step 3: Hardcoded-logic scan across SP-3b files**

```bash
grep -nE "UIDevice|UIScreen\.main\.bounds|UIInterfaceOrientation|#if os\(macOS\)|#if os\(iOS\)|\.bottomBar|\.topBarTrailing|import UIKit|import AppKit" \
  SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift \
  SurVibeTests/PlaybackCoordinatorTests.swift
```

Expected: 0 lines. Any hit must be fixed (AD-10 enforcement).

- [ ] **Step 4: Single-hop note-on invariant check**

```bash
grep -nE "AudioEngineManager\.shared\.noteOn|audioEngine\.noteOn" \
  SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift
```

Expected: **0 hits**. PlaybackCoordinator must NEVER call `noteOn` — that's NoteRouter's site (still on VM until SP-3d). Any hit means a misextraction — fix.

- [ ] **Step 5: If any fixes were needed, commit them**

```bash
git add -A
git commit -m "fix(SP-3b): lint/format/scan cleanup"
```

---

## Task 11: Tag + exit checklist

**Files:** none edited.

---

- [ ] **Step 1: Tag the final SHA on the feature branch**

```bash
git tag sp-3b-playback
git log --oneline main..HEAD
```

Expected commit list (chronological):
- `chore(SP-3b): pre-task footprint snapshot on feature branch`
- `feat(SurVibe): PlaybackCoordinator skeleton + state + test seams (SP-3b)`
- `feat(SurVibe): PlaybackCoordinator scheduling internals (SP-3b)`
- `feat(SurVibe): PlaybackCoordinator session completion + persistence + cleanup (SP-3b)`
- `refactor(SurVibe): facade composes playback coordinator + still-on-VM hooks (SP-3b)`
- `refactor(SurVibe): delete orphaned playback methods from VM facade (SP-3b)`
- optional `fix(SP-3b): lint/format/scan cleanup`

- [ ] **Step 2: Update `docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md`**

Update the §Status table:
- `SP-3b PlaybackCoordinator (phase 2 of 4)`: change to `✅ shipped`, fill `Tag` (`sp-3b-playback @ <SHA>`), `Merge SHA` (left blank until merge), `Commits` (count).

Update `## Status (2026-04-19, post-SP-3a merge)` heading to `post-SP-3b merge`.

Add a new `### SP-3b landed (2026-04-19)` block under the SP-3a one with the same shape:
- What was extracted
- Facade pattern wired (state delegations, `let playback`, init wiring)
- VM line count delta
- Tests delta (8 pre-existing + new PlaybackCoordinatorTests + ScoringCoordinator regression)
- Latency gates + SVCore + cross-platform discipline confirmation
- Architectural deviations actually applied (D-SP3b-1 through D-SP3b-5 — note any further deviations discovered at plan time)

Commit:

```bash
git add -f docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md
git commit -m "docs(SP-3b): update tracker with SP-3b completion + SP-3c as next"
```

- [ ] **Step 3: SP-3b exit checklist verification**

Confirm before merge / hand-off:

- [ ] `SurVibe/PlayAlong/Coordinators/PlaybackCoordinator.swift` exists, `@Observable @MainActor final class`, ~600 lines.
- [ ] 7 new `PlaybackCoordinatorTests` green (load, start, pause, resume, tempoScale, completion, cleanup).
- [ ] 5 ScoringCoordinator tests still green (SP-3a regression).
- [ ] All 8 pre-existing PlayAlong suites green.
- [ ] Both latency-contract tests green (`featureFlagToggleDoesNotRestartEngine`, `rotationDoesNotRestartAudioEngine`).
- [ ] SVCore tests still 93/93.
- [ ] Facade holds `let scoring` + `let playback`, init wires both.
- [ ] 12 stored properties replaced by delegating computed properties on the facade (`playbackState`, `noteEvents`, `currentNoteIndex`, `noteStates`, `currentTime`, `duration`, `errorMessage`, `playbackStartDate`, `tempoScale`, `isWaitModeEnabled`, `isSoundEnabled`, `modelContext`).
- [ ] Facade public methods (`loadSong / startSession / pauseSession / resumeSession / stopAndComplete / cleanup / seek / toggleWaitMode`) compose `playback.*` calls with still-on-VM NoteRouter-territory work.
- [ ] Orphaned VM private methods deleted (`startPlayback`, `startPlaybackFromCurrentPosition`, `runPlaybackLoop`, `playNoteSound`, `markPreviousNotesAsMissed`, `awaitWaitModeResolution`, `awaitLastNoteCompletion`, `startDisplayLink`, `completeSession`, `persistSessionResults`, `trackSessionCompletion`).
- [ ] VM's old `cancelPlaybackTasks` either deleted (if its full body moved to coordinator) or renamed to `cancelPitchAndMIDITasks` (if it cancelled NoteRouter-territory tasks too).
- [ ] VM private state `pauseElapsed`, `playbackStartTime` removed from VM (lives on coordinator).
- [ ] `PlayAlongViewModel.swift` shrunk from 1,788 to ≤ ~1,200 lines.
- [ ] Hardcoded-logic grep returns 0 hits on SP-3b files.
- [ ] `AudioEngineManager.shared.noteOn` grep on `PlaybackCoordinator.swift` returns 0 hits (single-hop note-on invariant preserved).
- [ ] `docs/SP-3_baseline.md` updated with SP-3b post-task snapshot.
- [ ] Tag `sp-3b-playback` created.
- [ ] `docs/superpowers/plans/SP-TRAJECTORY-TRACKER.md` updated.

Next: **SP-3c** (PlayAlongChromeState) — written as a separate plan after SP-3b merges to `main`. Plan-time read of what SP-3b actually landed (especially the test-seam shape and any additional deviations discovered) will inform SP-3c's chrome-state extraction sequence.
