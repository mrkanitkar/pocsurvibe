import Foundation
import Observation
import SVCore

/// Ephemeral live recording buffer for the Play tab.
///
/// Wiped on tab change, New Session, or Save (when materialised into a
/// `RecordedTake`). All mutations happen on the main actor in MIDI Phase 2 —
/// see Play tab v2 spec §5.2.1. Open notes (note-on without matching note-off)
/// are flushed on `clear()`, `freezeForSave()`, or hard-cap with a synthesised
/// `offTimeSec` equal to the flush moment.
///
/// `notes` and `sustain` arrays are `@Observable`-tracked but per the
/// observation-isolation rule (§5.2.2) only scalar derived values
/// (`noteCount`, `durationSec`, cap flags) should be bound by views that
/// re-render on every Phase-2 update.
@MainActor
@Observable
public final class ScratchpadState {
    /// Soft cap — UI banner appears at this note count.
    public static let softCap = 1500
    /// Hard cap — further input is dropped past this note count.
    public static let hardCap = 5000
    /// Maximum depth of the per-note undo stack.
    public static let undoStackCap = 20

    public private(set) var notes: [RecordedNote] = []
    public private(set) var sustain: [RecordedSustainEvent] = []
    public private(set) var startedAt: Date?
    public private(set) var instrumentProgram: UInt8 = 0
    public private(set) var saPitchMidi: UInt8 = 60      // C4 default

    private struct PendingNote {
        let id: UUID
        let velocity: UInt8
        let velocity16Bit: UInt16
        let onTimeSec: TimeInterval
        let channel: UInt8
    }
    private var openNotes: [UInt8: PendingNote] = [:]
    private var openSustainChannels: Set<UInt8> = []
    private var undoStack: [UUID] = []      // ids of recently-closed notes (most recent last)

    /// Creates a fresh scratchpad with the supplied program and Sa pitch.
    ///
    /// - Parameters:
    ///   - instrumentProgram: General MIDI program (0–127). Defaults to 0.
    ///   - saPitchMidi: MIDI note number for the tonic Sa. Defaults to C4 (60).
    public init(instrumentProgram: UInt8 = 0, saPitchMidi: UInt8 = 60) {
        self.instrumentProgram = instrumentProgram
        self.saPitchMidi = saPitchMidi
    }

    /// Number of completed notes in the scratchpad.
    public var noteCount: Int { notes.count }
    /// True once the soft cap (1500 notes) is reached.
    public var isAtSoftCap: Bool { notes.count >= Self.softCap }
    /// True once the hard cap (5000 notes) is reached. Further input is dropped.
    public var isAtHardCap: Bool { notes.count >= Self.hardCap }
    /// True if any notes (open or closed) or sustain events have been captured.
    public var hasContent: Bool { !notes.isEmpty || !openNotes.isEmpty || !sustain.isEmpty }
    /// Wall-clock seconds since `startedAt`. Returns 0 before the first note.
    public var durationSec: TimeInterval {
        guard let started = startedAt else { return 0 }
        return Date().timeIntervalSince(started)
    }

    // MARK: - Phase-2 mutators (MainActor only)

    /// Updates the active instrument program. Does not affect captured notes.
    public func setInstrumentProgram(_ program: UInt8) { self.instrumentProgram = program }
    /// Updates the active Sa (tonic) MIDI pitch. Does not affect captured notes.
    public func setSaPitchMidi(_ midi: UInt8) { self.saPitchMidi = midi }

    /// Records a note-on. Drops the event if at hard cap.
    ///
    /// Sets `startedAt` on the first note of a recording. The note is held in
    /// `openNotes` until a matching `appendNoteOff` arrives.
    public func appendNoteOn(
        midi: UInt8, velocity: UInt8, velocity16: UInt16,
        channel: UInt8, onTimeSec: TimeInterval
    ) {
        guard !isAtHardCap else { return }
        if startedAt == nil { startedAt = Date() }
        openNotes[midi] = PendingNote(
            id: UUID(), velocity: velocity, velocity16Bit: velocity16,
            onTimeSec: onTimeSec, channel: channel
        )
    }

    /// Records a note-off, materialising the matching open note into `notes`.
    /// No-op if there is no matching open note. Triggers a hard-cap flush
    /// (closing any open sustain pedals) if the cap is reached.
    public func appendNoteOff(midi: UInt8, channel: UInt8, offTimeSec: TimeInterval) {
        guard let pending = openNotes.removeValue(forKey: midi) else { return }
        let note = RecordedNote(
            id: pending.id, midi: midi, velocity: pending.velocity,
            velocity16Bit: pending.velocity16Bit,
            onTimeSec: pending.onTimeSec, offTimeSec: offTimeSec, channel: channel
        )
        notes.append(note)
        pushUndo(pending.id)
        if isAtHardCap { synthesiseHardCapFlush(atTimeSec: offTimeSec) }
    }

    /// Records a sustain pedal (CC 64) event. Dropped if at hard cap.
    public func appendSustain(down: Bool, channel: UInt8, atTimeSec: TimeInterval) {
        guard !isAtHardCap else { return }
        if down {
            openSustainChannels.insert(channel)
        } else {
            openSustainChannels.remove(channel)
        }
        sustain.append(RecordedSustainEvent(timeSec: atTimeSec, down: down, channel: channel))
    }

    /// Removes the most recently closed note. Returns true if a note was popped.
    @discardableResult
    public func undoLastNote() -> Bool {
        guard let id = undoStack.popLast(),
              let idx = notes.lastIndex(where: { $0.id == id })
        else { return false }
        notes.remove(at: idx)
        return true
    }

    /// Reset the scratchpad. Optionally replace `instrumentProgram` and
    /// `saPitchMidi` (callers pass current toolbar values; nil preserves).
    public func clear(programOverride: UInt8?, saOverride: UInt8?) {
        notes.removeAll()
        sustain.removeAll()
        openNotes.removeAll()
        openSustainChannels.removeAll()
        undoStack.removeAll()
        startedAt = nil
        if let p = programOverride { instrumentProgram = p }
        if let s = saOverride { saPitchMidi = s }
    }

    /// Snapshot the current scratchpad as Sendable arrays. Closes any open
    /// notes at the latest `offTimeSec` seen so far (or `durationSec`).
    public func freezeForSave() -> (notes: [RecordedNote], sustain: [RecordedSustainEvent]) {
        var out = notes
        let nowSec = max(durationSec, notes.map(\.offTimeSec).max() ?? 0)
        for (midi, p) in openNotes {
            out.append(RecordedNote(
                id: p.id, midi: midi, velocity: p.velocity,
                velocity16Bit: p.velocity16Bit,
                onTimeSec: p.onTimeSec, offTimeSec: nowSec, channel: p.channel
            ))
        }
        var sus = sustain
        for ch in openSustainChannels {
            sus.append(RecordedSustainEvent(timeSec: nowSec, down: false, channel: ch))
        }
        return (out.sorted { $0.onTimeSec < $1.onTimeSec }, sus.sorted { $0.timeSec < $1.timeSec })
    }

    // MARK: - Private

    private func pushUndo(_ id: UUID) {
        undoStack.append(id)
        if undoStack.count > Self.undoStackCap { undoStack.removeFirst(undoStack.count - Self.undoStackCap) }
    }

    private func synthesiseHardCapFlush(atTimeSec: TimeInterval) {
        for ch in openSustainChannels {
            sustain.append(RecordedSustainEvent(timeSec: atTimeSec, down: false, channel: ch))
        }
        openSustainChannels.removeAll()
    }
}
