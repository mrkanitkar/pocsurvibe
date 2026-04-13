import Testing

@testable import SVAudio

// MARK: - SustainPedalState Tests

@Suite("Sustain Pedal State Tests")
struct SustainPedalStateTests {

    // MARK: - Initial State

    @Test("Initial state has pedal up on all channels")
    func initialStateAllChannelsUp() {
        let sustain = SustainPedalState()
        for ch: UInt8 in 0..<16 {
            #expect(!sustain.isActive(channel: ch))
        }
    }

    @Test("Initial state has no held notes on any channel")
    func initialStateNoHeldNotes() {
        let sustain = SustainPedalState()
        for ch: UInt8 in 0..<16 {
            #expect(sustain.heldNotes(channel: ch).isEmpty)
        }
    }

    // MARK: - Pedal Down/Up State Transitions

    @Test("Pedal down sets channel active")
    func pedalDownSetsActive() {
        let sustain = SustainPedalState()
        sustain.pedalDown(channel: 0)
        #expect(sustain.isActive(channel: 0))
    }

    @Test("Pedal up clears channel active")
    func pedalUpClearsActive() {
        let sustain = SustainPedalState()
        sustain.pedalDown(channel: 0)
        sustain.pedalUp(channel: 0)
        #expect(!sustain.isActive(channel: 0))
    }

    @Test("Multiple pedal-down calls without up do not accumulate state")
    func doublePedalDown() {
        let sustain = SustainPedalState()
        sustain.pedalDown(channel: 0)
        sustain.pedalDown(channel: 0)
        #expect(sustain.isActive(channel: 0))
        // Should still be cleanly active — single pedal up clears it.
        let released = sustain.pedalUp(channel: 0)
        #expect(!sustain.isActive(channel: 0))
        #expect(released.isEmpty)
    }

    @Test("Pedal up when already up is a no-op")
    func pedalUpWhenAlreadyUp() {
        let sustain = SustainPedalState()
        let released = sustain.pedalUp(channel: 0)
        #expect(released.isEmpty)
        #expect(!sustain.isActive(channel: 0))
    }

    // MARK: - Per-Channel Isolation

    @Test("Channel 0 sustain does not affect channel 1")
    func perChannelIsolation() {
        let sustain = SustainPedalState()
        sustain.pedalDown(channel: 0)
        #expect(sustain.isActive(channel: 0))
        #expect(!sustain.isActive(channel: 1))
    }

    @Test("Held notes on channel 0 not visible on channel 1")
    func heldNotesPerChannelIsolation() {
        let sustain = SustainPedalState()
        sustain.pedalDown(channel: 0)
        sustain.holdNote(note: 60, channel: 0)
        #expect(sustain.isNoteHeld(note: 60, channel: 0))
        #expect(!sustain.isNoteHeld(note: 60, channel: 1))
    }

    @Test("Pedal up on channel 0 does not release channel 1 held notes")
    func pedalUpPerChannelIsolation() {
        let sustain = SustainPedalState()
        sustain.pedalDown(channel: 0)
        sustain.pedalDown(channel: 1)
        sustain.holdNote(note: 60, channel: 0)
        sustain.holdNote(note: 64, channel: 1)

        let released0 = sustain.pedalUp(channel: 0)
        #expect(released0 == [60])
        // Channel 1 should still hold note 64.
        #expect(sustain.isNoteHeld(note: 64, channel: 1))
    }

    // MARK: - Hold Note During Sustain

    @Test("Hold note returns true when pedal is down")
    func holdNoteWhenPedalDown() {
        let sustain = SustainPedalState()
        sustain.pedalDown(channel: 0)
        let captured = sustain.holdNote(note: 60, channel: 0)
        #expect(captured)
        #expect(sustain.isNoteHeld(note: 60, channel: 0))
    }

    @Test("Hold note returns false when pedal is up")
    func holdNoteWhenPedalUp() {
        let sustain = SustainPedalState()
        let captured = sustain.holdNote(note: 60, channel: 0)
        #expect(!captured)
        #expect(!sustain.isNoteHeld(note: 60, channel: 0))
    }

    @Test("Multiple notes can be held simultaneously")
    func multipleHeldNotes() {
        let sustain = SustainPedalState()
        sustain.pedalDown(channel: 0)
        sustain.holdNote(note: 60, channel: 0)
        sustain.holdNote(note: 64, channel: 0)
        sustain.holdNote(note: 67, channel: 0)

        #expect(sustain.heldNotes(channel: 0) == [60, 64, 67])
    }

    @Test("Holding same note twice does not duplicate")
    func holdSameNoteTwice() {
        let sustain = SustainPedalState()
        sustain.pedalDown(channel: 0)
        sustain.holdNote(note: 60, channel: 0)
        sustain.holdNote(note: 60, channel: 0)

        #expect(sustain.heldNotes(channel: 0).count == 1)
    }

    // MARK: - Pedal Up Releases Held Notes

    @Test("Pedal up returns all held notes")
    func pedalUpReturnsHeldNotes() {
        let sustain = SustainPedalState()
        sustain.pedalDown(channel: 0)
        sustain.holdNote(note: 60, channel: 0)
        sustain.holdNote(note: 64, channel: 0)
        sustain.holdNote(note: 67, channel: 0)

        let released = sustain.pedalUp(channel: 0)
        #expect(released == [60, 64, 67])
    }

    @Test("Pedal up clears held notes set")
    func pedalUpClearsHeldNotes() {
        let sustain = SustainPedalState()
        sustain.pedalDown(channel: 0)
        sustain.holdNote(note: 60, channel: 0)
        sustain.pedalUp(channel: 0)

        #expect(sustain.heldNotes(channel: 0).isEmpty)
    }

