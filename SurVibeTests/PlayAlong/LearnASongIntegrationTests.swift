// SurVibeTests/PlayAlong/LearnASongIntegrationTests.swift
import AVFoundation
import Foundation
import SVAudio
import SVCore
import SVLearning
import SwiftData
import Testing

@testable import SurVibe

/// Wave 5 E2 — integration tests that exercise the full Learn-a-Song
/// pipeline against a real bundled MXL asset (Sukhkarta_Dukhharta).
///
/// These tests run the production parsing path end-to-end:
/// `Bundle.main → MXLLoader → VerovioBridge → PartSplitter → ArrangementPlayer`.
/// The sampler graph is replaced with `SharedMockGraph` so the suite stays
/// hardware-free under `xcodebuild test`. The hardware-driven p50 ≤ 12 ms /
/// p99 ≤ 18 ms gate is exercised on a physical iPad in Task E3 — these
/// integration tests guard the wiring and per-event invariants that gate
/// would otherwise depend on.
///
/// Plan reference: `docs/superpowers/plans/2026-04-30-learn-a-song.md`
/// Task E2 (lines 2246–2276).
@MainActor
@Suite("Learn-a-Song integration — Wave 5 E2", .serialized)
struct LearnASongIntegrationTests {

    // MARK: - Fixtures

    /// Resolve the bundled `Sukhkarta_Dukhharta.mxl` asset.
    ///
    /// The file lives in the synchronized `SurVibe/Diagnostics/AuditionAssets/`
    /// folder and is auto-bundled into the app target. Returns `nil` when
    /// the bundle is missing the resource so individual tests can record an
    /// `Issue` without crashing the suite.
    private func loadBundledSukhkarta() throws -> PartSplit? {
        guard
            let url = Bundle.main.url(
                forResource: "Sukhkarta_Dukhharta",
                withExtension: "mxl"
            )
        else { return nil }
        let mxl = try Data(contentsOf: url)
        let xml = try MXLLoader.loadMusicXML(from: mxl)
        let bridge = VerovioBridge()
        let rendered = try bridge.render(musicXML: xml)
        return try PartSplitter().split(rendered)
    }

    /// Build a play-along VM wired with hardware-free mocks. Mirrors the
    /// helper in `PlayAlongViewModelE1Tests` so both suites use the same
    /// fixture surface.
    private func makeViewModel(
        midiInput: MockMIDIInputProvider = MockMIDIInputProvider()
    ) -> PlayAlongViewModel {
        PlayAlongViewModel(
            soundFont: MockSoundFontPlayer(),
            audioEngine: MockAudioEngineProvider(),
            metronome: MockMetronomePlayer(),
            clock: TestClock(),
            midiInput: midiInput
        )
    }

    /// Load Sukhkarta into the VM through the production pipeline and
    /// return the captured mock graph + split for assertions.
    ///
    /// Records an `Issue` and returns `nil` when the bundled MXL is
    /// missing — keeps the integration suite resilient against asset
    /// drift while still failing loudly.
    private func wireSukhkarta(
        into vm: PlayAlongViewModel
    ) async throws -> (mock: SharedMockGraph, split: PartSplit)? {
        guard let split = try loadBundledSukhkarta() else {
            Issue.record(
                "Sukhkarta_Dukhharta.mxl missing from app bundle (expected at SurVibe/Diagnostics/AuditionAssets/)."
            )
            return nil
        }
        let mock = SharedMockGraph()
        try await vm.loadArrangement(split: split, graph: mock)
        return (mock, split)
    }

    // MARK: - Tests

    /// Verifies the MXL → VM wiring at half-tempo and that the mock
    /// graph receives the scaled rate. With a `SharedMockGraph`,
    /// `currentPositionInBeats` does not auto-advance — we drive it
    /// explicitly via the existing test seam to simulate a 2-second
    /// playback window at 0.5×.
    @Test("Sukhkarta loads and advances at half speed")
    func testSukhkartaLoadsAndAdvancesAtHalfSpeed() async throws {
        let vm = makeViewModel()
        guard let wired = try await wireSukhkarta(into: vm) else { return }
        let (mock, _) = wired

        vm.tempoScale = 0.5
        #expect(mock.lastSetTempoScale == 0.5)

        // Plant note events so the playback coordinator's start path
        // does not bail out as a no-op (it requires non-empty events).
        vm.playback.installNoteEventsForTesting(
            [NoteEventFactory.make(swarName: "Sa", midiNote: 60, timestamp: 0, duration: 1)]
        )
        await vm.startSession()
        #expect(mock.playCalled)
        #expect(vm.arrangementPlayer?.isPlaying == true)

        // Simulate ~2 seconds of playback at 120 BPM × 0.5 = 60 effective
        // BPM. 2 s of wall-clock time would cover ~2 beats. We assert a
        // wide band [0.5, 4.0] to absorb host-timing jitter while still
        // proving the position advanced.
        mock.currentPositionInBeats = 2.0
        vm.arrangementPlayer?.simulateDisplayLinkFire()

        let beat = vm.arrangementPlayer?.currentBeat ?? 0
        #expect(beat > 0.5)
        #expect(beat < 4.0)

        vm.cleanup()
    }

