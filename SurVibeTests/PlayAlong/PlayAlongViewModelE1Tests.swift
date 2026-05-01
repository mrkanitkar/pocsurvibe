// SurVibeTests/PlayAlong/PlayAlongViewModelE1Tests.swift
import AVFoundation
import Foundation
import SVAudio
import SVCore
import SVLearning
import SwiftData
import Testing

@testable import SurVibe

/// Wave 5 E1 wiring tests for `PlayAlongViewModel`.
///
/// Verifies that the play-along facade correctly forwards transport,
/// tempo, loop, practice-mode, and hand-isolation calls into a wired
/// `ArrangementPlayer`, that AudioSessionManager interruption /
/// route-change callbacks pause playback, that Bluetooth practice-mode
/// detection toggles the chip flag, and that `stopAndComplete` persists
/// a `PlayAlongSession` row.
@MainActor
@Suite("PlayAlongViewModel — Wave 5 E1 wiring")
struct PlayAlongViewModelE1Tests {

    // MARK: - Helpers

    /// Build a `PlayAlongViewModel` wired with hardware-free mocks.
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

    /// Wire a fresh ArrangementPlayer + ScoringAdapter into the VM via
    /// `loadArrangement(split:graph:)`, returning the mock graph for
    /// assertions.
    @discardableResult
    private func loadArrangement(
        on vm: PlayAlongViewModel,
        measureCount: Int = 4,
        multiStaff: Bool = false
    ) async throws -> SharedMockGraph {
        let mock = SharedMockGraph()
        try await vm.loadArrangement(
            split: makeE1Split(measureCount: measureCount, multiStaff: multiStaff),
            graph: mock
        )
        return mock
    }

    // MARK: - Tests

    @Test("loadArrangement initializes ArrangementPlayer + ScoringAdapter")
    func loadArrangementInitializesPlayerAndScorer() async throws {
        let vm = makeViewModel()
        let mock = try await loadArrangement(on: vm, measureCount: 8)
        #expect(vm.arrangementPlayer != nil)
        #expect(vm.scoringAdapter != nil)
        #expect(vm.currentSplit != nil)
        #expect(vm.totalMeasures == 8)
        #expect(mock.loadMIDICalled)
    }

    @Test("startSession invokes ArrangementPlayer.start when wired")
    func startSessionStartsArrangementPlayer() async throws {
        let vm = makeViewModel()
        let mock = try await loadArrangement(on: vm)
        // Note events are needed for PlaybackCoordinator to actually start.
        vm.playback.installNoteEventsForTesting(
            [NoteEventFactory.make(swarName: "Sa", midiNote: 60, timestamp: 0, duration: 1)]
        )
        await vm.startSession()
        #expect(mock.playCalled)
        #expect(vm.arrangementPlayer?.isPlaying == true)
    }

    @Test("tempoScale setter forwards to ArrangementPlayer")
    func tempoScaleForwardsToPlayer() async throws {
        let vm = makeViewModel()
        let mock = try await loadArrangement(on: vm)
        vm.tempoScale = 0.75
        #expect(mock.lastSetTempoScale == 0.75)
        // Both legacy + slider state stay in sync.
        #expect(vm.tempoScale == 0.75)
    }

    @Test("tempoScale slider also drives ArrangementPlayer")
    func tempoScaleSliderForwardsToPlayer() async throws {
        let vm = makeViewModel()
        let mock = try await loadArrangement(on: vm)
        vm.tempoScale = 1.25
        #expect(mock.lastSetTempoScale == 1.25)
        #expect(vm.tempoScale == 1.25)
    }

    @Test("tempoScale clamps to [0.5, 1.5]")
    func tempoScaleClamps() {
        let vm = makeViewModel()
        vm.tempoScale = 0.1
        #expect(vm.tempoScale == 0.5)
        vm.tempoScale = 5.0
        #expect(vm.tempoScale == 1.5)
    }

