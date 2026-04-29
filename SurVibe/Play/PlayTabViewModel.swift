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

    /// Whether the recording strip has reached its cap.
    var isStripFull: Bool { recordedNotes.count >= Self.stripCap }

    // MARK: - Dependencies

    private let engine: any PlayTabAudioEngine
    private let midiInput: any MIDIInputProviding
    private let highlightCoordinator: MIDINoteHighlightCoordinator

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
        self.engine = engine
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
            lastError = "Couldn't load \(GMInstrumentCatalog.name(for: program))"
            log.error("loadProgram failed for \(program): \(String(describing: error))")
        }
    }

    /// Update the performer's tonic (Sa) MIDI pitch.
    func setSaPitch(_ midi: UInt8) {
        saPitch = midi
        log.info("Sa pitch -> \(midi)")
    }

    /// Update the notation display mode.
    func setNotationMode(_ mode: PlayTabNotationMode) {
        notationMode = mode
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
    func onAppear() {
        midiInput.onNoteEvent = { [weak self] event in
            // Capture only `Sendable` scalars before crossing the actor hop.
            let note = event.noteNumber
            let velocity = event.velocity
            Task { @MainActor [weak self] in
                self?.dispatchMIDI(note: note, velocity: velocity)
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
    }

    private func dispatchMIDI(note: UInt8, velocity: UInt8) {
        if velocity > 0 {
            handleNoteOn(note, velocity: velocity, source: .midi)
        } else {
            handleNoteOff(note, source: .midi)
        }
    }
}
