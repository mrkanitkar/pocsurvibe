import CoreMIDI
import Darwin.Mach
import Foundation
import SVAudio
import SVCore
import SwiftData
import Synchronization
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

/// Type-erased shim that lets the Phase-1 timestamp helper accept either
/// `MIDIInputEvent` or `MIDIControlChangeEvent` without copying.
///
/// The witness is `nonisolated` because Phase 1 runs on the CoreMIDI thread —
/// the underlying structs are `Sendable` value types whose stored properties
/// are inherently nonisolated, but the swift-6 default-MainActor-isolation
/// app target needs the protocol requirement marked explicitly.
protocol HasMIDITimestamp: Sendable {
    nonisolated var midiTimestamp: MIDITimeStamp? { get }
}

extension MIDIInputEvent: HasMIDITimestamp {}
extension MIDIControlChangeEvent: HasMIDITimestamp {}

/// Owns the Play tab's state: current instrument, Sa pitch, notation mode,
/// active highlighted notes, and the always-on `ScratchpadState` recording.
///
/// Touch events arrive via SwiftUI on the main thread (already played by
/// `InteractivePianoView`). MIDI events arrive on a CoreMIDI thread; the
/// VM flips the highlight bit synchronously on that thread (see ``onAppear()``)
/// and only the non-latency-critical bookkeeping hops to MainActor.
///
/// MIDI input never plays through the iPad's built-in sampler — the user's
/// external MIDI keyboard is expected to produce its own sound, and doubling
/// would only create an unwanted echo.
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
            scratchpad.setInstrumentProgram(currentInstrument)
        }
    }

    /// Performer's tonic (Sa) as a MIDI note number. Defaults to middle C (60).
    var saPitch: UInt8 {
        didSet {
            UserDefaults.standard.set(Int(saPitch), forKey: Self.kSaPitch)
            scratchpad.setSaPitchMidi(saPitch)
        }
    }

    // MARK: - Session-only state

    /// Notation display mode. Session-only (not persisted in v1).
    var notationMode: PlayTabNotationMode = .both

    /// MIDI notes currently held down (touch + MIDI). Drives keyboard highlight.
    private(set) var activeMidiNotes: Set<UInt8> = []

    /// Whether the Takes list sheet is currently presented. Bound from the
    /// Play tab's overflow menu (T16b → T16c…); flipping to `true` brings up
    /// `TakesListSheet`, flipping to `false` dismisses it.
    var takesListSheetPresented: Bool = false

    /// Always-on capture buffer. Replaces v1 `recordedNotes: [RecordedNote]`
    /// (16-note strip). Wiped on tab change, New Session, or Save.
    let scratchpad: ScratchpadState

    /// Most recent user-facing error message. `nil` when no error pending.
    private(set) var lastError: String?

    /// Whether the Save Take sheet is currently presented. Toggled by the ⋯
    /// menu's "Save take" action and cleared when the sheet dismisses.
    var saveTakeSheetPresented: Bool = false

    /// Whether ``onAppear()`` has run since the last ``onDisappear()``.
    /// Guards against scenePhase double-fire — `.task` runs once and
    /// `scenePhase == .active` may fire again on every foreground transition,
    /// which otherwise re-loads the SF2 program needlessly.
    private var isAppeared: Bool = false

    // MARK: - Dependencies

    /// Engine reference held behind an unfair lock so MIDI-thread callers
    /// could read it without a MainActor hop. The MIDI path no longer routes
    /// audio through the iPad sampler, but the lock stays in place for the
    /// touch path's `playTouchNote` / `loadProgram` calls.
    private let engineLock: OSAllocatedUnfairLock<any PlayTabAudioEngine>
    private let midiInput: any MIDIInputProviding

    /// Highlight coordinator. `nonisolated` so the MIDI-thread `onNoteEvent`
    /// closure can call `noteOn`/`noteOff` directly without an actor hop —
    /// the coordinator's note bit-flip is itself `nonisolated` and lock-
    /// protected. Lifecycle (`start`/`stop`) is still invoked from MainActor.
    nonisolated private let highlightCoordinator: MIDINoteHighlightCoordinator

    /// Reference host-tick captured at the first MIDI event after `onAppear()`
    /// (or after `clearScratchpad()` resets it). Used by Phase 1 to compute
    /// `onTimeSec` without a MainActor hop. `Mutex<UInt64?>` matches the
    /// SoundAnalysisGate / MIDIDeJitterFilter pattern in SVAudio.
    nonisolated private let referenceMIDITicks: Mutex<UInt64?>

    /// Snapshot the current engine. Cheap (uncontended unfair lock).
    private var engine: any PlayTabAudioEngine {
        engineLock.withLock { $0 }
    }

    private static let kInstrument = "playTab.lastInstrument"
    private static let kSaPitch = "playTab.saPitch"

    private let log = Logger.survibe(category: "PlayTab")

    // MARK: - Init

    /// Construct a Play tab view model.
    ///
    /// - Parameters:
    ///   - engine: Audio engine surface used to load programs and play touch
    ///     notes. In production, the shared `ProductionMultiChannelEngine`.
    ///   - midiInput: Live MIDI source. Provider is owned by the caller; the
    ///     VM only sets/clears the `onNoteEvent` and `onControlChangeEvent`
    ///     closures on ``onAppear()``/``onDisappear()``.
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
        self.referenceMIDITicks = Mutex<UInt64?>(nil)
        let storedInstrument = UInt8(
            UserDefaults.standard.object(forKey: Self.kInstrument) as? Int ?? 0
        )
        let storedSa = UInt8(
            UserDefaults.standard.object(forKey: Self.kSaPitch) as? Int ?? 60
        )
        self.currentInstrument = storedInstrument
        self.saPitch = storedSa
        self.scratchpad = ScratchpadState(
            instrumentProgram: storedInstrument,
            saPitchMidi: storedSa
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

    /// Install a callback that fires every time the highlight coordinator
    /// publishes a new active-notes set (driven by a CADisplayLink, so the
    /// cadence is bounded by display refresh — typically 8–16 ms).
    ///
    /// Used by `PlayTab` to drive the visual highlight (staff + keyboard) on
    /// the display-link path instead of waiting for a `Task { @MainActor }`
    /// hop in the MIDI bookkeeping pipeline. This matches PlayAlong's
    /// keyboard-highlight path and keeps perceived MIDI→highlight latency
    /// under one display frame.
    ///
    /// The callback receives a `Set<Int>` of MIDI note numbers currently
    /// highlighted. It runs on the main actor; assign the value into a
    /// `@State` on the view to drive SwiftUI re-render.
    ///
    /// - Parameter callback: Closure invoked when the highlight set changes.
    func installHighlightObserver(_ callback: @escaping @MainActor (Set<Int>) -> Void) {
        highlightCoordinator.onActiveNotesChanged = callback
    }

    /// Handle a note-on from either touch or MIDI.
    ///
    /// Neither source produces audio in this method:
    /// - Touch: `InteractivePianoView` already played the note.
    /// - MIDI: this method is only entered for the touch path (the MIDI hot
    ///   path runs through ``onAppear()`` → Phase 1 / Phase 2). Touch is
    ///   human-paced so we sample `Date()` for `onTimeSec`.
    func handleNoteOn(_ midi: UInt8, velocity: UInt8, source: NoteSource) {
        let wasAlreadyOn = activeMidiNotes.contains(midi)
        if source == .touch {
            highlightCoordinator.noteOn(Int(midi))
        }
        activeMidiNotes.insert(midi)
        if !wasAlreadyOn {
            let onTime = currentTouchOnTimeSec()
            scratchpad.appendNoteOn(
                midi: midi, velocity: velocity, velocity16: 0,
                channel: 0, onTimeSec: onTime
            )
        }
    }

    /// Handle a note-off from either touch or MIDI.
    ///
    /// Mirrors ``handleNoteOn(_:velocity:source:)`` — the MIDI path already
    /// cleared the highlight bit on the CoreMIDI thread, so we only flip it
    /// here for touch.
    func handleNoteOff(_ midi: UInt8, source: NoteSource) {
        if source == .touch {
            highlightCoordinator.noteOff(Int(midi))
        }
        let wasOn = activeMidiNotes.remove(midi) != nil
        if wasOn {
            scratchpad.appendNoteOff(
                midi: midi, channel: 0,
                offTimeSec: currentTouchOnTimeSec()
            )
        }
    }

    /// Reset the scratchpad and the Phase-1 timestamp reference. Replaces
    /// v1's `clearStrip()` (which only emptied the 16-note strip).
    ///
    /// - Parameters:
    ///   - programOverride: When non-nil, replaces `scratchpad.instrumentProgram`.
    ///     When nil the value is preserved (useful for the Save path which
    ///     materialises the take with its own program snapshot).
    ///   - saOverride: When non-nil, replaces `scratchpad.saPitchMidi`.
    func clearScratchpad(programOverride: UInt8? = nil, saOverride: UInt8? = nil) {
        referenceMIDITicks.withLock { $0 = nil }
        scratchpad.clear(programOverride: programOverride, saOverride: saOverride)
    }

    /// Deprecated v1 alias — kept so any pre-existing test or call site still
    /// compiles with a deprecation warning.
    @available(*, deprecated, renamed: "clearScratchpad")
    func clearStrip() { clearScratchpad() }

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
    /// The MIDI closure runs in two phases per spec §5.2.1:
    ///
    /// 1. **Phase 1 (sync, MIDI thread).** `highlightCoordinator` is
    ///    `nonisolated` and lock-protected — flipping its note bit on the
    ///    CoreMIDI thread costs ~ns and is picked up by the next display-link
    ///    frame. `onTimeSec` is computed *here* from the hardware
    ///    `MIDIInputEvent.midiTimestamp` to preserve sub-frame accuracy. No
    ///    MainActor hop on this path; no `Date()` sample.
    ///
    /// 2. **Phase 2 (async, MainActor).** `activeMidiNotes`, `scratchpad`,
    ///    and `lastError` are SwiftUI-observable; they hop to the main actor
    ///    where their write triggers a re-render. Not latency-critical
    ///    because the visual highlight already updated.
    ///
    /// Audio is never produced from MIDI input — the user's external keyboard
    /// makes sound; doubling through the iPad sampler creates an echo.
    func onAppear() {
        guard !isAppeared else { return }
        isAppeared = true
        midiInput.onNoteEvent = { [weak self] event in
            guard let self else { return }
            // Capture only `Sendable` scalars + the hardware-derived onTime
            // before crossing isolation. NEVER call @MainActor properties
            // or sample Date() inside this closure.
            let note = event.noteNumber
            let velocity = event.velocity
            let velocity16 = event.velocity16Bit
            let channel = event.channel
            let onTimeSec = self.computeOnTimeSec(from: event)
            // Phase 1: flip the highlight bit synchronously on the MIDI
            // thread. The display-link picks it up on the next frame.
            // Verified sub-100us on iPad Air; matches PlayAlong's NoteRouter.
            if velocity > 0 {
                self.highlightCoordinator.noteOn(Int(note))
            } else {
                self.highlightCoordinator.noteOff(Int(note))
            }
            // Phase 2: bookkeeping + scratchpad mutation on MainActor.
            Task { @MainActor [weak self] in
                self?.dispatchMIDIBookkeeping(
                    note: note, velocity: velocity, velocity16: velocity16,
                    channel: channel, onTimeSec: onTimeSec
                )
            }
        }
        midiInput.onControlChangeEvent = { [weak self] event in
            guard let self else { return }
            // Sustain pedal only — other CCs are not part of the v2 capture
            // contract. (CC isolation invariant: never forward to a sampler.)
            guard event.controller == 64 else { return }
            let down = event.value >= 64
            let channel = event.channel
            let atTimeSec = self.computeOnTimeSec(from: event)
            // Phase 1: highlight bit flip (sustain affects key release semantics).
            if down {
                self.highlightCoordinator.sustainDown()
            } else {
                self.highlightCoordinator.sustainUp()
            }
            // Phase 2: scratchpad mutation on MainActor.
            Task { @MainActor [weak self] in
                self?.scratchpad.appendSustain(
                    down: down, channel: channel, atTimeSec: atTimeSec
                )
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

    /// Stop everything, clear the MIDI handlers, and stop the highlight coordinator.
    func onDisappear() {
        allNotesOff()
        midiInput.onNoteEvent = nil
        midiInput.onControlChangeEvent = nil
        highlightCoordinator.stop()
        referenceMIDITicks.withLock { $0 = nil }
        isAppeared = false
    }

    // MARK: - Phase 1 helpers (nonisolated)

    /// Phase-1 helper: convert a hardware MIDI timestamp into seconds since
    /// the first MIDI event of the current scratchpad recording.
    ///
    /// On the very first event the reference is unset; we snap it here and
    /// return 0. Subsequent events return the host-tick delta converted to
    /// seconds via `mach_timebase_info`. Events without a hardware timestamp
    /// (e.g. test doubles) fall back to 0 — the Phase-2 hop will still record
    /// the note, just without sub-frame precision.
    ///
    /// Safe to call from any thread: backed by a `Mutex<UInt64?>` snapshot.
    nonisolated private func computeOnTimeSec<E: HasMIDITimestamp>(from event: E) -> TimeInterval {
        guard let ts = event.midiTimestamp else { return 0 }
        let snapshot = referenceMIDITicks.withLock { current -> UInt64? in
            if current == nil {
                current = ts
                return nil   // signal "first event"
            }
            return current
        }
        guard let ref = snapshot else { return 0 }
        // Use saturating subtraction in case a backdated event somehow arrives.
        let delta = ts >= ref ? ts &- ref : 0
        return Self.hostTicksToSeconds(delta)
    }

    /// Convert host ticks to seconds via `mach_timebase_info`.
    nonisolated private static func hostTicksToSeconds(_ ticks: UInt64) -> TimeInterval {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let nanos = Double(ticks) * Double(info.numer) / Double(info.denom)
        return nanos / 1_000_000_000.0
    }

    // MARK: - Phase 2 dispatcher (MainActor)

    /// Phase-2 MIDI bookkeeping — runs on the main actor. Updates the
    /// SwiftUI-observable `activeMidiNotes` and `scratchpad`. Does NOT
    /// touch the highlight coordinator (already flipped on the MIDI thread)
    /// or the audio engine (MIDI input never plays through the iPad sampler).
    private func dispatchMIDIBookkeeping(
        note: UInt8, velocity: UInt8, velocity16: UInt16,
        channel: UInt8, onTimeSec: TimeInterval
    ) {
        if velocity > 0 {
            let wasAlreadyOn = activeMidiNotes.contains(note)
            activeMidiNotes.insert(note)
            if !wasAlreadyOn {
                scratchpad.appendNoteOn(
                    midi: note, velocity: velocity, velocity16: velocity16,
                    channel: channel, onTimeSec: onTimeSec
                )
            }
        } else {
            activeMidiNotes.remove(note)
            scratchpad.appendNoteOff(
                midi: note, channel: channel, offTimeSec: onTimeSec
            )
        }
    }

    // MARK: - Touch path helper (MainActor)

    /// Touch-path `onTimeSec` source. Touch is human-paced so a `Date()`
    /// sample is appropriate (no sub-frame requirement). Returns 0 before
    /// the scratchpad has its `startedAt` snapped (i.e. the first event of
    /// the recording session).
    private func currentTouchOnTimeSec() -> TimeInterval {
        guard let started = scratchpad.startedAt else { return 0 }
        return Date().timeIntervalSince(started)
    }

    // MARK: - Save take

    /// Materialise the current scratchpad into a persisted ``RecordedTake``.
    ///
    /// Freezes the live scratchpad (closing any open notes / sustains at the
    /// current time), encodes the snapshot into a `RecordedTake`, inserts it
    /// into the supplied `ModelContext`, and saves. On success the scratchpad
    /// is cleared without overriding the active program or Sa pitch — the
    /// performer keeps their current setup ready for the next take.
    ///
    /// `scratchpad` and `modelContext` are passed in rather than read from
    /// VM properties because both are introduced by Task 6 (parallel branch);
    /// keeping the dependency local lets Task 16a build standalone and lets
    /// T6's merge thin this signature down without touching the call sites
    /// inside `SaveTakeSheet`.
    ///
    /// - Parameters:
    ///   - scratchpad: Live recording buffer to freeze and persist.
    ///   - modelContext: SwiftData context that owns the `RecordedTake` model.
    ///   - title: User-supplied take title (must be non-empty per the sheet).
    ///   - ragaTagId: Optional raga catalog tag.
    ///   - teacherNotes: Free-form notes for the teacher.
    func saveTake(
        scratchpad: ScratchpadState,
        modelContext: ModelContext,
        title: String,
        ragaTagId: String?,
        teacherNotes: String
    ) async {
        let frozen = scratchpad.freezeForSave()
        let take = RecordedTake(
            title: title,
            instrumentProgram: scratchpad.instrumentProgram,
            saPitchMidi: scratchpad.saPitchMidi,
            ragaTagId: ragaTagId,
            teacherNotes: teacherNotes,
            notes: frozen.notes,
            sustain: frozen.sustain
        )
        modelContext.insert(take)
        do {
            try modelContext.save()
        } catch {
            lastError = "Couldn't save: \(error.localizedDescription)"
            log.error("RecordedTake save failed: \(String(describing: error))")
            return
        }
        scratchpad.clear(programOverride: nil, saOverride: nil)
        saveTakeSheetPresented = false
    }

    /// Number of `RecordedTake` rows currently persisted.
    ///
    /// Used by the Save Take sheet to seed the title placeholder
    /// (`"Take N · <date>"`). On fetch failure returns 0 — the user just sees
    /// `"Take 1"` until the next save succeeds.
    ///
    /// - Parameter modelContext: SwiftData context to query.
    /// - Returns: Count of persisted takes.
    func takesCount(in modelContext: ModelContext) -> Int {
        (try? modelContext.fetchCount(FetchDescriptor<RecordedTake>())) ?? 0
    }
}