    @Test("practiceMode setter forwards to ArrangementPlayer")
    func practiceModeForwardsToPlayer() async throws {
        let vm = makeViewModel()
        _ = try await loadArrangement(on: vm, multiStaff: true)
        vm.practiceMode = .rightHand
        #expect(vm.arrangementPlayer?.practiceMode == .rightHand)
    }

    @Test("hearOtherHand setter forwards to ArrangementPlayer mute set")
    func hearOtherHandForwardsToPlayer() async throws {
        let vm = makeViewModel()
        let mock = try await loadArrangement(on: vm, multiStaff: true)
        vm.practiceMode = .rightHand
        vm.hearOtherHand = false
        #expect(mock.mutedTrackIndices == [1])
    }

    @Test("loopRegion setter forwards to ArrangementPlayer.setLoop")
    func loopRegionForwardsToPlayer() async throws {
        let vm = makeViewModel()
        let mock = try await loadArrangement(on: vm, measureCount: 12)
        vm.loopRegion = LoopRegion(startMeasure: 5, endMeasure: 8)
        // SectionLoopController only wraps while the player is playing;
        // start it (with no count-in) before driving the tick so the
        // wrap actually fires.
        vm.arrangementPlayer?.start(countInBars: 0)
        vm.arrangementPlayer?.simulateBeatTick(
            beatsPerMeasure: 4,
            currentBeat: 32.5
        )
        #expect(mock.lastSeekBeat == 16)
    }

    @Test("totalMeasures derived from learner score last measure")
    func totalMeasuresDerivedFromSplit() async throws {
        let vm = makeViewModel()
        _ = try await loadArrangement(on: vm, measureCount: 16)
        #expect(vm.totalMeasures == 16)
    }

    @Test("hasMultipleStaves true when split has RH + LH")
    func hasMultipleStavesDerivedFromSplit() async throws {
        let vm = makeViewModel()
        _ = try await loadArrangement(on: vm, multiStaff: true)
        #expect(vm.hasMultipleStaves == true)
    }

    // MARK: - AudioSession callbacks

    @Test("interruption-began pauses playback")
    func interruptionBeganPausesPlayback() async throws {
        let vm = makeViewModel()
        _ = try await loadArrangement(on: vm)
        vm.playback.installNoteEventsForTesting(
            [NoteEventFactory.make(swarName: "Sa", midiNote: 60, timestamp: 0, duration: 1)]
        )
        await vm.startSession()
        // Drive the public `onInterruptionBegan` callback the VM registered
        // in `setupAudioSessionCallbacks()`. Posting a real
        // `AVAudioSession.interruptionNotification` is unreliable in unit
        // tests because the system observer is `queue: .main` and may not
        // drain inside a single test tick.
        AudioSessionManager.shared.onInterruptionBegan?()
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(vm.playbackState == .paused)
        // Tear down callbacks so the next test starts clean.
        vm.cleanup()
    }

    @Test("route change with .oldDeviceUnavailable pauses playback")
    func routeChangeOldDevicePausesPlayback() async throws {
        let vm = makeViewModel()
        _ = try await loadArrangement(on: vm)
        vm.playback.installNoteEventsForTesting(
            [NoteEventFactory.make(swarName: "Sa", midiNote: 60, timestamp: 0, duration: 1)]
        )
        await vm.startSession()
        AudioSessionManager.shared.onRouteChangeWithReason?(.oldDeviceUnavailable)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(vm.playbackState == .paused)
        vm.cleanup()
    }

    // MARK: - Bluetooth practice-mode chip

