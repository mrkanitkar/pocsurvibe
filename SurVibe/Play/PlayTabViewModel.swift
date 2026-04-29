import Foundation
import SVAudio
import SVCore
import os

/// Notation display mode for the Play tab top staff and recording strip.
enum PlayTabNotationMode: Hashable, Sendable {
    case western
    case sargam
    case both
}

/// Source of a note event delivered to ``PlayTabViewModel``.
///
/// Touch notes are already produced by `InteractivePianoView`; the VM only
/// observes them. MIDI notes arrive from a connected hardware device and the
/// VM is responsible for producing audio.
enum NoteSource: Hashable, Sendable {
    case touch
    case midi
}

/// One entry in the capped recording strip.
struct RecordedNote: Identifiable, Equatable, Sendable {
    let id = UUID()
    let midi: UInt8
    let timestamp: Date

    init(midi: UInt8, timestamp: Date = Date()) {
        self.midi = midi
        self.timestamp = timestamp
    }
}

/// Owns the Play tab's state: current instrument, Sa pitch, notation mode,
/// active highlighted notes, and the capped recording strip.
///
/// Touch events arrive via SwiftUI on the main thread (already played by
/// `InteractivePianoView`). MIDI events arrive on a CoreMIDI thread; the
/// `onNoteEvent` closure hops to MainActor before touching VM state.
@MainActor
@Observable
final class PlayTabViewModel {
    // MARK: - Persisted state
    //
    // We use UserDefaults + `didSet` rather than `@AppStorage` because
    // `@AppStorage` does not propagate observation through `@Observable`
    // classes (it is a SwiftUI `DynamicProperty`). `didSet` writes the new
    // value to UserDefaults; the `@Observable` macro tracks the property so
    // SwiftUI re-renders observers on change.

    /// Current GM program (0–127). Persisted across launches.
    var currentInstrument: UInt8 {
        didSet {
            UserDefaults.standard.set(Int(currentInstrument), forKey: Self.kInstrument)
        }
    }

    /// Performer's tonic (Sa) as a MIDI note number. Defaults to middle C (60).
    var saPitch: UInt8 {
        didSet {
            UserDefaults.standard.set(Int(saPitch), forKey: Self.kSaPitch)
        }
    }

    // MARK: - Session-only state

    /// Notation display mode. Session-only (not persisted in v1).
    var notationMode: PlayTabNotationMode = .both

    /// MIDI notes currently held down (touch + MIDI). Drives keyboard highlight.
    private(set) var activeMidiNotes: Set<UInt8> = []

    /// Capped recording strip — last ``stripCap`` distinct note-ons.
    private(set) var recordedNotes: [RecordedNote] = []

    /// Most recent user-facing error message. `nil` when no error pending.
    private(set) var lastError: String?

    /// Whether ``onAppear()`` has run since the last ``onDisappear()``.
    /// Guards against scenePhase double-fire — `.task` runs once and
    /// `scenePhase == .active` may fire again on every foreground transition,
    /// which otherwise re-loads the SF2 program needlessly.
    private var isAppeared: Bool = false

    /// Whether the recording strip has reached its cap.
    var isStripFull: Bool { recordedNotes.count >= Self.stripCap }

    // MARK: - Dependencies

    /// Engine reference held behind an unfair lock so MIDI-thread callbacks
    /// (`engineSyncPlay` / `engineSyncStop`) can read it without a MainActor
    /// hop. Initial value comes from `init`; ``attachEngine(_:)`` swaps it
    /// when the real `ProductionMultiChannelEngine` becomes available.
    private let engineLock: OSAllocatedUnfairLock<any PlayTabAudioEngine>
    private let midiInput: any MIDIInputProviding
    private let highlightCoordinator: MIDINoteHighlightCoordinator

    /// Snapshot the current engine. Cheap (uncontended unfair lock).
    private var engine: any PlayTabAudioEngine {
        engineLock.withLock { $0 }
    }

    private static let kInstrument = "playTab.lastInstrument"
    private static let kSaPitch = "playTab.saPitch"
    private static let stripCap = 16

    private let log = Logger.survibe(category: "PlayTab")

    // MARK: - Init