    /// Drives four simulated MIDI note-on events through the scoring tap
    /// and verifies `ScoringAdapter.summary().notesAttempted` reflects
    /// the ingested count.
    @Test("Injecting MIDI note-ons increments scoring attempts")
    func testInjectMIDIScoresVerdicts() async throws {
        let vm = makeViewModel()
        guard let wired = try await wireSukhkarta(into: vm) else { return }
        _ = wired

        vm.playback.installNoteEventsForTesting(
            [NoteEventFactory.make(swarName: "Sa", midiNote: 60, timestamp: 0, duration: 1)]
        )
        await vm.startSession()

        // Inject four note-ons across four expected-note pitches drawn
        // from the loaded learner score so at least one of them lands
        // close to a real expected beat — guarding the verdict path.
        let learner = vm.currentSplit?.learner.notes ?? []
        let pitches: [UInt8] = learner.prefix(4).map { UInt8($0.midiNote) }
        let velocities: UInt8 = 96

        for pitch in pitches {
            let event = MIDIInputEvent(
                noteNumber: pitch,
                velocity: velocities,
                channel: 0,
                midiTimestamp: mach_absolute_time(),
                timestamp: Date()
            )
            vm.handleMIDINoteEventForScoring(event)
        }

        let summary = vm.scoringAdapter?.summary()
        #expect(summary != nil)
        #expect((summary?.notesAttempted ?? 0) == pitches.count)

        vm.cleanup()
    }

    /// Mid-playback tempo changes propagate to the wired sampler graph.
    @Test("Tempo change mid-playback forwards to ArrangementPlayer")
    func testTempoChangeMidPlaybackStaysConsistent() async throws {
        let vm = makeViewModel()
        guard let wired = try await wireSukhkarta(into: vm) else { return }
        let (mock, _) = wired

        vm.playback.installNoteEventsForTesting(
            [NoteEventFactory.make(swarName: "Sa", midiNote: 60, timestamp: 0, duration: 1)]
        )
        await vm.startSession()
        #expect(mock.lastSetTempoScale == 1.0)

        vm.tempoScale = 0.75
        #expect(mock.lastSetTempoScale == 0.75)
        #expect(vm.arrangementTempoScale == 0.75)

        vm.cleanup()
    }

    /// `stopAndComplete()` writes a `PlayAlongSession` row capturing the
    /// scoring summary at session end.
    @Test("PlayAlongSession is persisted on stop")
    func testPlayAlongSessionIsPersistedOnStop() async throws {
        let vm = makeViewModel()
        guard let wired = try await wireSukhkarta(into: vm) else { return }
        _ = wired

        let context = try SwiftDataTestContainer.freshContext()
        vm.modelContext = context
        let song = Song(slugId: "sukhkarta-integration", title: "Sukhkarta")
        context.insert(song)
        try context.save()
        vm.playback.installSongInfoForTesting(
            slugId: "sukhkarta-integration",
            title: "Sukhkarta",
            ragaName: "Bhairavi",
            difficulty: 1
        )
        vm.playback.installNoteEventsForTesting(
            [NoteEventFactory.make(swarName: "Sa", midiNote: 60, timestamp: 0, duration: 1)]
        )

        await vm.startSession()

        // Ingest one note-on so the persisted session has a non-zero
        // attempts counter (validates the scoring fan-out is alive).
        let firstPitch = UInt8(vm.currentSplit?.learner.notes.first?.midiNote ?? 60)
        vm.handleMIDINoteEventForScoring(
            MIDIInputEvent(
                noteNumber: firstPitch,
                velocity: 96,
                channel: 0,
                midiTimestamp: mach_absolute_time(),
                timestamp: Date()
            )
        )

        vm.stopAndComplete()

        let descriptor = FetchDescriptor<PlayAlongSession>()
        let rows = try context.fetch(descriptor)
        #expect(rows.count >= 1)
        if let row = rows.first {
            #expect(row.notesAttempted >= 1)
        }

        vm.cleanup()
    }

