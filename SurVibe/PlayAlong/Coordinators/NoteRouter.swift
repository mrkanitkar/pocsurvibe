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
///   (per AUD-033) + `CADisplayLink`. NoteRouter does NOT change this path.
/// - **Phase 2 (off-MainActor scoring):** delegates to existing custom
///   `actor NoteMatchingActor`. NoteRouter is `@MainActor` and dispatches
///   into the actor via `await`.
@Observable
@MainActor
final class NoteRouter {

    /// Guided-play feedback state (only meaningful when playback is .idle/.paused).
    enum GuidedPlayState: Equatable {
        case waitingForNote
        case correct
        case wrong
        case stuck
    }

    // MARK: - Observed input state

    private(set) var currentPitch: PitchResult?
    private(set) var detectedMidiNotes: Set<Int> = []
    private(set) var isMIDIConnected: Bool = false
    private(set) var midiDeviceName: String?

    // MARK: - Observed guided-play state

    private(set) var guidedPlayState: GuidedPlayState = .waitingForNote
    private(set) var expectedMidiNote: Int?
    private(set) var isStuck: Bool = false

    // MARK: - Latency preset (D-SP3d-3)

    /// Latency preset for mic pitch detection. Persisted across sessions.
    /// Side-effect: changing while detection is active restarts the pipeline.
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

    // MARK: - Highlight state (shared with facade)

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

    // MARK: - Dependencies (injected) — ALL PRIVATE

    private let midiInput: any MIDIInputProviding
    private let scoring: ScoringCoordinator
    private let playback: PlaybackCoordinator

    // ADR-002 collaborators — preserved unchanged
    private let highlightCoordinator = MIDINoteHighlightCoordinator()
    private let noteMatchingActor = NoteMatchingActor()

    // Pitch detection collaborator
    private let audioProcessor = PracticeAudioProcessor()

    // MARK: - Internal task lifecycle state — ALL PRIVATE

    private var ringBuffer: SPSCRingBuffer?
    private var pitchDetectionTask: Task<Void, Never>?
    private var chordDetectionTask: Task<Void, Never>?
    private var chordListenerTask: Task<Void, Never>?
    private var midiConnectionTask: Task<Void, Never>?
    private var patienceTimerTask: Task<Void, Never>?

    private var latestChordResult: ChordResult?
    private var lastGuidedMidiNote: Int?
    private var lastMelodyDetectionDate: Date = .distantPast
    private var ragaScoringContext: RagaScoringContext?
    private var ragaMapper: RagaAwareMapper?

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

    /// Start mic + MIDI + chord-listener detection.
    /// Task 5 will append startPitchDetection() call; Task 8 wires full startup.
    func startInputDetection() {
        startMIDIDetection()
        // Task 5 will append startPitchDetection() call.
    }

    /// Stop and clear all input detection tasks/callbacks.
    /// Task 8 adds audioProcessor.stop() + pitchDetectionTask cancels + chord tasks + patience timer.
    func stopInputDetection() {
        detectedMidiNotes = []
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
        // Task 8 adds audioProcessor.stop() + pitchDetectionTask cancels + chord tasks + patience timer.
    }

    func handleKeyboardNoteOn(midiNote: Int) {
        detectedMidiNotes.insert(midiNote)
        updateDetectedSwarInfo(from: detectedMidiNotes)
        // Task 8: routing to processNoteInput / handleGuidedNoteDetected.
    }

    func handleKeyboardNoteOff(midiNote: Int) {
        detectedMidiNotes.remove(midiNote)
        updateDetectedSwarInfo(from: detectedMidiNotes)
    }

    func handleKeyboardTouch(midiNote: Int) async {
        detectedMidiNotes.insert(midiNote)
        updateDetectedSwarInfo(from: detectedMidiNotes)
        // Task 8: awaitable routing.
    }

