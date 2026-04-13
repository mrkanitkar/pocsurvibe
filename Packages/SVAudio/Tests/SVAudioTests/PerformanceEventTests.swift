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
}
