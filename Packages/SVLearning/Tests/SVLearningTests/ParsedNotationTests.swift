import Foundation
import Testing

@testable import SVLearning

@Suite("ParsedNotation Tests")
struct ParsedNotationTests {

    // MARK: - ragaName

    @Test("ragaName defaults to nil")
    func ragaNameDefaultsToNil() {
        let notation = ParsedNotation(
            format: .sargam,
            notes: []
        )
        #expect(notation.ragaName == nil)
    }

    @Test("ragaName stores raga when provided")
    func ragaNameStoresValue() {
        let notation = ParsedNotation(
            format: .sargam,
            notes: [],
            ragaName: "Yaman"
        )
        #expect(notation.ragaName == "Yaman")
    }

    @Test("ragaName is mutable")
    func ragaNameIsMutable() {
        var notation = ParsedNotation(
            format: .sargam,
            notes: []
        )
        notation.ragaName = "Bhairav"
        #expect(notation.ragaName == "Bhairav")
    }

    // MARK: - Note.velocity

    @Test("Note velocity defaults to nil")
    func noteVelocityDefaultsToNil() {
        let note = ParsedNotation.Note(name: "Sa", index: 0)
        #expect(note.velocity == nil)
    }

    @Test("Note velocity stores value when provided")
    func noteVelocityStoresValue() {
        let note = ParsedNotation.Note(
            name: "Re", octave: 4, durationBeats: 1.0,
            modifier: nil, index: 1, velocity: 80
        )
        #expect(note.velocity == 80)
    }

    @Test("Note velocity accepts full MIDI range")
    func noteVelocityFullRange() {
        let soft = ParsedNotation.Note(name: "Ga", index: 0, velocity: 0)
        let loud = ParsedNotation.Note(name: "Ma", index: 1, velocity: 127)
        #expect(soft.velocity == 0)
        #expect(loud.velocity == 127)
    }

    // MARK: - Backward Compatibility

    @Test("Existing init without ragaName still works")
    func existingInitWorksWithoutRagaName() {
        let notation = ParsedNotation(
            format: .western,
            notes: [ParsedNotation.Note(name: "C4", index: 0)],
            tempo: 140,
            keySignature: "G major",
            timeSignature: "3/4"
        )
        #expect(notation.ragaName == nil)
        #expect(notation.tempo == 140)
        #expect(notation.notes.count == 1)
    }

    @Test("Existing Note init without velocity still works")
    func existingNoteInitWorksWithoutVelocity() {
        let note = ParsedNotation.Note(
            name: "Sa", octave: 4, durationBeats: 2.0,
            modifier: "tivra", index: 3
        )
        #expect(note.velocity == nil)
        #expect(note.modifier == "tivra")
    }
}
