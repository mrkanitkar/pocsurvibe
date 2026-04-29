import Foundation
import SVCore
import Testing
@testable import SurVibe

@MainActor
struct ScratchpadStateTests {
    @Test func startsEmpty() {
        let s = ScratchpadState()
        #expect(s.notes.isEmpty)
        #expect(s.noteCount == 0)
        #expect(!s.hasContent)
        #expect(s.isAtSoftCap == false)
        #expect(s.isAtHardCap == false)
    }

    @Test func appendNoteOnThenOff() {
        let s = ScratchpadState()
        s.appendNoteOn(midi: 60, velocity: 100, velocity16: 0, channel: 0, onTimeSec: 0.0)
        s.appendNoteOff(midi: 60, channel: 0, offTimeSec: 0.5)
        #expect(s.notes.count == 1)
        #expect(s.notes[0].midi == 60)
        #expect(s.notes[0].onTimeSec == 0.0)
        #expect(s.notes[0].offTimeSec == 0.5)
    }

    @Test func startedAtSetOnFirstNote() {
        let s = ScratchpadState()
        #expect(s.startedAt == nil)
        s.appendNoteOn(midi: 60, velocity: 100, velocity16: 0, channel: 0, onTimeSec: 0.0)
        #expect(s.startedAt != nil)
    }

    @Test func undoLastNotePopsAndReturnsTrue() {
        let s = ScratchpadState()
        s.appendNoteOn(midi: 60, velocity: 100, velocity16: 0, channel: 0, onTimeSec: 0)
        s.appendNoteOff(midi: 60, channel: 0, offTimeSec: 0.5)
        s.appendNoteOn(midi: 62, velocity: 100, velocity16: 0, channel: 0, onTimeSec: 1)
        s.appendNoteOff(midi: 62, channel: 0, offTimeSec: 1.5)
        #expect(s.undoLastNote())
        #expect(s.notes.count == 1)
        #expect(s.notes[0].midi == 60)
    }

    @Test func undoOnEmptyReturnsFalse() {
        let s = ScratchpadState()
        #expect(s.undoLastNote() == false)
    }

    @Test func softCapAt1500() {
        let s = ScratchpadState()
        for i in 0..<1500 {
            s.appendNoteOn(midi: 60, velocity: 100, velocity16: 0, channel: 0, onTimeSec: Double(i) * 0.01)
            s.appendNoteOff(midi: 60, channel: 0, offTimeSec: Double(i) * 0.01 + 0.005)
        }
        #expect(s.isAtSoftCap == true)
        #expect(s.isAtHardCap == false)
    }

    @Test func hardCapAt5000DropsFurtherInput() {
        let s = ScratchpadState()
        for i in 0..<5000 {
            s.appendNoteOn(midi: 60, velocity: 100, velocity16: 0, channel: 0, onTimeSec: Double(i) * 0.01)
            s.appendNoteOff(midi: 60, channel: 0, offTimeSec: Double(i) * 0.01 + 0.005)
        }
        #expect(s.isAtHardCap == true)
        let beforeCount = s.notes.count
        s.appendNoteOn(midi: 72, velocity: 100, velocity16: 0, channel: 0, onTimeSec: 1000)
        s.appendNoteOff(midi: 72, channel: 0, offTimeSec: 1000.1)
        #expect(s.notes.count == beforeCount, "appends past hard cap must be dropped")
    }

    @Test func sustainEvents() {
        let s = ScratchpadState()
        s.appendNoteOn(midi: 60, velocity: 100, velocity16: 0, channel: 0, onTimeSec: 0)
        s.appendSustain(down: true, channel: 0, atTimeSec: 0.1)
        s.appendSustain(down: false, channel: 0, atTimeSec: 0.5)
        #expect(s.sustain.count == 2)
        #expect(s.sustain[0].down)
        #expect(!s.sustain[1].down)
    }

    @Test func clearFlushesOpenNotesAndResets() {
        let s = ScratchpadState()
        s.appendNoteOn(midi: 60, velocity: 100, velocity16: 0, channel: 0, onTimeSec: 0)
        // No matching off — note is "open".
        #expect(s.hasContent)
        s.clear(programOverride: nil, saOverride: nil)
        #expect(s.notes.isEmpty)
        #expect(s.startedAt == nil)
        #expect(!s.hasContent)
    }

    @Test func clearWithOverrides() {
        let s = ScratchpadState()
        s.appendNoteOn(midi: 60, velocity: 100, velocity16: 0, channel: 0, onTimeSec: 0)
        s.clear(programOverride: 105, saOverride: 62)
        #expect(s.instrumentProgram == 105)
        #expect(s.saPitchMidi == 62)
    }

    @Test func freezeForSaveClosesOpenNotes() {
        let s = ScratchpadState()
        s.appendNoteOn(midi: 60, velocity: 100, velocity16: 0, channel: 0, onTimeSec: 0)
        // No off — note still open.
        let frozen = s.freezeForSave()
        #expect(frozen.notes.count == 1)
        #expect(frozen.notes[0].offTimeSec >= frozen.notes[0].onTimeSec)
    }

    @Test func sustainFlushedDownAtHardCap() {
        let s = ScratchpadState()
        s.appendSustain(down: true, channel: 0, atTimeSec: 0)
        // Drive to hard cap.
        for i in 0..<5000 {
            s.appendNoteOn(midi: 60, velocity: 100, velocity16: 0, channel: 0, onTimeSec: Double(i) * 0.01)
            s.appendNoteOff(midi: 60, channel: 0, offTimeSec: Double(i) * 0.01 + 0.005)
        }
        // The hard-cap synthesised sustain-up should appear.
        #expect(s.sustain.contains(where: { !$0.down }), "hard-cap flush must close any open sustain pedal")
    }
}
