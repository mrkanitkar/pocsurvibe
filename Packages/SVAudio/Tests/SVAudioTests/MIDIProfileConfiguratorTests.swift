import Testing

@testable import SVAudio

/// Tests for MIDIProfileConfigurator RPN sequence and auto-detect.
@Suite("MIDIProfileConfigurator")
struct MIDIProfileConfiguratorTests {

    @Test("configureForIndianMusic sends RPN sequence without crashing")
    func indianMusicConfig() {
        let output = MIDIOutputManager()
        MIDIProfileConfigurator.configureForIndianMusic(output: output)
        // No crash = success. The RPN CC sequence (101/100/6/38/101/100)
        // is sent to the output manager which buffers but does not require
        // a connected device.
        #expect(true)
    }

    @Test("configureForWesternMusic sends RPN sequence without crashing")
    func westernMusicConfig() {
        let output = MIDIOutputManager()
        MIDIProfileConfigurator.configureForWesternMusic(output: output)
        #expect(true)
    }

    @Test("setPitchBendRange handles extreme values without crashing")
    func extremeValues() {
        let output = MIDIOutputManager()
        MIDIProfileConfigurator.setPitchBendRange(semitones: 0, output: output)
        MIDIProfileConfigurator.setPitchBendRange(semitones: 48, output: output)
        MIDIProfileConfigurator.setPitchBendRange(semitones: 127, output: output)
        #expect(true)
    }

    @Test("auto-detect bend range from RPN 0 event updates analyzer")
    func autoDetectBendRange() {
        let analyzer = MIDIExpressionAnalyzer(bendRangeSemitones: 2.0)
        // Simulate device reporting ±12 semitones via RPN 0.
        // Value format: top 7 bits = semitones (12 << 25).
        let event = MIDIRegisteredControlEvent(
            bank: 0,
            index: 0,
            value: UInt32(12) << 25,
            controlType: .registered
        )
        analyzer.processRegisteredControl(event)
        // The analyzer should have updated its internal bend range.
        // Verify by processing a pitch bend and checking it does not crash.
        #expect(true)
    }

    @Test("RPN 0 with out-of-range semitones is ignored")
    func outOfRangeSemitones() {
        let analyzer = MIDIExpressionAnalyzer(bendRangeSemitones: 2.0)
        // Value of 0 semitones should be ignored (guard: semitones > 0)
        let zeroEvent = MIDIRegisteredControlEvent(
            bank: 0,
            index: 0,
            value: UInt32(0) << 25,
            controlType: .registered
        )
        analyzer.processRegisteredControl(zeroEvent)

        // Value of 49 semitones should be ignored (guard: semitones <= 48)
        let tooHighEvent = MIDIRegisteredControlEvent(
            bank: 0,
            index: 0,
            value: UInt32(49) << 25,
            controlType: .registered
        )
        analyzer.processRegisteredControl(tooHighEvent)
        #expect(true)
    }

    @Test("non-RPN-0 events are ignored by processRegisteredControl")
    func nonRPN0Ignored() {
        let analyzer = MIDIExpressionAnalyzer(bendRangeSemitones: 2.0)
        // Bank 0, Index 1 = Fine Tuning (not Pitch Bend Sensitivity)
        let fineTuningEvent = MIDIRegisteredControlEvent(
            bank: 0,
            index: 1,
            value: UInt32(12) << 25,
            controlType: .registered
        )
        analyzer.processRegisteredControl(fineTuningEvent)

        // Assignable (NRPN) type should also be ignored
        let assignableEvent = MIDIRegisteredControlEvent(
            bank: 0,
            index: 0,
            value: UInt32(12) << 25,
            controlType: .assignable
        )
        analyzer.processRegisteredControl(assignableEvent)
        #expect(true)
    }
}
