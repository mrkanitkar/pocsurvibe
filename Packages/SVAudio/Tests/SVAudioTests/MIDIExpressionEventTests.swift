import Foundation
import Testing

@testable import SVAudio

// MARK: - MIDIPitchBendEvent Tests

@Suite("MIDIPitchBendEvent Tests")
struct MIDIPitchBendEventTests {

    @Test("Default values are correct")
    func defaultValues() {
        let event = MIDIPitchBendEvent(value: 0)
        #expect(event.value == 0)
        #expect(event.noteNumber == nil)
        #expect(event.channel == 0)
        #expect(event.midiTimestamp == nil)
        #expect(!event.isPerNote)
        #expect(event.resolution == .midi2)
    }

    @Test("Per-note pitch bend sets noteNumber")
    func perNoteBend() {
        let event = MIDIPitchBendEvent(value: 1000, noteNumber: 60)
        #expect(event.isPerNote)
        #expect(event.noteNumber == 60)
    }

    @Test("toCents with MIDI 1.0 14-bit full positive bend")
    func toCentsMidi1FullPositive() {
        let event = MIDIPitchBendEvent(value: 8191, resolution: .midi1)
        let cents = event.toCents(bendRangeSemitones: 2.0)
        #expect(cents > 199.0)
        #expect(cents < 200.1)
    }

    @Test("toCents with MIDI 1.0 14-bit center returns zero")
    func toCentsMidi1Center() {
        let event = MIDIPitchBendEvent(value: 0, resolution: .midi1)
        #expect(event.toCents() == 0.0)
    }

    @Test("toCents with MIDI 2.0 32-bit full negative bend")
    func toCentsMidi2FullNegative() {
        let event = MIDIPitchBendEvent(value: Int32.min, resolution: .midi2)
        let cents = event.toCents(bendRangeSemitones: 2.0)
        #expect(cents <= -199.0)
    }

    @Test("Equatable conformance works correctly")
    func equatable() {
        let a = MIDIPitchBendEvent(value: 100, channel: 1)
        let b = MIDIPitchBendEvent(value: 100, channel: 1)
        let c = MIDIPitchBendEvent(value: 200, channel: 1)
        #expect(a == b)
        #expect(a != c)
    }
}

// MARK: - MIDIPressureEvent Tests

@Suite("MIDIPressureEvent Tests")
struct MIDIPressureEventTests {

    @Test("Channel pressure has nil noteNumber")
    func channelPressure() {
        let event = MIDIPressureEvent(pressure: 1_000_000)
        #expect(event.noteNumber == nil)
        #expect(!event.isPerNote)
    }

    @Test("Poly pressure has noteNumber set")
    func polyPressure() {
        let event = MIDIPressureEvent(noteNumber: 64, pressure: 2_000_000_000)
        #expect(event.noteNumber == 64)
        #expect(event.isPerNote)
    }

    @Test("pressure7Bit extracts top 7 bits")
    func pressure7BitComputation() {
        let full = MIDIPressureEvent(pressure: UInt32.max)
        #expect(full.pressure7Bit == 127)

        let zero = MIDIPressureEvent(pressure: 0)
        #expect(zero.pressure7Bit == 0)

        let half = MIDIPressureEvent(pressure: 0x80000000)
        #expect(half.pressure7Bit == 64)
    }
}

// MARK: - MIDIProgramChangeEvent Tests

@Suite("MIDIProgramChangeEvent Tests")
struct MIDIProgramChangeEventTests {

    @Test("Default bank is invalid")
    func defaultBankInvalid() {
        let event = MIDIProgramChangeEvent(program: 42)
        #expect(event.program == 42)
        #expect(!event.bankIsValid)
        #expect(event.bankMSB == 0)
        #expect(event.bankLSB == 0)
    }

    @Test("Valid bank select stores MSB and LSB")
    func validBankSelect() {
        let event = MIDIProgramChangeEvent(
            program: 0, bankMSB: 1, bankLSB: 32, bankIsValid: true
        )
        #expect(event.bankIsValid)
        #expect(event.bankMSB == 1)
        #expect(event.bankLSB == 32)
    }
}

// MARK: - MIDIPerNoteControlEvent Tests

@Suite("MIDIPerNoteControlEvent Tests")
struct MIDIPerNoteControlEventTests {

    @Test("Registered control type is default")
    func registeredDefault() {
        let event = MIDIPerNoteControlEvent(noteNumber: 60, index: 7, value: 1000)
        #expect(event.controlType == .registered)
    }

    @Test("Assignable control type stores correctly")
    func assignableType() {
        let event = MIDIPerNoteControlEvent(
            noteNumber: 64, index: 1, value: 500, controlType: .assignable
        )
        #expect(event.controlType == .assignable)
        #expect(event.noteNumber == 64)
        #expect(event.index == 1)
        #expect(event.value == 500)
    }
}

// MARK: - MIDIRegisteredControlEvent Tests

@Suite("MIDIRegisteredControlEvent Tests")
struct MIDIRegisteredControlEventTests {

