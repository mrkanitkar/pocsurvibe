import Foundation
import Testing
@testable import SVCore

struct MIDISerializerTests {
    @Test func headerAndTempoMeta() {
        let data = MIDISerializer.serializeType0(notes: [], sustain: [], program: 0)
        // MThd <len=6> <fmt=0> <ntracks=1> <division=1000>
        #expect(Array(data.prefix(4)) == [0x4D, 0x54, 0x68, 0x64])     // "MThd"
        #expect(Array(data[4..<8]) == [0x00, 0x00, 0x00, 0x06])         // header chunk len
        #expect(Array(data[8..<10]) == [0x00, 0x00])                    // format 0
        #expect(Array(data[10..<12]) == [0x00, 0x01])                   // 1 track
        #expect(Array(data[12..<14]) == [0x03, 0xE8])                   // division = 1000
    }

    @Test func tempoMetaIs60BPM() {
        let data = MIDISerializer.serializeType0(notes: [], sustain: [], program: 0)
        // Find FF 51 03 0F 42 40 — the 60 BPM tempo meta event.
        let needle: [UInt8] = [0xFF, 0x51, 0x03, 0x0F, 0x42, 0x40]
        #expect(data.range(of: Data(needle)) != nil)
    }

    @Test func programChangeAtTimeZero() {
        let data = MIDISerializer.serializeType0(notes: [], sustain: [], program: 105)
        // Program-change for program 105 on channel 0: C0 69 (0xC0 = program change ch 0, 0x69 = 105)
        let needle: [UInt8] = [0x00, 0xC0, 0x69]                        // delta-time 0 + status + program
        #expect(data.range(of: Data(needle)) != nil)
    }

    @Test func roundTripSingleNote() throws {
        let notes = [RecordedNote(midi: 60, velocity: 100, onTimeSec: 0, offTimeSec: 1.0)]
        let bytes = MIDISerializer.serializeType0(notes: notes, sustain: [], program: 0)
        // We don't ship a full SMF parser; assert structural invariants.
        // 1) Note-On 0x90 0x3C 0x64 must appear.
        let noteOn: [UInt8] = [0x90, 0x3C, 0x64]
        #expect(bytes.range(of: Data(noteOn)) != nil)
        // 2) Note-Off (running-status note-on with vel 0, OR explicit 0x80).
        let noteOff90: [UInt8] = [0x90, 0x3C, 0x00]
        let noteOff80: [UInt8] = [0x80, 0x3C, 0x40]
        #expect(bytes.range(of: Data(noteOff90)) != nil || bytes.range(of: Data(noteOff80)) != nil)
    }

    @Test func sustainCC64InOutput() {
        let sus = [
            RecordedSustainEvent(timeSec: 0.5, down: true, channel: 0),
            RecordedSustainEvent(timeSec: 1.0, down: false, channel: 0),
        ]
        let bytes = MIDISerializer.serializeType0(notes: [], sustain: sus, program: 0)
        // CC: B0 40 7F (down) and B0 40 00 (up)
        #expect(bytes.range(of: Data([0xB0, 0x40, 0x7F])) != nil)
        #expect(bytes.range(of: Data([0xB0, 0x40, 0x00])) != nil)
    }

    @Test func goldenSaReGaMaFixtureMatches() throws {
        let beat = 0.75
        let pitches: [UInt8] = [0, 2, 4, 5]
        let notes = (0..<4).map { i in
            RecordedNote(
                midi: UInt8(60) + pitches[i],
                velocity: 100,
                onTimeSec: Double(i) * beat,
                offTimeSec: Double(i + 1) * beat
            )
        }
        let actual = MIDISerializer.serializeType0(notes: notes, sustain: [], program: 0)
        let url = Bundle.module.url(forResource: "sa-re-ga-ma", withExtension: "mid",
                                    subdirectory: "Play")!
        let expected = try Data(contentsOf: url)
        #expect(actual == expected)
    }
}
