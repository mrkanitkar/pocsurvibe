import Testing

@testable import SVAudio

@Suite("MIDI2MessageBuilder")
struct MIDI2MessageBuilderTests {

    // MARK: - Note Messages (MIDI 2.0 — 2 words)

    @Test("noteOn returns two UMP words")
    func noteOnWordCount() {
        let words = MIDI2MessageBuilder.noteOn(note: 60, velocity: 100, channel: 0)
        #expect(words.count == 2)
        #expect(words[0] != 0, "word0 must encode message type and status")
    }

    @Test("noteOff returns two UMP words")
    func noteOffWordCount() {
        let words = MIDI2MessageBuilder.noteOff(note: 60, velocity: 0, channel: 0)
        #expect(words.count == 2)
        #expect(words[0] != 0)
    }

    @Test("noteOn with different channels produces different word0")
    func noteOnChannelEncoding() {
        let ch0 = MIDI2MessageBuilder.noteOn(note: 60, velocity: 100, channel: 0)
        let ch1 = MIDI2MessageBuilder.noteOn(note: 60, velocity: 100, channel: 1)
        #expect(ch0[0] != ch1[0], "Different channels must produce different word0")
    }

    @Test("noteOn with different notes produces different words")
    func noteOnNoteEncoding() {
        let c4 = MIDI2MessageBuilder.noteOn(note: 60, velocity: 100, channel: 0)
        let d4 = MIDI2MessageBuilder.noteOn(note: 62, velocity: 100, channel: 0)
        #expect(c4 != d4, "Different notes must produce different UMP words")
    }

    @Test("noteOn with different groups produces different word0")
    func noteOnGroupEncoding() {
        let g0 = MIDI2MessageBuilder.noteOn(note: 60, velocity: 100, channel: 0, group: 0)
        let g1 = MIDI2MessageBuilder.noteOn(note: 60, velocity: 100, channel: 0, group: 1)
        #expect(g0[0] != g1[0], "Different groups must produce different word0")
    }

    // MARK: - Polyphonic Messages (MIDI 2.0 — 2 words)

    @Test("polyPressure returns two UMP words")
    func polyPressureWordCount() {
        let words = MIDI2MessageBuilder.polyPressure(note: 60, pressure: 1000, channel: 0)
        #expect(words.count == 2)
        #expect(words[0] != 0)
    }

    @Test("registeredPerNoteController returns two UMP words")
    func registeredPNCWordCount() {
        let words = MIDI2MessageBuilder.registeredPerNoteController(
            note: 60, index: 7, value: 5000, channel: 0
        )
        #expect(words.count == 2)
        #expect(words[0] != 0)
    }

    @Test("assignablePerNoteController returns two UMP words")
    func assignablePNCWordCount() {
        let words = MIDI2MessageBuilder.assignablePerNoteController(
            note: 60, index: 3, value: 2000, channel: 0
        )
        #expect(words.count == 2)
        #expect(words[0] != 0)
    }

    @Test("perNoteManagement returns two UMP words")
    func perNoteManagementWordCount() {
        let words = MIDI2MessageBuilder.perNoteManagement(
            note: 60, detach: true, reset: false, channel: 0
        )
        #expect(words.count == 2)
        #expect(words[0] != 0)
    }

    // MARK: - Channel Voice Messages (MIDI 2.0 — 2 words)

    @Test("controlChange2 returns two UMP words")
    func controlChange2WordCount() {
        let words = MIDI2MessageBuilder.controlChange2(
            controller: 7, value: 0x7FFF_FFFF, channel: 0
        )
        #expect(words.count == 2)
        #expect(words[0] != 0)
    }

    @Test("registeredController returns two UMP words")
    func registeredControllerWordCount() {
        let words = MIDI2MessageBuilder.registeredController(
            bank: 0, index: 0, value: 1000, channel: 0
        )
        #expect(words.count == 2)
        #expect(words[0] != 0)
    }