    /// Construct a Play tab view model.
    ///
    /// - Parameters:
    ///   - engine: Audio engine surface used to load programs and play touch
    ///     notes. In production, the shared `ProductionMultiChannelEngine`.
    ///   - midiInput: Live MIDI source. Provider is owned by the caller; the
    ///     VM only sets/clears the `onNoteEvent` closure on
    ///     ``onAppear()``/``onDisappear()``.
    ///   - highlightCoordinator: Display-link-driven coordinator that owns
    ///     the highlighted-keys state for the keyboard view.
    init(
        engine: any PlayTabAudioEngine,
        midiInput: any MIDIInputProviding,
        highlightCoordinator: MIDINoteHighlightCoordinator
    ) {
        self.engineLock = OSAllocatedUnfairLock(initialState: engine)
        self.midiInput = midiInput
        self.highlightCoordinator = highlightCoordinator
        self.currentInstrument = UInt8(
            UserDefaults.standard.object(forKey: Self.kInstrument) as? Int ?? 0
        )
        self.saPitch = UInt8(
            UserDefaults.standard.object(forKey: Self.kSaPitch) as? Int ?? 60
        )
    }

    // MARK: - Public actions

    /// Switch the touch sampler to the given GM program.
    ///
    /// Stops every currently-ringing touch note (instrument change otherwise
    /// produces a stuck-note glitch). On `loadProgram` failure the previous
    /// instrument is restored and ``lastError`` is set.
    func setInstrument(_ program: UInt8) {
        let previous = currentInstrument
        engine.stopAllTouchNotes()
        activeMidiNotes.removeAll()
        do {
            try engine.loadProgram(into: 0, program: program, isPercussion: false)
            currentInstrument = program
            log.info("Loaded GM program \(program) — \(GMInstrumentCatalog.name(for: program))")
        } catch {
            currentInstrument = previous
            // Re-load the previous program so the sampler's bank matches the
            // rolled-back currentInstrument label. Without this, the sampler
            // is left in an indeterminate state — the failed program may have
            // partially loaded, and the user sees "Acoustic Grand" but hears
            // whatever fragment leaked through.
            try? engine.loadProgram(into: 0, program: previous, isPercussion: false)
            lastError = "Couldn't load \(GMInstrumentCatalog.name(for: program))"
            log.error("loadProgram failed for \(program): \(String(describing: error))")
        }
    }

    /// Replace the audio engine reference and force-reload the current GM
    /// program on the new engine.
    ///
    /// Called from `PlayTab.task` after `AudioEngineManager.startForPlayback()`
    /// succeeds — the VM is initialized with a `PlaceholderAudioEngine` because
    /// `AudioEngineManager.shared.multiChannel` is `nil` at view-init time.
    /// Without this swap the VM would route MIDI keypresses to the placeholder
    /// forever and the user would hear silence.
    ///
    /// Idempotent: calling with the same engine instance still re-loads the
    /// current program, which is harmless and keeps the touch sampler in a
    /// known state.
    ///
    /// - Parameter engine: The real audio engine to use for subsequent
    ///   `playTouchNote` / `loadProgram` calls.
    func attachEngine(_ engine: any PlayTabAudioEngine) {
        engineLock.withLock { $0 = engine }
        do {
            try engine.loadProgram(into: 0, program: currentInstrument, isPercussion: false)
        } catch {
            log.error("attachEngine loadProgram failed: \(String(describing: error))")
            lastError = "Audio unavailable — try restarting the app."
        }
    }

    /// Update the performer's tonic (Sa) MIDI pitch.
    func setSaPitch(_ midi: UInt8) {
        saPitch = midi
        log.info("Sa pitch -> \(midi)")
    }

    /// Handle a note-on from either touch or MIDI.
    ///
    /// Touch path: VM observes only — `InteractivePianoView` produces audio.
    /// MIDI path: VM produces audio with the supplied velocity.
    func handleNoteOn(_ midi: UInt8, velocity: UInt8, source: NoteSource) {
        let wasAlreadyOn = activeMidiNotes.contains(midi)
        if source == .midi {
            engine.playTouchNote(midi, velocity: velocity)
        }
        highlightCoordinator.noteOn(Int(midi))
        activeMidiNotes.insert(midi)
        if !wasAlreadyOn && !isStripFull {
            recordedNotes.append(RecordedNote(midi: midi))
        } else if !wasAlreadyOn && isStripFull {
            log.debug("Strip full — note \(midi) plays but is not recorded")
        }
    }