    @Test("Pedal up with no held notes returns empty set")
    func pedalUpNoHeldNotes() {
        let sustain = SustainPedalState()
        sustain.pedalDown(channel: 0)
        let released = sustain.pedalUp(channel: 0)
        #expect(released.isEmpty)
    }

    // MARK: - Reset

    @Test("Reset clears all channels")
    func resetClearsAllChannels() {
        let sustain = SustainPedalState()
        sustain.pedalDown(channel: 0)
        sustain.pedalDown(channel: 5)
        sustain.holdNote(note: 60, channel: 0)
        sustain.holdNote(note: 72, channel: 5)

        sustain.reset()

        for ch: UInt8 in 0..<16 {
            #expect(!sustain.isActive(channel: ch))
            #expect(sustain.heldNotes(channel: ch).isEmpty)
        }
    }

    // MARK: - Channel Masking

    @Test("Channel values above 15 are masked to 0-15 range")
    func channelMasking() {
        let sustain = SustainPedalState()
        // Channel 16 should be masked to 0 (16 & 0x0F = 0)
        sustain.pedalDown(channel: 16)
        #expect(sustain.isActive(channel: 0))
    }

    // MARK: - Edge Cases

    @Test("Hold note at boundary values 0 and 127")
    func holdNoteBoundaryValues() {
        let sustain = SustainPedalState()
        sustain.pedalDown(channel: 0)
        sustain.holdNote(note: 0, channel: 0)
        sustain.holdNote(note: 127, channel: 0)
        #expect(sustain.isNoteHeld(note: 0, channel: 0))
        #expect(sustain.isNoteHeld(note: 127, channel: 0))

        let released = sustain.pedalUp(channel: 0)
        #expect(released.contains(0))
        #expect(released.contains(127))
    }

    @Test("Full cycle: pedal down, hold notes, pedal up, pedal down again")
    func fullCycle() {
        let sustain = SustainPedalState()

        // First sustain cycle
        sustain.pedalDown(channel: 0)
        sustain.holdNote(note: 60, channel: 0)
        let released1 = sustain.pedalUp(channel: 0)
        #expect(released1 == [60])

        // Second sustain cycle — should start clean
        sustain.pedalDown(channel: 0)
        #expect(sustain.heldNotes(channel: 0).isEmpty)
        sustain.holdNote(note: 64, channel: 0)
        let released2 = sustain.pedalUp(channel: 0)
        #expect(released2 == [64])
    }
}

// MARK: - MIDIControlChangeEvent Tests

@Suite("MIDI Control Change Event Tests")
struct MIDIControlChangeEventTests {

    @Test("Default values are correct")
    func defaultValues() {
        let event = MIDIControlChangeEvent(controller: 64, value: 127)
        #expect(event.controller == 64)
        #expect(event.value == 127)
        #expect(event.channel == 0)
        #expect(event.midiTimestamp == nil)
    }

    @Test("Custom channel is preserved")
    func customChannel() {
        let event = MIDIControlChangeEvent(controller: 64, value: 127, channel: 5)
        #expect(event.channel == 5)
    }

    @Test("isSustainPedal returns true for CC64")
    func isSustainPedalCC64() {
        let event = MIDIControlChangeEvent(controller: 64, value: 127)
        #expect(event.isSustainPedal)
    }

    @Test("isSustainPedal returns false for other controllers")
    func isSustainPedalOtherCC() {
        let event = MIDIControlChangeEvent(controller: 1, value: 127)
        #expect(!event.isSustainPedal)
    }

    @Test("isSustainDown true when value >= 64")
    func sustainDownThreshold() {
        let downAt64 = MIDIControlChangeEvent(controller: 64, value: 64)
        #expect(downAt64.isSustainDown)

        let downAt127 = MIDIControlChangeEvent(controller: 64, value: 127)
        #expect(downAt127.isSustainDown)
    }

    @Test("isSustainDown false when value < 64")
    func sustainUpThreshold() {
        let upAt63 = MIDIControlChangeEvent(controller: 64, value: 63)
        #expect(!upAt63.isSustainDown)

        let upAt0 = MIDIControlChangeEvent(controller: 64, value: 0)
        #expect(!upAt0.isSustainDown)
    }

    @Test("isSustainDown false for non-CC64 even with high value")
    func sustainDownNonCC64() {
        let event = MIDIControlChangeEvent(controller: 1, value: 127)
        #expect(!event.isSustainDown)
    }

    @Test("Equality for identical events")
    func eventEquality() {
        let date = Date()
        let event1 = MIDIControlChangeEvent(
            controller: 64,
            value: 127,
            channel: 0,
            midiTimestamp: 12345,
            timestamp: date
        )
        let event2 = MIDIControlChangeEvent(
            controller: 64,
            value: 127,
            channel: 0,
            midiTimestamp: 12345,
            timestamp: date
        )
        #expect(event1 == event2)
    }

    @Test("Inequality for different values")
    func eventInequality() {
        let date = Date()
        let event1 = MIDIControlChangeEvent(
            controller: 64,
            value: 127,
            channel: 0,
            timestamp: date
        )
        let event2 = MIDIControlChangeEvent(
            controller: 64,
            value: 0,
            channel: 0,
            timestamp: date
        )
        #expect(event1 != event2)
    }

    @Test("Conforms to Sendable")
    func sendableConformance() {
        let event = MIDIControlChangeEvent(controller: 64, value: 127)
        let _: any Sendable = event
        #expect(true)
    }
}