    @Test("assignableController returns two UMP words")
    func assignableControllerWordCount() {
        let words = MIDI2MessageBuilder.assignableController(
            bank: 0, index: 0, value: 1000, channel: 0
        )
        #expect(words.count == 2)
        #expect(words[0] != 0)
    }

    @Test("relativeRegisteredController returns two UMP words")
    func relativeRegisteredControllerWordCount() {
        let words = MIDI2MessageBuilder.relativeRegisteredController(
            bank: 0, index: 0, value: 500, channel: 0
        )
        #expect(words.count == 2)
        #expect(words[0] != 0)
    }

    @Test("relativeAssignableController returns two UMP words")
    func relativeAssignableControllerWordCount() {
        let words = MIDI2MessageBuilder.relativeAssignableController(
            bank: 0, index: 0, value: 500, channel: 0
        )
        #expect(words.count == 2)
        #expect(words[0] != 0)
    }

    @Test("programChange (MIDI 2.0) returns two UMP words")
    func programChange2WordCount() {
        let words = MIDI2MessageBuilder.programChange(
            program: 0, bankMSB: 0, bankLSB: 0, channel: 0
        )
        #expect(words.count == 2)
        #expect(words[0] != 0)
    }

    @Test("programChange auto-detects bank validity")
    func programChangeBankDetection() {
        // Sentinel bank values (0x7F, 0x7F) → bankIsValid = false. Explicit
        // 0x7F is required to disambiguate from the MIDI 1.0 UP overload,
        // which has no bankMSB/bankLSB parameters and returns 1 word.
        let noBank = MIDI2MessageBuilder.programChange(
            program: 5, bankMSB: 0x7F, bankLSB: 0x7F, channel: 0
        )
        // Explicit bank values → bankIsValid = true
        let withBank = MIDI2MessageBuilder.programChange(
            program: 5, bankMSB: 0, bankLSB: 1, channel: 0
        )
        // word1 encodes bank select info — different when bank is valid vs not
        #expect(noBank[1] != withBank[1], "Bank validity must affect word1 encoding")
    }

    @Test("channelPressure returns two UMP words")
    func channelPressureWordCount() {
        let words = MIDI2MessageBuilder.channelPressure(pressure: 50000, channel: 0)
        #expect(words.count == 2)
        #expect(words[0] != 0)
    }

    @Test("pitchBend returns two UMP words")
    func pitchBendWordCount() {
        let words = MIDI2MessageBuilder.pitchBend(value: 0x8000_0000, channel: 0)
        #expect(words.count == 2)
        #expect(words[0] != 0)
    }

    // MARK: - MIDI 1.0 UP (Compatibility — 1 word)

    @Test("controlChange (MIDI 1.0 UP) returns one word")
    func controlChange1WordCount() {
        let words = MIDI2MessageBuilder.controlChange(
            controller: 64, value: 127, channel: 0
        )
        #expect(words.count == 1)
        #expect(words[0] != 0)
    }

    @Test("programChange (MIDI 1.0 UP) returns one word")
    func programChange1WordCount() {
        let words = MIDI2MessageBuilder.programChange(program: 42, channel: 0)
        #expect(words.count == 1)
        #expect(words[0] != 0)
    }

    // MARK: - Edge Cases

    @Test("boundary MIDI note values produce valid words")
    func boundaryNoteValues() {
        let low = MIDI2MessageBuilder.noteOn(note: 0, velocity: 1, channel: 0)
        let high = MIDI2MessageBuilder.noteOn(note: 127, velocity: 127, channel: 15)
        #expect(low.count == 2)
        #expect(high.count == 2)
        #expect(low != high)
    }

    @Test("zero velocity noteOn produces valid words")
    func zeroVelocityNoteOn() {
        let words = MIDI2MessageBuilder.noteOn(note: 60, velocity: 0, channel: 0)
        #expect(words.count == 2)
    }
}