    /// Handle a note-off from either touch or MIDI.
    func handleNoteOff(_ midi: UInt8, source: NoteSource) {
        if source == .midi {
            engine.stopTouchNote(midi)
        }
        highlightCoordinator.noteOff(Int(midi))
        activeMidiNotes.remove(midi)
    }

    /// Empty the recording strip without affecting currently held notes.
    func clearStrip() {
        recordedNotes.removeAll()
    }

    /// Stop everything and clear active-note state.
    func allNotesOff() {
        engine.stopAllTouchNotes()
        for midi in activeMidiNotes {
            highlightCoordinator.noteOff(Int(midi))
        }
        activeMidiNotes.removeAll()
    }

    // MARK: - Lifecycle

    /// Wire MIDI input, start the highlight coordinator, and force-reload the
    /// current program so we are not playing whatever the previous tab left.
    ///
    /// The MIDI closure runs in two phases to keep the touch-to-sound budget
    /// under SurVibe's 3–10 ms target:
    ///
    /// 1. **Engine call (sync, MIDI thread).** `engineSyncPlay/Stop` invokes
    ///    the nonisolated `playTouchNote` / `stopTouchNote` directly —
    ///    `AVAudioUnitSampler` is documented thread-safe, so no MainActor hop.
    ///
    /// 2. **Bookkeeping (async, MainActor).** Only the SwiftUI-observable
    ///    state (`activeMidiNotes`, `recordedNotes`, `highlightCoordinator`)
    ///    hops to the main actor — that is not latency-critical.
    func onAppear() {
        guard !isAppeared else { return }
        isAppeared = true
        midiInput.onNoteEvent = { [weak self] event in
            // Capture only `Sendable` scalars before crossing isolation.
            let note = event.noteNumber
            let velocity = event.velocity
            // Phase 1: latency-critical engine call on the MIDI thread.
            if velocity > 0 {
                self?.engineSyncPlay(note: note, velocity: velocity)
            } else {
                self?.engineSyncStop(note: note)
            }
            // Phase 2: bookkeeping on main actor.
            Task { @MainActor [weak self] in
                self?.dispatchMIDIBookkeeping(note: note, velocity: velocity)
            }
        }
        highlightCoordinator.start()
        do {
            try engine.loadProgram(into: 0, program: currentInstrument, isPercussion: false)
        } catch {
            log.error("onAppear loadProgram failed: \(String(describing: error))")
            lastError = "Audio unavailable — try restarting the app."
        }
    }

    /// Stop everything, clear the MIDI handler, and stop the highlight coordinator.
    func onDisappear() {
        allNotesOff()
        midiInput.onNoteEvent = nil
        highlightCoordinator.stop()
        isAppeared = false
    }

    /// Phase-1 engine call — runs synchronously on the CoreMIDI callback
    /// thread. Touches only the locked engine snapshot.
    nonisolated private func engineSyncPlay(note: UInt8, velocity: UInt8) {
        let snapshot = engineLock.withLock { $0 }
        snapshot.playTouchNote(note, velocity: velocity)
    }

    /// Phase-1 engine stop — runs synchronously on the CoreMIDI callback thread.
    nonisolated private func engineSyncStop(note: UInt8) {
        let snapshot = engineLock.withLock { $0 }
        snapshot.stopTouchNote(note)
    }

    /// Phase-2 MIDI bookkeeping — runs on the main actor. Updates the
    /// SwiftUI-observable state but does NOT touch the engine (the engine
    /// already played the note in phase 1).
    private func dispatchMIDIBookkeeping(note: UInt8, velocity: UInt8) {
        if velocity > 0 {
            recordNoteOnBookkeeping(note: note)
        } else {
            recordNoteOffBookkeeping(note: note)
        }
    }

    private func recordNoteOnBookkeeping(note: UInt8) {
        let wasAlreadyOn = activeMidiNotes.contains(note)
        highlightCoordinator.noteOn(Int(note))
        activeMidiNotes.insert(note)
        if !wasAlreadyOn && !isStripFull {
            recordedNotes.append(RecordedNote(midi: note))
        } else if !wasAlreadyOn && isStripFull {
            log.debug("Strip full — note \(note) plays but is not recorded")
        }
    }

    private func recordNoteOffBookkeeping(note: UInt8) {
        highlightCoordinator.noteOff(Int(note))
        activeMidiNotes.remove(note)
    }
}