    @Test("Bluetooth endpoint registration flips practiceModeChipVisible")
    func bluetoothEndpointTriggersChip() async {
        // Drive the singleton manager directly because the chip is wired
        // to its `onPracticeModeRequired` (test-double mocks don't surface
        // this hook). The VM init wires the callback.
        let manager = MIDIInputManager.shared
        let vm = makeViewModel(
            midiInput: MockMIDIInputProvider()  // not used for this path
        )
        // Re-attach the hook for the singleton manager (the VM init only
        // wires it when the resolved provider IS the manager — the mock
        // path is the fallback). Manually call the wiring as the
        // production code path would.
        manager.onPracticeModeRequired = { _ in
            Task { @MainActor in vm.practiceModeChipVisible = true }
        }
        defer { manager.onPracticeModeRequired = nil }

        // Use a randomised endpointID so the manager's `blockedEndpointIDs`
        // set treats this as a fresh insertion (`updateEndpoint` skips the
        // `onPracticeModeRequired` callback when the ID is already in the
        // blocklist from a previous test run).
        let descriptor = EndpointDescriptor(
            endpointID: Int32.random(in: 100_000...999_999),
            displayName: "Mock BLE",
            kind: .bluetooth
        )
        manager.updateEndpoint(0, descriptor: descriptor)
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(vm.practiceModeChipVisible == true)
    }

    @Test("scoring drops events while practiceModeChipVisible is true")
    func scoringDroppedDuringPracticeMode() async throws {
        let vm = makeViewModel()
        _ = try await loadArrangement(on: vm)
        vm.playback.installNoteEventsForTesting(
            [NoteEventFactory.make(swarName: "Sa", midiNote: 60, timestamp: 0, duration: 1)]
        )
        await vm.startSession()
        let beforeAttempts = vm.scoringAdapter?.summary().notesAttempted ?? 0
        vm.practiceModeChipVisible = true
        let event = MIDIInputEvent(noteNumber: 60, velocity: 90)
        vm.handleMIDINoteEventForScoring(event)
        let afterAttempts = vm.scoringAdapter?.summary().notesAttempted ?? 0
        #expect(beforeAttempts == afterAttempts)
        vm.cleanup()
    }

    // MARK: - Persistence

    @Test("stopAndComplete writes a PlayAlongSession to the model context")
    func stopAndCompleteWritesPlayAlongSession() async throws {
        let vm = makeViewModel()
        _ = try await loadArrangement(on: vm)
        vm.playback.installNoteEventsForTesting(
            [NoteEventFactory.make(swarName: "Sa", midiNote: 60, timestamp: 0, duration: 1)]
        )
        let context = try SwiftDataTestContainer.freshContext()
        vm.modelContext = context
        // Install a real Song so the persistence path has an id to use.
        let song = Song(slugId: "e1-fixture", title: "E1 Fixture")
        context.insert(song)
        try context.save()
        vm.playback.installSongInfoForTesting(
            slugId: "e1-fixture",
            title: "E1 Fixture",
            ragaName: "Yaman",
            difficulty: 1
        )
        await vm.startSession()
        vm.stopAndComplete()

        let descriptor = FetchDescriptor<PlayAlongSession>()
        let rows = try context.fetch(descriptor)
        #expect(rows.count >= 1)
        if let row = rows.first {
            #expect(row.tempoScale == vm.tempoScale)
            #expect(row.practiceMode == vm.practiceMode.rawValue)
        }
        vm.cleanup()
    }

    // MARK: - Cleanup

    // MARK: - Wave 5 — loadSong → loadArrangement auto-wiring

