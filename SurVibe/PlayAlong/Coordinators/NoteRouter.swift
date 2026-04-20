// SurVibe/PlayAlong/Coordinators/NoteRouter.swift
// swiftlint:disable file_length
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
// swiftlint:disable:next type_body_length
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
                startPitchDetection()
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

    /// Wait mode controller — nil until PlaybackCoordinator exposes it (mirrors VM pattern).
    private var waitController: PlayAlongWaitController?

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
    func startInputDetection() {
        startMIDIDetection()
        startPitchDetection()
    }

    /// Stop and clear all input detection tasks/callbacks.
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
        patienceTimerTask?.cancel()
        patienceTimerTask = nil
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
        guard playback.playbackState == .idle || playback.playbackState == .paused else { return }
        handleGuidedNoteDetected(midiNote: midiNote)
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
            startPatienceTimer()
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

    nonisolated private static func midiNoteFromFrequency(_ frequency: Double) -> Int {
        guard frequency > 0 else { return 60 }
        return Int((12.0 * log2(frequency / 440.0) + 69.0).rounded())
    }

    // MARK: - Private Methods — Pitch + Chord Detection

    /// Start microphone pitch and chord detection pipeline.
    ///
    /// Cancels any existing consumer tasks, allocates a fresh ring buffer sized to
    /// the current latency preset, starts `PracticeAudioProcessor`, then launches
    /// the melody detection task, chord detection task, and chord listener task.
    private func startPitchDetection() {
        // Cancel existing consumer tasks. Only restart the processor when it is not
        // yet running — reinstalling the mic tap unnecessarily causes a dropout.
        pitchDetectionTask?.cancel()
        pitchDetectionTask = nil

        // Allocate a fresh ring buffer sized to the current latency preset.
        // Capacity = realSamples * 2 so we always have a full window available.
        // SPSCRingBuffer rounds up to the next power of two internally, so the
        // request is a hint — the actual capacity may be larger.
        let preset = latencyPreset
        let newRingBuffer = SPSCRingBuffer(capacity: preset.realSamples * 2)
        ringBuffer = newRingBuffer

        // Give PracticeAudioProcessor the ring buffer reference BEFORE start(),
        // so the tap closure captures it when it is installed during start().
        audioProcessor.ringBuffer = newRingBuffer

        if !audioProcessor.isActive {
            do {
                try audioProcessor.start()
                Self.logger.info("MicDiag: audioProcessor.start() succeeded")
            } catch {
                Self.logger.error(
                    "MicDiag: audioProcessor.start() FAILED: \(error.localizedDescription, privacy: .public)"
                )
                return
            }
        } else {
            Self.logger.info("MicDiag: audioProcessor already active — skipping start()")
        }

        let engineRunning = AudioEngineManager.shared.isRunning
        let hasTap = AudioEngineManager.shared.hasMicTap
        Self.logger.info(
            "MicDiag: engine.isRunning=\(engineRunning) hasMicTap=\(hasTap) isMIDIConnected=\(self.isMIDIConnected)"
        )
        Self.logger.info(
            "Pitch detection started: preset=\(preset.rawValue) realSamples=\(preset.realSamples)"
        )

        // --- Melody detection task ---
        // Reads PitchResult from PracticeAudioProcessor's autocorrelation stream.
        pitchDetectionTask = Task { [weak self] in
            await self?.runMelodyDetectionLoop()
        }

        chordDetectionTask?.cancel()
        chordDetectionTask = Task { [weak self] in
            await self?.runChordDetectionLoop(realSamples: preset.realSamples)
        }

        // MAJ-2: subscribe to the chord stream so chord-aware scoring in
        // `processNoteInput` always has a fresh `ChordResult` to consult.
        chordListenerTask?.cancel()
        chordListenerTask = Task { [weak self] in
            guard let stream = self?.audioProcessor.chordStream else { return }
            for await chord in stream {
                guard !Task.isCancelled else { return }
                self?.latestChordResult = chord
            }
        }
    }

    /// Poll the ring buffer for chromagram chord analysis and route to scoring.
    ///
    /// Runs every 50 ms, gated on minimum RMS amplitude to reject speaker bleed.
    /// Falls back to scoring only when the melody autocorrelation path has not
    /// handled a note in the last 80 ms (avoids double-scoring).
    private func runChordDetectionLoop(realSamples: Int) async {
        let buf = ringBuffer
        let refPitch = 440.0
        let amplitudeGate: Float = 0.01
        // Pre-allocate the read buffer once; reuse on every poll. Owned by
        // the chord task so it is deallocated when the task exits (cancel
        // or stop). Avoids per-iteration heap churn at 20 Hz.
        let workBuf = UnsafeMutableBufferPointer<Float>.allocate(capacity: realSamples)
        workBuf.initialize(repeating: 0)
        defer { workBuf.deallocate() }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
            guard let buf, buf.readLatest(count: realSamples, into: workBuf),
                let base = workBuf.baseAddress
            else { continue }
            let samples = Array(UnsafeBufferPointer(start: base, count: realSamples))
            let rms = Self.calculateRMS(samples)
            guard rms >= amplitudeGate else { continue }
            let result = ChromagramDSP.analyzeChord(
                samples: samples,
                sampleRate: 44100,
                referencePitch: refPitch
            )
            guard !result.detectedPitches.isEmpty else { continue }
            guard !isMIDIConnected else { continue }

            let midiNotes = Set(result.detectedPitches.map { $0.midiNote })
            detectedMidiNotes = midiNotes
            updateDetectedSwarInfo(from: midiNotes)

            let melodyAge = Date().timeIntervalSince(lastMelodyDetectionDate)
            guard melodyAge > 0.080 else { continue }
            guard let dominant = result.detectedPitches.max(by: { $0.confidence < $1.confidence }) else {
                continue
            }
            routeNoteToScoring(midiNote: dominant.midiNote)
        }
    }

    /// Route a detected MIDI note to timed scoring or guided free-play.
    private func routeNoteToScoring(midiNote: Int) {
        if playback.playbackState == .playing {
            handleNoteDetected(midiNote: midiNote)
        } else if playback.playbackState == .idle || playback.playbackState == .paused {
            handleGuidedNoteDetected(midiNote: midiNote)
        }
    }

    /// Consume the autocorrelation pitch stream and update UI/scoring state.
    ///
    /// Extracted from `startPitchDetection()` to keep that function within the
    /// SwiftLint `function_body_length` limit. Runs for the lifetime of
    /// `pitchDetectionTask` and exits when the stream ends or the Task is cancelled.
    private func runMelodyDetectionLoop() async {
        var pitchResultCount = 0
        var belowThresholdCount = 0
        Self.logger.info("MicDiag: melody task started — isMIDIConnected=\(self.isMIDIConnected)")
        for await pitchResult in self.audioProcessor.pitchStream {
            guard !Task.isCancelled else {
                Self.logger.info(
                    "MicDiag: melody task cancelled (results=\(pitchResultCount) belowThresh=\(belowThresholdCount))"
                )
                return
            }

            let enriched = self.enrichPitchWithRagaContext(pitchResult)

            let ampStr = String(format: "%.4f", enriched.amplitude)
            let confStr = String(format: "%.3f", enriched.confidence)
            let freqStr = String(format: "%.1f", enriched.frequency)
            let silThresh = String(format: "%.4f", PracticeConstants.silenceThreshold)
            let confThresh = String(format: "%.3f", PracticeConstants.confidenceThreshold)
            let midiConn = self.isMIDIConnected
            Self.logger.info(
                // swiftlint:disable:next line_length
                "MicDiag: pitchStream result #\(pitchResultCount) freq=\(freqStr)Hz note=\(enriched.noteName, privacy: .public)\(enriched.octave) amp=\(ampStr)/\(silThresh) conf=\(confStr)/\(confThresh) midiConnected=\(midiConn)"
            )
            pitchResultCount += 1

            if enriched.amplitude >= PracticeConstants.silenceThreshold,
                enriched.confidence >= PracticeConstants.confidenceThreshold
            {
                processMelodyPitch(enriched)
            } else {
                belowThresholdCount += 1
                clearMelodyHighlight()
            }
        }
        Self.logger.info(
            "MicDiag: melody task stream ended (results=\(pitchResultCount) belowThresh=\(belowThresholdCount))"
        )
    }

    /// Process a pitch that passed amplitude and confidence thresholds.
    private func processMelodyPitch(_ enriched: PitchResult) {
        currentPitch = enriched
        lastMelodyDetectionDate = Date()
        let midiNote = Self.midiNoteFromFrequency(enriched.frequency)
        if !isMIDIConnected {
            Self.logger.info(
                "MicDiag: highlight note=\(midiNote) (\(enriched.noteName, privacy: .public)\(enriched.octave))"
            )
            detectedMidiNotes = [midiNote]
            updateDetectedSwarInfo(from: detectedMidiNotes)
        } else {
            Self.logger.info("MicDiag: MIDI connected — skipping detectedMidiNotes update")
        }
        routeNoteToScoring(midiNote: midiNote)
    }

    /// Clear melody highlight state when pitch falls below threshold.
    private func clearMelodyHighlight() {
        currentPitch = nil
        if !isMIDIConnected {
            detectedMidiNotes = []
            highlightState.detectedSwarInfo = nil
        }
        lastGuidedMidiNote = nil
    }

    /// Calculate RMS amplitude from audio samples.
    ///
    /// - Parameter samples: Float audio samples.
    /// - Returns: Root-mean-square amplitude (0.0–1.0).
    private static func calculateRMS(_ samples: [Float]) -> Float {
        var sum: Float = 0
        for s in samples { sum += s * s }
        return sqrt(sum / Float(samples.count))
    }

    /// Enrich a pitch result with raga-aware mapping when a mapper is configured.
    ///
    /// When a `RagaAwareMapper` is available, re-maps the frequency to get JI
    /// cents offset and in-raga status. Falls through to the original result otherwise.
    ///
    /// - Parameter pitch: Raw pitch result from the audio processor.
    /// - Returns: Enriched pitch result with `isInRaga` and `ragaCentsOffset` set.
    private func enrichPitchWithRagaContext(_ pitch: PitchResult) -> PitchResult {
        guard let mapper = ragaMapper else { return pitch }
        do {
            let mapping = try mapper.mapFrequency(pitch.frequency, referencePitch: 440.0)
            return PitchResult(
                frequency: pitch.frequency,
                amplitude: pitch.amplitude,
                noteName: mapping.noteName,
                octave: mapping.octave,
                centsOffset: pitch.centsOffset,
                confidence: pitch.confidence,
                isInRaga: mapping.isInRaga,
                ragaCentsOffset: mapping.ragaCentsOffset
            )
        } catch {
            return pitch
        }
    }

    // MARK: - Private Methods — Note Input Processing

    /// Process a note input (from either keyboard touch or pitch detection).
    ///
    /// Scoring arithmetic runs on `NoteMatchingActor` (off `@MainActor`) so it never
    /// competes with SwiftUI's falling-notes render pass. Only the resulting
    /// `ScoringDiff` hops back to update `@Observable` state on `@MainActor`.
    ///
    /// Wait-mode evaluation via `PlayAlongWaitController` still happens here on
    /// `@MainActor` (the controller is `@MainActor`-isolated) — the boolean result
    /// is then passed as a `Sendable` value to the actor.
    ///
    /// - Parameter midiNote: MIDI note number of the input.
    private func processNoteInput(midiNote: Int) async {
        guard let index = playback.currentNoteIndex,
            index < playback.noteEvents.count
        else { return }

        let expectedEvent = playback.noteEvents[index]

        // Evaluate wait-mode match here on @MainActor (PlayAlongWaitController is
        // @MainActor-isolated). Pass the Bool result to the actor as a Sendable value.
        let waitModeMatch: Bool?
        if playback.isWaitModeEnabled, let waitCtrl = waitController {
            let detectedSwarName = Self.swarNameFromMIDI(UInt8(clamping: midiNote))
            waitModeMatch = waitCtrl.evaluateAttempt(detectedNoteName: detectedSwarName)
        } else {
            waitModeMatch = nil
        }

        // Snapshot Sendable values before crossing actor boundary.
        let pitch = currentPitch
        let ragaContext = ragaScoringContext

        // Compute timing deviation: difference between actual onset and expected onset.
        // In wait mode, timing is not scored (defaults to 0 via evaluateWaitMode).
        let onsetDeviation = abs(playback.currentTime - expectedEvent.timestamp)

        // Duration deviation requires note-off tracking (not yet implemented).
        // Pass 0 until note-off timestamps are captured in a future task.
        let durDeviation = 0.0

        var diff = await noteMatchingActor.evaluate(
            midiNote: midiNote,
            expectedEvent: expectedEvent,
            currentPitch: pitch,
            ragaScoringContext: ragaContext,
            waitModeMatch: waitModeMatch,
            timingDeviationSeconds: onsetDeviation,
            durationDeviation: durDeviation
        )

        // MAJ-2: if the expected event belongs to a chord group AND a fresh
        // chord analysis is available from the mic stream, attach a completeness
        // score and blend it into the per-note accuracy. Single-note events
        // skip this path entirely (chordCompleteness stays nil).
        if let chordGroup = findChordGroup(for: expectedEvent),
            let chord = latestChordResult
        {
            let expectedSet = Set(chordGroup.map { Int($0.midiNote) })
            let detectedSet = chord.activeMidiNotes
            let completeness = await noteMatchingActor.evaluateChord(
                expectedChordNotes: expectedSet,
                detectedNotes: detectedSet
            )
            diff.chordCompleteness = completeness
            if let baseScore = diff.score {
                diff = applyChordCompleteness(
                    completeness,
                    to: diff,
                    baseScore: baseScore
                )
            }
        }

        // Apply the diff back on @MainActor — only three writes, no re-render
        // of the full note list.
        playback.noteStates[diff.noteEventID] = diff.newState
        if let score = diff.score {
            scoring.record(score)
        }
        switch diff.streakOutcome {
        case .hit(let grade):
            scoring.updateStreak(grade: grade)
        case .miss:
            scoring.updateStreak(grade: .miss)
        case .noChange:
            break
        }
    }

    /// Group `NoteEvent`s that share the given event's onset within the
    /// `chordGroupingWindow` (10 ms) into a single chord group.
    ///
    /// The returned group includes the input event itself. Returns `nil` when
    /// the event has no neighbours inside the window — i.e. it is a single
    /// melodic note, not part of a chord.
    ///
    /// - Parameter event: The expected event currently under evaluation.
    /// - Returns: All `NoteEvent`s within ±`chordGroupingWindow` of `event`'s
    ///   timestamp, or `nil` when no other event qualifies.
    private func findChordGroup(for event: NoteEvent) -> [NoteEvent]? {
        let window = Self.chordGroupingWindow
        let group = playback.noteEvents.filter { abs($0.timestamp - event.timestamp) <= window }
        return group.count >= 2 ? group : nil
    }

    /// Blend a chord-completeness factor into an existing per-note `NoteScore`.
    ///
    /// Returns a `ScoringDiff` with `score.accuracy` multiplied by the
    /// completeness fraction (so missing chord notes pull the per-note accuracy
    /// down). The `chordCompleteness` field is preserved on the returned diff.
    ///
    /// - Parameters:
    ///   - completeness: Chord completeness fraction in `0.0...1.0`.
    ///   - diff: The existing scoring diff with `chordCompleteness` already set.
    ///   - baseScore: The non-blended `NoteScore` produced by `NoteMatchingActor`.
    /// - Returns: A new diff carrying a blended-accuracy score.
    private func applyChordCompleteness(
        _ completeness: Double,
        to diff: ScoringDiff,
        baseScore: NoteScore
    ) -> ScoringDiff {
        let blended = NoteScore(
            id: baseScore.id,
            grade: baseScore.grade,
            accuracy: baseScore.accuracy * completeness,
            pitchDeviationCents: baseScore.pitchDeviationCents,
            timingDeviationSeconds: baseScore.timingDeviationSeconds,
            durationDeviation: baseScore.durationDeviation,
            expectedNote: baseScore.expectedNote,
            detectedNote: baseScore.detectedNote,
            isOutOfRaga: baseScore.isOutOfRaga,
            expressionResult: baseScore.expressionResult,
            timestamp: baseScore.timestamp
        )
        return ScoringDiff(
            noteEventID: diff.noteEventID,
            newState: diff.newState,
            score: blended,
            streakOutcome: diff.streakOutcome,
            probeToken: diff.probeToken,
            chordCompleteness: completeness
        )
    }

    // MARK: - Private Methods — Guided Free-Play

    /// Handle a note detected in guided free-play mode (before/after timed playback).
    ///
    /// Compares the detected MIDI note against the expected note at
    /// `currentNoteIndex`. On correct: flash green, advance to next note.
    /// On wrong: flash red, keep waiting. Resets the patience timer on every
    /// detected note so the hint only fires during silence.
    ///
    /// - Parameter midiNote: MIDI note number of the detected pitch.
    private func handleGuidedNoteDetected(midiNote: Int) {
        guard let index = playback.currentNoteIndex, index < playback.noteEvents.count else { return }

        // Debounce: only score when the MIDI note changes (new onset).
        // The mic fires ~20 frames/second while a note is held — without this
        // the note would be scored and the index would advance multiple times
        // before the user releases the key.
        guard midiNote != lastGuidedMidiNote else { return }
        lastGuidedMidiNote = midiNote

        let expectedEvent = playback.noteEvents[index]
        let isCorrect = Int(expectedEvent.midiNote) == midiNote

        // Any note input resets the patience timer (user is actively playing)
        isStuck = false
        startPatienceTimer()

        let detectedSwarName = Self.swarNameFromMIDI(UInt8(clamping: midiNote))
        let centsDeviation: Double
        if let pitch = currentPitch {
            centsDeviation = abs(pitch.ragaCentsOffset ?? pitch.centsOffset)
        } else {
            centsDeviation = isCorrect ? 0 : 50
        }

        if isCorrect {
            handleGuidedCorrectNote(
                event: expectedEvent,
                index: index,
                detectedSwarName: detectedSwarName,
                centsDeviation: centsDeviation
            )
        } else {
            handleGuidedWrongNote(event: expectedEvent)
        }
    }

    /// Score a correct guided-mode note and advance to the next event.
    private func handleGuidedCorrectNote(
        event: NoteEvent,
        index: Int,
        detectedSwarName: String,
        centsDeviation: Double
    ) {
        playback.noteStates[event.id] = .correct
        let score = NoteScoreCalculator.score(
            expectedNote: event.swarName,
            detectedNote: detectedSwarName,
            pitchDeviationCents: centsDeviation,
            timingDeviationSeconds: 0,
            durationDeviation: 0,
            ragaPitchDeviationCents: currentPitch?.ragaCentsOffset.map { abs($0) },
            ragaContext: ragaScoringContext
        )
        scoring.record(score)
        scoring.updateStreak(grade: score.grade)
        guidedPlayState = .correct
        lastGuidedMidiNote = nil

        let nextIndex = index + 1
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(150))
            if nextIndex < self.playback.noteEvents.count {
                self.playback.currentNoteIndex = nextIndex
                self.updateExpectedMidiNote()
                self.guidedPlayState = .waitingForNote
                self.isStuck = false
                self.startPatienceTimer()
            } else {
                self.playback.currentNoteIndex = nil
                self.expectedMidiNote = nil
                self.guidedPlayState = .waitingForNote
            }
        }
    }

    /// Flash wrong feedback and reset debounce for the next attempt.
    private func handleGuidedWrongNote(event: NoteEvent) {
        playback.noteStates[event.id] = .wrong
        guidedPlayState = .wrong
        lastGuidedMidiNote = nil
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(100))
            if self.guidedPlayState == .wrong {
                self.guidedPlayState = .waitingForNote
            }
        }
    }

    /// Start the patience timer for the current expected note.
    ///
    /// After `patienceSeconds` of silence, transitions to `.stuck` state
    /// so the view can show a hint overlay.
    private func startPatienceTimer() {
        patienceTimerTask?.cancel()
        patienceTimerTask = Task { [weak self] in
            guard let self else { return }
            let timeout = self.patienceSeconds
            try? await Task.sleep(for: .seconds(timeout))
            guard !Task.isCancelled else { return }
            // Only mark stuck when in guided mode (not during timed playback)
            if self.playback.playbackState == .idle || self.playback.playbackState == .paused {
                self.isStuck = true
                self.guidedPlayState = .stuck
            }
        }
    }
}
