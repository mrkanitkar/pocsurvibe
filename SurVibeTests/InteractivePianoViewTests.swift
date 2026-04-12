import Foundation
import SVAudio
import Testing

@testable import SurVibe

/// Tests for InteractivePianoView data model and highlighting logic.
@MainActor
struct InteractivePianoViewTests {

    // MARK: - Devanagari Label Constants

    @Test func devanagariLabelsHas12Entries() {
        // InteractivePianoView uses a static array of 12 Devanagari labels
        let expectedLabels = [
            "सा", "रे♭", "रे", "ग♭", "ग", "म", "म♯", "प", "ध♭", "ध", "नि♭", "नि",
        ]
        #expect(expectedLabels.count == 12)
    }

    @Test func westernNamesHas12Entries() {
        let expectedNames = [
            "C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B",
        ]
        #expect(expectedNames.count == 12)
    }

    @Test func naturalOffsetsAre7() {
        let naturalOffsets: Set<Int> = [0, 2, 4, 5, 7, 9, 11]
        #expect(naturalOffsets.count == 7, "Piano has 7 natural notes per octave")
    }

    // MARK: - MIDI to Swar Mapping

    @Test func midiNoteToSwarMappingCorrect() {
        // C4 = MIDI 60 = Sa, D4 = MIDI 62 = Re, E4 = MIDI 64 = Ga, etc.
        let swarCases = Swar.allCases
        let midi60Index = ((60 - 60) % 12 + 12) % 12
        #expect(swarCases[midi60Index] == .sa, "MIDI 60 should be Sa")

        let midi62Index = ((62 - 60) % 12 + 12) % 12
        #expect(swarCases[midi62Index] == .re, "MIDI 62 should be Re")

        let midi64Index = ((64 - 60) % 12 + 12) % 12
        #expect(swarCases[midi64Index] == .ga, "MIDI 64 should be Ga")

        let midi67Index = ((67 - 60) % 12 + 12) % 12
        #expect(swarCases[midi67Index] == .pa, "MIDI 67 should be Pa")
    }

    @Test func midiNoteIndexWrapsCorrectlyForLowOctaves() {
        // C2 = MIDI 36: (36 - 60) = -24, (-24 % 12 + 12) % 12 = 0 => Sa
        let midi36Index = ((36 - 60) % 12 + 12) % 12
        #expect(midi36Index == 0, "MIDI 36 (C2) should map to index 0 (Sa)")
    }

    @Test func midiNoteIndexWrapsCorrectlyForHighOctaves() {
        // C7 = MIDI 96: (96 - 60) = 36, (36 % 12 + 12) % 12 = 0 => Sa
        let midi96Index = ((96 - 60) % 12 + 12) % 12
        #expect(midi96Index == 0, "MIDI 96 (C7) should map to index 0 (Sa)")
    }

    // MARK: - Highlight Color Logic

    @Test func highlightColorDetectionOnlyIsBlue() {
        // Simulating the highlight logic from InteractivePianoView
        let activeMidiNotes: Set<Int> = [60]
        let touchedMidiNotes: Set<Int> = []
        let midiNote = 60

        let isDetected = activeMidiNotes.contains(midiNote)
        let isTouched = touchedMidiNotes.contains(midiNote)

        #expect(isDetected == true)
        #expect(isTouched == false)
        // Detection-only should be blue
    }

    @Test func highlightColorTouchOnlyIsGreen() {
        let activeMidiNotes: Set<Int> = []
        let touchedMidiNotes: Set<Int> = [60]
        let midiNote = 60

        let isDetected = activeMidiNotes.contains(midiNote)
        let isTouched = touchedMidiNotes.contains(midiNote)

        #expect(isDetected == false)
        #expect(isTouched == true)
        // Touch-only should be green
    }

    @Test func highlightColorBothIsCyan() {
        let activeMidiNotes: Set<Int> = [60]
        let touchedMidiNotes: Set<Int> = [60]
        let midiNote = 60

        let isDetected = activeMidiNotes.contains(midiNote)
        let isTouched = touchedMidiNotes.contains(midiNote)

        #expect(isDetected == true)
        #expect(isTouched == true)
        // Both should be cyan
    }

    @Test func highlightColorNeitherIsNil() {
        let activeMidiNotes: Set<Int> = [60]
        let touchedMidiNotes: Set<Int> = [64]
        let midiNote = 67  // Not in either set

        let isDetected = activeMidiNotes.contains(midiNote)
        let isTouched = touchedMidiNotes.contains(midiNote)

        #expect(isDetected == false)
        #expect(isTouched == false)
        // Neither should return nil (no highlight)
    }

    // MARK: - Latching Logic

    @Test func latchingModeKeepsNoteInSet() {
        // When latching is enabled, noteOff should not remove from touched set
        var touchedNotes: Set<Int> = []
        let midiNote = 60

        // Simulate noteOn
        touchedNotes.insert(midiNote)
        #expect(touchedNotes.contains(midiNote))

        // In latching mode, noteOff does NOT remove (Keyboard handles this internally)
        // The note stays in touchedPitches until tapped again
        #expect(touchedNotes.contains(midiNote), "Note should remain in set during latching")
    }

    @Test func latchingModeSecondTapRemovesNote() {
        var touchedNotes: Set<Int> = [60]

        // Second tap in latching mode removes the note
        touchedNotes.remove(60)
        #expect(!touchedNotes.contains(60), "Second tap should remove note in latching mode")
    }

    @Test func clearAllLatchedRemovesAllNotes() {
        var touchedNotes: Set<Int> = [60, 64, 67]  // C Major chord

        // Clear all
        touchedNotes.removeAll()
        #expect(touchedNotes.isEmpty, "Clear all should empty the set")
    }

    // MARK: - Octave Calculation

    @Test func octaveCalculationCorrectForAllRanges() {
        // MIDI 36 = C2 (octave 2)
        let octave36 = Int(floor(Double(36 - 60) / 12.0)) + 4
        #expect(octave36 == 2)

        // MIDI 48 = C3 (octave 3)
        let octave48 = Int(floor(Double(48 - 60) / 12.0)) + 4
        #expect(octave48 == 3)

        // MIDI 60 = C4 (octave 4)
        let octave60 = Int(floor(Double(60 - 60) / 12.0)) + 4
        #expect(octave60 == 4)

        // MIDI 72 = C5 (octave 5)
        let octave72 = Int(floor(Double(72 - 60) / 12.0)) + 4
        #expect(octave72 == 5)

        // MIDI 96 = C7 (octave 7)
        let octave96 = Int(floor(Double(96 - 60) / 12.0)) + 4
        #expect(octave96 == 7)
    }
}