    func handleKeyboardTouchGuided(midiNote: Int) {
        // Task 7: guided routing.
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
            // Task 7: startPatienceTimer() call.
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

    // MARK: - Public — MIDI routing

    /// Handle a note detected from pitch detection or MIDI input.
    /// Scores the detected note against the current expected note.
    func handleNoteDetected(midiNote: Int) {
        guard playback.playbackState == .playing else { return }
        Task { await processNoteInput(midiNote: midiNote) }
    }

    // MARK: - Private Methods — MIDI Detection

    /// Start live MIDI keyboard detection.
    ///
    /// Clears any previous callbacks, starts the highlight coordinator,
    /// syncs connection state, installs the two-phase note callback, and
    /// begins connection monitoring.
    private func startMIDIDetection() {
        midiInput.onNoteEvent = nil  // clear any previous callback before re-registering
        midiInput.onControlChangeEvent = nil
        midiConnectionTask?.cancel()
        midiConnectionTask = nil
        highlightCoordinator.start()
        // Relay coordinator highlight changes into the isolated HighlightState
        // observable. Only InteractivePianoView observes HighlightState, so this
        // write never triggers SongPlayAlongView.body to re-evaluate.
        let hs = highlightState
        highlightCoordinator.onActiveNotesChanged = { notes in
            hs.midiHighlightNotes = notes
        }
        midiInput.start()

        // Sync connection state after start
        isMIDIConnected = midiInput.isConnected
        midiDeviceName = midiInput.connectedDeviceName

        if isMIDIConnected {
            Self.logger.info(
                "MIDI keyboard detected: \(self.midiDeviceName ?? "unknown")"
            )
        }

        installMIDINoteCallback()
        startMIDIConnectionMonitoring()
    }

    /// Install the two-phase MIDI note-on/note-off callback on the MIDI input.
    ///
    /// ADR-002 Phase 1 (CoreMIDI thread, lock-free):
    /// - Diagnostic recording
    /// - MIDINoteHighlightCoordinator.noteOn/noteOff (OSAllocatedUnfairLock)
    ///
    /// ADR-002 Phase 2 (MainActor Task):
    /// - Scoring dispatch via handleNoteDetected / handleGuidedNoteDetected
    private func installMIDINoteCallback() {
        #if DEBUG
            MIDIEventDiagnostics.shared.reset()
            MIDIEventDiagnostics.shared.isEnabled = true
        #endif

        let coordinator = highlightCoordinator

        // CC callback: sustain pedal (CC64) and other controllers.
        // Runs on CoreMIDI's high-priority thread — no actor hop.
        midiInput.onControlChangeEvent = { event in
            guard event.isSustainPedal else { return }
            if event.isSustainDown {
                coordinator.sustainDown(channel: event.channel)
            } else {
                coordinator.sustainUp(channel: event.channel)
            }
        }

        midiInput.onNoteEvent = { [weak self] event in
            let midiNote = Int(event.noteNumber)

            // Phase 1: CoreMIDI thread — lock-free highlight + diagnostic recording.
            #if DEBUG
                MIDIEventDiagnostics.shared.recordCoremidi(event: event)
            #endif
            if event.isNoteOn {
                coordinator.noteOn(midiNote)
            } else {
                coordinator.noteOff(midiNote, channel: event.channel)
            }

            // Phase 2: MainActor — scoring only.
            Task(priority: .high) { @MainActor [weak self] in
                guard let self else { return }

                #if DEBUG
                    MIDIEventDiagnostics.shared.recordMainActor(event: event)
                #endif

                if event.isNoteOn {
                    if self.playback.playbackState == .playing {
                        self.handleNoteDetected(midiNote: midiNote)
                    } else if self.playback.playbackState == .idle || self.playback.playbackState == .paused {
                        self.handleGuidedNoteDetected(midiNote: midiNote)
                    }
                }
            }
        }
    }

    /// Start monitoring MIDI keyboard connect/disconnect events.
    private func startMIDIConnectionMonitoring() {
        midiConnectionTask = Task { [weak self] in
            guard let self else { return }
            for await connected in self.midiInput.connectionStateStream {
                guard !Task.isCancelled else { return }
                self.isMIDIConnected = connected
                self.midiDeviceName = connected ? self.midiInput.connectedDeviceName : nil
                Self.logger.info(
                    "MIDI connection changed: \(connected ? "connected" : "disconnected", privacy: .public)"
                )
            }
        }
    }

    // MARK: - Private helpers

    private func updateDetectedSwarInfo(from midiNotes: Set<Int>) {
        guard let midiNote = midiNotes.min() else {
            highlightState.detectedSwarInfo = nil
            return
        }
        let fullName = Self.swarNameFromMIDI(UInt8(midiNote))
        let baseName = fullName.components(separatedBy: " ").last ?? fullName
        let octave = (midiNote / 12) - 1
        highlightState.detectedSwarInfo = (name: baseName, octave: octave)
    }

    /// Derive the full swar name from a MIDI note number.
    ///
    /// Uses the pre-built O(1) `Swar.nameForSemitone` dictionary.
    ///
    /// - Parameter midiNote: MIDI note number (0–127).
    /// - Returns: Full swar name string (e.g., "Komal Re"). Falls back to "Sa".
    nonisolated private static func swarNameFromMIDI(_ midiNote: UInt8) -> String {
        let semitone = Int(midiNote) % 12
        return Swar.nameForSemitone[semitone] ?? Swar.sa.rawValue
    }

    /// Stub — Task 5 implements.
    private func startPitchDetection() async {}

    nonisolated private static func midiNoteFromFrequency(_ frequency: Double) -> Int {
        guard frequency > 0 else { return 60 }
        return Int((12.0 * log2(frequency / 440.0) + 69.0).rounded())
    }
}
