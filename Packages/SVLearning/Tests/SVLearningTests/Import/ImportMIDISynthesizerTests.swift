import Foundation
import Testing
@testable import SVLearning

struct ImportMIDISynthesizerTests {

    let synthesizer = ImportMIDISynthesizer()

    func makeNote(
        name: String, octave: Int = 4, duration: Double = 1.0,
        modifier: String? = nil, index: Int = 0
    ) -> ParsedNotation.Note {
        ParsedNotation.Note(
            name: name, octave: octave, durationBeats: duration,
            modifier: modifier, index: index
        )
    }

    @Test func returnsNilForEmptyNotation() async throws {
        let notation = ParsedNotation(format: .sargam, notes: [])
        let result = try await synthesizer.synthesise(from: notation, tempo: 120)
        #expect(result == nil)
    }

    @Test func returnsMIDIDataForSingleNote() async throws {
        let notes = [makeNote(name: "Sa")]
        let notation = ParsedNotation(format: .sargam, notes: notes)
        let result = try await synthesizer.synthesise(from: notation, tempo: 120)
        #expect(result != nil)
        #expect((result?.count ?? 0) > 14) // At least header + track header
    }

    @Test func midiFileStartsWithMThdHeader() async throws {
        let notes = [makeNote(name: "C", octave: 4)]
        let notation = ParsedNotation(format: .western, notes: notes)
        let data = try await synthesizer.synthesise(from: notation, tempo: 120)
        let bytes = data.map { Array($0) } ?? []
        // "MThd" = 0x4D 0x54 0x68 0x64
        #expect(bytes.count > 4)
        #expect(bytes[0] == 0x4D)
        #expect(bytes[1] == 0x54)
        #expect(bytes[2] == 0x68)
        #expect(bytes[3] == 0x64)
    }

    @Test func midiFileContainsMTrkChunk() async throws {
        let notes = [makeNote(name: "Sa")]
        let notation = ParsedNotation(format: .sargam, notes: notes)
        let data = try await synthesizer.synthesise(from: notation, tempo: 120)
        let bytes = data.map { Array($0) } ?? []
        // "MTrk" starts at byte 14: 0x4D 0x54 0x72 0x6B
        #expect(bytes.count > 17)
        #expect(bytes[14] == 0x4D)
        #expect(bytes[15] == 0x54)
        #expect(bytes[16] == 0x72)
        #expect(bytes[17] == 0x6B)
    }

    @Test func producesLargerFileForMoreNotes() async throws {
        let singleNote = [makeNote(name: "Sa")]
        let multiNote = (0..<7).map { makeNote(name: "Sa", index: $0) }

        let single = try await synthesizer.synthesise(
            from: ParsedNotation(format: .sargam, notes: singleNote), tempo: 120
        )
        let multi = try await synthesizer.synthesise(
            from: ParsedNotation(format: .sargam, notes: multiNote), tempo: 120
        )

        #expect((single?.count ?? 0) < (multi?.count ?? 0))
    }

    @Test func sargamSaMapsToCMidi60() async throws {
        // Sa at octave 4 = C4 = MIDI 60
        // Verify the MIDI note-on byte appears in the file
        let notes = [makeNote(name: "Sa", octave: 4)]
        let notation = ParsedNotation(format: .sargam, notes: notes)
        let data = try await synthesizer.synthesise(from: notation, tempo: 120)
        let bytes = data.map { Array($0) } ?? []
        // Find 0x90 (note-on channel 0) followed by 60 (C4)
        let hasC4 = zip(bytes, bytes.dropFirst()).contains { $0.0 == 0x90 && $0.1 == 60 }
        #expect(hasC4)
    }

    @Test func westernCMapsToCMidi() async throws {
        let notes = [makeNote(name: "C", octave: 4)]
        let notation = ParsedNotation(format: .western, notes: notes)
        let data = try await synthesizer.synthesise(from: notation, tempo: 120)
        let bytes = data.map { Array($0) } ?? []
        let hasC4 = zip(bytes, bytes.dropFirst()).contains { $0.0 == 0x90 && $0.1 == 60 }
        #expect(hasC4)
    }
}
