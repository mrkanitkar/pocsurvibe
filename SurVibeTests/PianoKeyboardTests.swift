import SVAudio
import Testing

@testable import SurVibe

@MainActor
struct PianoKeyboardTests {
    @Test func totalKeyCount() {
        #expect(allPianoKeys.count == 61)
    }

    @Test func midiNoteRange() {
        let firstKey = allPianoKeys.first
        let lastKey = allPianoKeys.last
        #expect(firstKey?.id == 36, "First key should be C2 (MIDI 36)")
        #expect(lastKey?.id == 96, "Last key should be C7 (MIDI 96)")
    }

    @Test func whiteKeyCount() {
        let naturals = allPianoKeys.filter(\.isNatural)
        #expect(naturals.count == 36, "61-key piano has 36 white keys")
    }

    @Test func blackKeyCount() {
        let accidentals = allPianoKeys.filter { !$0.isNatural }
        #expect(accidentals.count == 25, "61-key piano has 25 black keys")
    }

    @Test func c4IsMidi60() {
        let c4 = allPianoKeys.first(where: { $0.id == 60 })
        #expect(c4 != nil)
        #expect(c4?.westernName == "C")
        #expect(c4?.octave == 4)
        #expect(c4?.swar == .sa)
        #expect(c4?.isNatural == true)
        #expect(c4?.devanagari == "सा")
    }

    @Test func c5IsMidi72() {
        let c5 = allPianoKeys.first(where: { $0.id == 72 })
        #expect(c5 != nil)
        #expect(c5?.westernName == "C")
        #expect(c5?.octave == 5)
        #expect(c5?.swar == .sa)
    }

    @Test func c4AndC5AreDifferentKeys() {
        let c4 = allPianoKeys.first(where: { $0.id == 60 })
        let c5 = allPianoKeys.first(where: { $0.id == 72 })
        #expect(c4?.id != c5?.id, "C4 and C5 must be distinct keys")
        #expect(c4?.octave == 4)
        #expect(c5?.octave == 5)
    }

    @Test func a4IsMidi69() {
        let a4 = allPianoKeys.first(where: { $0.id == 69 })
        #expect(a4?.westernName == "A")
        #expect(a4?.octave == 4)
        #expect(a4?.swar == .dha)
        #expect(a4?.devanagari == "ध")
    }

    @Test func c2IsLowestKey() {
        let c2 = allPianoKeys.first(where: { $0.id == 36 })
        #expect(c2?.westernName == "C")
        #expect(c2?.octave == 2)
        #expect(c2?.isNatural == true)
    }

    @Test func c7IsHighestKey() {
        let c7 = allPianoKeys.first(where: { $0.id == 96 })
        #expect(c7?.westernName == "C")
        #expect(c7?.octave == 7)
        #expect(c7?.isNatural == true)
    }

    @Test func eachOctaveHasCorrectStructure() {
        // Check octave 4 (MIDI 60-71) as representative
        let octave4 = allPianoKeys.filter { $0.octave == 4 }
        #expect(octave4.count == 12, "Full octave has 12 keys")

        let naturals = octave4.filter(\.isNatural)
        let accidentals = octave4.filter { !$0.isNatural }
        #expect(naturals.count == 7, "7 natural keys per octave")
        #expect(accidentals.count == 5, "5 accidental keys per octave")
    }

    @Test func allMidiNotesAreUnique() {
        let ids = allPianoKeys.map(\.id)
        let uniqueIds = Set(ids)
        #expect(ids.count == uniqueIds.count, "All MIDI note IDs must be unique")
    }

    @Test func devanagariMappingsConsistent() {
        // Verify all C keys (Sa) across octaves have the same devanagari
        let saKeys = allPianoKeys.filter { $0.swar == .sa }
        for key in saKeys {
            #expect(key.devanagari == "सा", "Sa should be सा in all octaves")
        }
    }

    // MARK: - Multi-Note Highlighting Tests

    @Test func cMajorChordMidiNotes() {
        // C Major chord: C4(60) + E4(64) + G4(67)
        let chordNotes: Set<Int> = [60, 64, 67]
        #expect(chordNotes.count == 3)
        for midiNote in chordNotes {
            let key = allPianoKeys.first(where: { $0.id == midiNote })
            #expect(key != nil, "MIDI \(midiNote) should exist in keyboard")
        }
    }

    @Test func emptyMidiNotesHighlightsNothing() {
        let notes: Set<Int> = []
        #expect(notes.isEmpty)
        // No key should be highlighted when set is empty
        for key in allPianoKeys {
            #expect(!notes.contains(key.id))
        }
    }

    @Test func singleMidiNoteHighlightsOneKey() {
        let notes: Set<Int> = [60]
        #expect(notes.count == 1)
        let highlighted = allPianoKeys.filter { notes.contains($0.id) }
        #expect(highlighted.count == 1)
        #expect(highlighted.first?.westernName == "C")
    }

    @Test func chordNotesSpanCorrectPitchClasses() {
        // A minor chord: A3(57) + C4(60) + E4(64)
        let chordNotes: Set<Int> = [57, 60, 64]
        let keys = allPianoKeys.filter { chordNotes.contains($0.id) }
        let swarNames = Set(keys.map(\.swar))
        #expect(swarNames.contains(.dha))  // A = Dha
        #expect(swarNames.contains(.sa))   // C = Sa
        #expect(swarNames.contains(.ga))   // E = Ga
    }

    @Test func outOfRangeMidiNotesNotInKeyboard() {
        // MIDI 35 is below C2, MIDI 97 is above C7
        let outOfRange: Set<Int> = [35, 97]
        for midiNote in outOfRange {
            let key = allPianoKeys.first(where: { $0.id == midiNote })
            #expect(key == nil, "MIDI \(midiNote) should not exist in 61-key keyboard")
        }
    }
}