    /// `loadSong` on a Song without `midiData` falls back to the
    /// visualization-only path — no `arrangementPlayer`, no
    /// `scoringAdapter`, and no crash. Mirrors the legacy notation-only
    /// pipeline (Jana Gana Mana on first launch).
    /// `loadSong` on a Song that carries SMF bytes drives the
    /// production pipeline (`VerovioBridge.summarizeSMF` →
    /// `PartSplitter` → `MultiTrackSamplerGraph` → `loadArrangement`)
    /// and ends with a wired `arrangementPlayer` + `scoringAdapter`
    /// when the shared audio engine is available. Under
    /// `xcodebuild test` the simulator audio engine generally starts
    /// successfully, so we assert the wiring is present. When the
    /// engine cannot be started (CI sandbox), the call still completes
    /// — the visualization-only fallback is exercised by the sibling
    /// test below.
    @Test("loadSong with MXL data automatically loads arrangement")
    func loadSongWithMXLDataAutomaticallyLoadsArrangement() async throws {
        guard
            let url = Bundle.main.url(
                forResource: "Sukhkarta_Dukhharta",
                withExtension: "mxl"
            )
        else {
            Issue.record("Bundled Sukhkarta_Dukhharta.mxl missing")
            return
        }
        let context = try SwiftDataTestContainer.freshContext()
        let song = try ContentImportManager.importMusicXMLAsSong(from: url, into: context)
        #expect(song.midiData != nil)

        let vm = makeViewModel()
        await vm.loadSong(song)

        // When the shared audio engine is running, the MXL pipeline
        // produced an `arrangementPlayer` + `scoringAdapter`. When it
        // is not (e.g. headless CI), the call still completes
        // gracefully via the visualization-only fallback. We accept
        // either outcome — the contract under test is "no crash, and
        // when an engine is available, the arrangement is wired".
        if AudioEngineManager.shared.isRunning {
            #expect(vm.arrangementPlayer != nil)
            #expect(vm.scoringAdapter != nil)
            #expect(vm.currentSplit != nil)
        }
        vm.cleanup()
    }

    @Test("loadSong without MXL data falls back to visualization-only")
    func loadSongWithoutMXLDataFallsBackToVisualizationOnly() async {
        let vm = makeViewModel()
        let song = Song(slugId: "notation-only", title: "Notation Only")
        // Plant minimal sargam + western notation arrays so
        // PlaybackCoordinator.loadSong returns true rather than .error
        // — that path is the realistic notation-only fallback.
        let sargam: [String] = ["Sa", "Re", "Ga"]
        let western: [String] = ["C", "D", "E"]
        song.sargamNotation = try? JSONEncoder().encode(sargam)
        song.westernNotation = try? JSONEncoder().encode(western)
        await vm.loadSong(song)
        #expect(vm.arrangementPlayer == nil)
        #expect(vm.scoringAdapter == nil)
        vm.cleanup()
    }

    /// Simulating a beat tick after `loadArrangement` advances
    /// `PlaybackCoordinator.currentTime`. Closes Wave 5's last wiring
    /// gap: nothing was driving the visualization clock after D3.
    @Test("ArrangementPlayer tick advances PlaybackCoordinator currentTime")
    func arrangementPlayerTickAdvancesPlaybackCoordinatorTime() async throws {
        let vm = makeViewModel()
        _ = try await loadArrangement(on: vm, measureCount: 8)
        #expect(vm.playback.currentTime == 0)
        vm.arrangementPlayer?.start(countInBars: 0)
        // 4 beats at 120 BPM × 1.0 scale → 2.0 wall-clock seconds.
        vm.arrangementPlayer?.simulateBeatTick(beatsPerMeasure: 4, currentBeat: 4.0)
        #expect(vm.playback.currentTime > 0)
        // Tolerance for floating-point conversion, but tight enough to
        // prove the conversion ran (4 beats / (120/60) / 1.0 = 2.0 s).
        #expect(abs(vm.playback.currentTime - 2.0) < 0.01)
        vm.cleanup()
    }

    @Test("cleanup tears down ArrangementPlayer + ScoringAdapter + AudioSession callbacks")
    func cleanupTearsDownE1State() async throws {
        let vm = makeViewModel()
        _ = try await loadArrangement(on: vm)
        vm.cleanup()
        #expect(vm.arrangementPlayer == nil)
        #expect(vm.scoringAdapter == nil)
        #expect(vm.currentSplit == nil)
        #expect(AudioSessionManager.shared.onInterruptionBegan == nil)
        #expect(AudioSessionManager.shared.onRouteChangeWithReason == nil)
    }
}