    @Test("All four control types store correctly")
    func allControlTypes() {
        let types: [MIDIRegisteredControlEvent.ControlType] = [
            .registered, .assignable, .relativeRegistered, .relativeAssignable,
        ]
        for controlType in types {
            let event = MIDIRegisteredControlEvent(
                bank: 0, index: 0, value: 100, controlType: controlType
            )
            #expect(event.controlType == controlType)
        }
    }

    @Test("Bank and index stored correctly")
    func bankAndIndex() {
        let event = MIDIRegisteredControlEvent(bank: 3, index: 7, value: 42)
        #expect(event.bank == 3)
        #expect(event.index == 7)
        #expect(event.value == 42)
    }
}

// MARK: - MIDIPerNoteManagementEvent Tests

@Suite("MIDIPerNoteManagementEvent Tests")
struct MIDIPerNoteManagementEventTests {

    @Test("Default flags are false")
    func defaultFlags() {
        let event = MIDIPerNoteManagementEvent(noteNumber: 60)
        #expect(!event.detach)
        #expect(!event.reset)
    }

    @Test("Detach flag sets correctly")
    func detachFlag() {
        let event = MIDIPerNoteManagementEvent(noteNumber: 60, detach: true)
        #expect(event.detach)
        #expect(!event.reset)
    }

    @Test("Reset flag sets correctly")
    func resetFlag() {
        let event = MIDIPerNoteManagementEvent(noteNumber: 60, reset: true)
        #expect(!event.detach)
        #expect(event.reset)
    }

    @Test("Both flags set simultaneously")
    func bothFlags() {
        let event = MIDIPerNoteManagementEvent(noteNumber: 60, detach: true, reset: true)
        #expect(event.detach)
        #expect(event.reset)
    }
}

// MARK: - MIDIExpressionEvent Tests

@Suite("MIDIExpressionEvent Tests")
struct MIDIExpressionEventTests {

    @Test("channelPitchBend case stores cents")
    func channelPitchBend() {
        let event = MIDIExpressionEvent.channelPitchBend(cents: 50.0, channel: 1, timestamp: nil)
        if case .channelPitchBend(let cents, let ch, _) = event {
            #expect(cents == 50.0)
            #expect(ch == 1)
        } else {
            Issue.record("Expected channelPitchBend case")
        }
    }

    @Test("perNotePitchBend case stores note number")
    func perNotePitchBend() {
        let event = MIDIExpressionEvent.perNotePitchBend(
            cents: -30.0, noteNumber: 64, channel: 0, timestamp: nil
        )
        if case .perNotePitchBend(let cents, let note, _, _) = event {
            #expect(cents == -30.0)
            #expect(note == 64)
        } else {
            Issue.record("Expected perNotePitchBend case")
        }
    }

    @Test("Factory from MIDIPitchBendEvent produces channel bend")
    func factoryChannelBend() {
        let pitchBend = MIDIPitchBendEvent(value: 0, channel: 2, resolution: .midi2)
        let expr = MIDIExpressionEvent.from(pitchBend)
        if case .channelPitchBend(let cents, let ch, _) = expr {
            #expect(cents == 0.0)
            #expect(ch == 2)
        } else {
            Issue.record("Expected channelPitchBend from factory")
        }
    }

    @Test("Factory from MIDIPitchBendEvent produces per-note bend")
    func factoryPerNoteBend() {
        let pitchBend = MIDIPitchBendEvent(
            value: Int32.max, noteNumber: 60, channel: 0, resolution: .midi2
        )
        let expr = MIDIExpressionEvent.from(pitchBend)
        if case .perNotePitchBend(_, let note, _, _) = expr {
            #expect(note == 60)
        } else {
            Issue.record("Expected perNotePitchBend from factory")
        }
    }

    @Test("Factory from MIDIPressureEvent produces poly aftertouch")
    func factoryPolyAftertouch() {
        let pressure = MIDIPressureEvent(noteNumber: 64, pressure: UInt32.max)
        let expr = MIDIExpressionEvent.from(pressure)
        if case .polyAftertouch(let p, let note, _, _) = expr {
            #expect(p > 0.99)
            #expect(note == 64)
        } else {
            Issue.record("Expected polyAftertouch from factory")
        }
    }

    @Test("Factory from MIDIPressureEvent produces channel aftertouch")
    func factoryChannelAftertouch() {
        let pressure = MIDIPressureEvent(pressure: 0)
        let expr = MIDIExpressionEvent.from(pressure)
        if case .channelAftertouch(let p, _, _) = expr {
            #expect(p == 0.0)
        } else {
            Issue.record("Expected channelAftertouch from factory")
        }
    }

    @Test("micPitchDeviation case stores cents and confidence")
    func micDeviation() {
        let event = MIDIExpressionEvent.micPitchDeviation(cents: -12.5, confidence: 0.85)
        if case .micPitchDeviation(let cents, let conf) = event {
            #expect(cents == -12.5)
            #expect(conf == 0.85)
        } else {
            Issue.record("Expected micPitchDeviation case")
        }
    }
}