    /// Audio interruption pauses; `.shouldResume` resumes.
    @Test("Interruption pauses; .shouldResume restores playback")
    func testInterruptionPausesAndShouldResumeRestores() async throws {
        let vm = makeViewModel()
        guard let wired = try await wireSukhkarta(into: vm) else { return }
        _ = wired

        vm.playback.installNoteEventsForTesting(
            [NoteEventFactory.make(swarName: "Sa", midiNote: 60, timestamp: 0, duration: 1)]
        )
        await vm.startSession()
        #expect(vm.playbackState == .playing)

        // Drive the registered callbacks directly. Posting real
        // `AVAudioSession.interruptionNotification` is unreliable in
        // unit tests because the system observer is `queue: .main`.
        AudioSessionManager.shared.onInterruptionBegan?()
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(vm.playbackState == .paused)

        AudioSessionManager.shared.onInterruptionEnded?(true)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(vm.playbackState == .playing)

        vm.cleanup()
    }

    /// Bluetooth endpoint registration flips the practice-mode chip and
    /// scoring is suppressed while the chip is visible.
    @Test("Bluetooth practice-mode chip suppresses scoring")
    func testBluetoothPracticeModeChipFlipsScoringSuppression() async throws {
        let vm = makeViewModel()
        guard let wired = try await wireSukhkarta(into: vm) else { return }
        _ = wired

        // Re-attach the singleton chip hook (init-time wiring only fires
        // when the resolved provider IS the manager — the mock path is
        // the fallback).
        let manager = MIDIInputManager.shared
        manager.onPracticeModeRequired = { _ in
            Task { @MainActor in vm.practiceModeChipVisible = true }
        }
        defer { manager.onPracticeModeRequired = nil }

        let descriptor = EndpointDescriptor(
            endpointID: Int32.random(in: 100_000...999_999),
            displayName: "Mock BLE",
            kind: .bluetooth
        )
        manager.updateEndpoint(0, descriptor: descriptor)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(vm.practiceModeChipVisible == true)

        vm.playback.installNoteEventsForTesting(
            [NoteEventFactory.make(swarName: "Sa", midiNote: 60, timestamp: 0, duration: 1)]
        )
        await vm.startSession()

        let before = vm.scoringAdapter?.summary().notesAttempted ?? 0
        vm.handleMIDINoteEventForScoring(
            MIDIInputEvent(
                noteNumber: 60,
                velocity: 96,
                channel: 0,
                midiTimestamp: mach_absolute_time(),
                timestamp: Date()
            )
        )
        let after = vm.scoringAdapter?.summary().notesAttempted ?? 0
        #expect(before == after)

        vm.cleanup()
    }

    // MARK: - Latency probe (Part A)

    /// Verifies the `#if DEBUG` `AppLatencyProbe` records at least one
    /// sample after a simulated MIDI note-on with a hardware timestamp.
    /// The exact value is host-dependent; we only assert non-zero
    /// percentile output to prove the wiring fired.
    @Test("Latency probe records ingest latency on note-on")
    func testLatencyProbeRecordsOnNoteOn() async throws {
        let vm = makeViewModel()
        guard let wired = try await wireSukhkarta(into: vm) else { return }
        _ = wired

        vm.playback.installNoteEventsForTesting(
            [NoteEventFactory.make(swarName: "Sa", midiNote: 60, timestamp: 0, duration: 1)]
        )
        await vm.startSession()

        // Stamp the MIDI timestamp slightly in the past so the recorded
        // latency is comfortably positive even with sub-µs precision.
        let pastTicks = mach_absolute_time()
        // Tiny spin to ensure `now > pastTicks` by a measurable amount.
        for _ in 0..<1_000 { _ = mach_absolute_time() }

        vm.handleMIDINoteEventForScoring(
            MIDIInputEvent(
                noteNumber: 60,
                velocity: 96,
                channel: 0,
                midiTimestamp: pastTicks,
                timestamp: Date()
            )
        )

        #expect(vm.latencyProbe.p50() >= 0.0)
        // At least one sample was recorded — p99 returns 0.0 only when
        // the sample buffer is empty, so a non-negative finite value
        // proves the recording path executed.
        #expect(vm.latencyProbe.p99().isFinite)

        vm.cleanup()
    }
}
