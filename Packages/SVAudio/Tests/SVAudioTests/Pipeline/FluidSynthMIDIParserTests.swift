import CoreMIDI
import Foundation
import Testing

@testable import SVAudio

@Suite("FluidSynthMIDIParser")
struct FluidSynthMIDIParserTests {

    @Test("Note-on (3 bytes) becomes one RealtimeMIDIEvent posted to ring")
    func parseNoteOn() {
        let ring = FluidSynthMIDIEventRing(capacity: 8)
        let parser = FluidSynthMIDIParser(ring: ring)
        // 0x90 0x3C 0x64 = note-on ch 0, note 60, vel 100
        parser.parseRawBytes([0x90, 0x3C, 0x64], timestamp: 100)
        let event = ring.dequeue()
        #expect(event?.status == 0x90)
        #expect(event?.channel == 0)
        #expect(event?.data1 == 60)
        #expect(event?.data2 == 100)
        #expect(event?.timestamp == 100)
    }

    @Test("Program-change (2 bytes) parses with data2=0")
    func parseProgramChange() {
        let ring = FluidSynthMIDIEventRing(capacity: 8)
        let parser = FluidSynthMIDIParser(ring: ring)
        // 0xC1 0x21 = program change ch 1, program 33
        parser.parseRawBytes([0xC1, 0x21], timestamp: 50)
        let event = ring.dequeue()
        #expect(event?.status == 0xC1)
        #expect(event?.channel == 1)
        #expect(event?.data1 == 33)
        #expect(event?.data2 == 0)
    }

    @Test("Multiple events in one packet are all posted")
    func parseMultipleEvents() {
        let ring = FluidSynthMIDIEventRing(capacity: 8)
        let parser = FluidSynthMIDIParser(ring: ring)
        parser.parseRawBytes([
            0x90, 0x3C, 0x64,   // note-on ch0
            0x80, 0x3C, 0x40,   // note-off ch0
            0x91, 0x40, 0x50,   // note-on ch1
        ], timestamp: 0)
        var count = 0
        while ring.dequeue() != nil { count += 1 }
        #expect(count == 3)
    }

    @Test("Sysex (0xF0 ... 0xF7) is skipped")
    func skipSysex() {
        let ring = FluidSynthMIDIEventRing(capacity: 8)
        let parser = FluidSynthMIDIParser(ring: ring)
        parser.parseRawBytes([
            0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7,  // GM-on sysex
            0x90, 0x3C, 0x64,                     // note-on after
        ], timestamp: 0)
        // Only the note-on should be posted
        let evt = ring.dequeue()
        #expect(evt?.status == 0x90)
        #expect(ring.dequeue() == nil)
    }
}
