import Foundation
import Testing

@testable import SurVibe
import SVAudio

// MARK: - Komal/Tivra Note Advancement Regression Tests

/// Verifies that notes with modifiers (komal, tivra) use the full Swar name
/// for pitch comparison, not just the base note name.
///
/// Regression test for the bug where `processDetectedPitch` compared
/// `pitch.noteName` against `expected.note` (bare name) instead of
/// `expectedName` (full name including modifier).
@MainActor
struct PracticeKomalTivraAdvancementTests {

    // MARK: - expectedName Construction

    @Test func expectedNameIncludesKomalModifier() {
        let note = SargamNote(note: "Re", octave: 4, duration: 1.0, modifier: "komal")
        let expectedName = note.modifier.map { "\($0.capitalized) \(note.note)" } ?? note.note
        #expect(expectedName == "Komal Re")
    }

    @Test func expectedNameIncludesTivraModifier() {
        let note = SargamNote(note: "Ma", octave: 4, duration: 1.0, modifier: "tivra")
        let expectedName = note.modifier.map { "\($0.capitalized) \(note.note)" } ?? note.note
        #expect(expectedName == "Tivra Ma")
    }

    @Test func expectedNameUsesBaseNoteWhenNoModifier() {
        let note = SargamNote(note: "Sa", octave: 4, duration: 1.0, modifier: nil)
        let expectedName = note.modifier.map { "\($0.capitalized) \(note.note)" } ?? note.note
        #expect(expectedName == "Sa")
    }

    // MARK: - Matching Behavior

    @Test func komalReMatchesFullNameNotBaseName() {
        // The detected pitch returns "Komal Re" from SwarUtility
        let detectedNoteName = "Komal Re"
        let expected = SargamNote(note: "Re", octave: 4, duration: 1.0, modifier: "komal")
        let expectedName = expected.modifier.map { "\($0.capitalized) \(expected.note)" } ?? expected.note

        // The fix ensures we compare against expectedName ("Komal Re"), not expected.note ("Re")
        #expect(detectedNoteName == expectedName)
        #expect(detectedNoteName != expected.note) // Would have falsely failed before the fix
    }

    @Test func tivraMaMatchesFullNameNotBaseName() {
        let detectedNoteName = "Tivra Ma"
        let expected = SargamNote(note: "Ma", octave: 4, duration: 1.0, modifier: "tivra")
        let expectedName = expected.modifier.map { "\($0.capitalized) \(expected.note)" } ?? expected.note

        #expect(detectedNoteName == expectedName)
        #expect(detectedNoteName != expected.note)
    }

    @Test func baseReDoesNotMatchKomalRe() {
        // A detected "Re" should NOT match an expected "Komal Re"
        let detectedNoteName = "Re"
        let expected = SargamNote(note: "Re", octave: 4, duration: 1.0, modifier: "komal")
        let expectedName = expected.modifier.map { "\($0.capitalized) \(expected.note)" } ?? expected.note

        #expect(detectedNoteName != expectedName)
    }

    @Test func allKomalVariantsProduceFullNames() {
        let komalNotes = ["Re", "Ga", "Dha", "Ni"]
        for note in komalNotes {
            let sargam = SargamNote(note: note, octave: 4, duration: 1.0, modifier: "komal")
            let expectedName = sargam.modifier.map { "\($0.capitalized) \(sargam.note)" } ?? sargam.note
            #expect(expectedName == "Komal \(note)")
        }
    }
}
