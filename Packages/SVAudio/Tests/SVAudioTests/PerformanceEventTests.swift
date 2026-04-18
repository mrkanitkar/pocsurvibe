import Testing
@testable import SVAudio

struct PerformanceEventTests {

    @Test func midiEventCarriesNoteAndVelocity() {
        let event = PerformanceEvent.midi(
            noteNumber: 60,
            velocity: 100,
            channel: 0,
            probeToken: nil
        )
        #expect(event.noteNumber == 60)
        #expect(event.velocity == 100)
        #expect(event.isMIDI)
        #expect(!event.isMic)
    }

    @Test func micEventCarriesFrequencyAndNote() {
        let event = PerformanceEvent.mic(
            frequency: 261.63,
            noteName: "Sa",
            centsOffset: -5.0,
            confidence: 0.95,
            amplitude: 0.3,
            probeToken: nil
        )
        #expect(event.noteNumber == nil)
        #expect(!event.isMIDI)
        #expect(event.isMic)
    }

    @Test func midiEventFromMIDIInputEvent() {
        let inputEvent = MIDIInputEvent(
            noteNumber: 64,
            velocity: 80,
            channel: 1
        )
        let event = PerformanceEvent.from(inputEvent)
        #expect(event.noteNumber == 64)
        #expect(event.velocity == 80)
        #expect(event.isMIDI)
    }

    @Test func micEventFromPitchResult() {
        let pitchResult = PitchResult(
            frequency: 440.0,
            amplitude: 0.5,
            noteName: "Dha",
            octave: 4,
            centsOffset: 2.0,
            confidence: 0.9
        )
        let event = PerformanceEvent.from(pitchResult)
        #expect(event.isMic)
        #expect(!event.isMIDI)
    }

    @Test func probeTokenPassedThrough() {
        var token = ProbeToken()
        token.stamp(.inputReceived)

        let event = PerformanceEvent.midi(
            noteNumber: 60,
            velocity: 100,
            channel: 0,
            probeToken: token
        )
        #expect(event.probeToken != nil)
        #expect(event.probeToken?.t0 != .zero)
    }

    @Test func velocity16BitPassedThrough() {
        let event = PerformanceEvent.midi(
            noteNumber: 60,
            velocity: 100,
            channel: 0,
            probeToken: nil,
            velocity16Bit: 32768
        )
        #expect(event.velocity16Bit == 32768)
    }

    @Test func midiTimestampPassedThrough() {
        let event = PerformanceEvent.midi(
            noteNumber: 60,
            velocity: 100,
            channel: 0,
            probeToken: nil,
            velocity16Bit: 0,
            midiTimestamp: 12345
        )
        #expect(event.midiTimestamp == 12345)
    }

    @Test func factoryFromMIDIInputEventPreservesVelocity16Bit() {
        let inputEvent = MIDIInputEvent(
            noteNumber: 64,
            velocity: 100,
            channel: 1,
            velocity16Bit: 51200
        )
        let event = PerformanceEvent.from(inputEvent)
        #expect(event.velocity16Bit == 51200)
    }

    @Test func pitchBendCaseProperties() {
        let bendEvent = MIDIPitchBendEvent(value: 1000, channel: 2)
        let event = PerformanceEvent.pitchBend(event: bendEvent)
        #expect(event.isPitchBend)
        #expect(!event.isMIDI)
        #expect(!event.isMic)
        #expect(event.noteNumber == nil)
        #expect(event.velocity == nil)
        #expect(event.probeToken == nil)
    }

    @Test func pressureCaseProperties() {
        let pressureEvent = MIDIPressureEvent(noteNumber: 60, pressure: 5000)
        let event = PerformanceEvent.pressure(event: pressureEvent)
        #expect(event.isPressure)
        #expect(!event.isMIDI)
    }

    @Test func programChangeCaseProperties() {
        let pgmEvent = MIDIProgramChangeEvent(program: 42)
        let event = PerformanceEvent.programChange(event: pgmEvent)
        #expect(event.isProgramChange)
        #expect(!event.isMIDI)
    }

    @Test func defaultVelocity16BitIsZero() {
        let event = PerformanceEvent.midi(
            noteNumber: 60, velocity: 100, channel: 0, probeToken: nil
        )
        #expect(event.velocity16Bit == 0)
    }
}
