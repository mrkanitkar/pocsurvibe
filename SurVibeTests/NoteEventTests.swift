import Foundation
import Testing

@testable import SurVibe
import SVAudio

// MARK: - NoteEvent fromNotation Tests

@MainActor
struct NoteEventFromNotationTests {

    // MARK: - Basic Conversion

    @Test func convertsSimpleSargamNotes() {
        let sargam = [
            SargamNote(note: "Sa", octave: 4, duration: 1.0),
            SargamNote(note: "Re", octave: 4, duration: 1.0),
        ]
        let western = [
            WesternNote(note: "C4", duration: 1.0, midiNumber: 60),
            WesternNote(note: "D4", duration: 1.0, midiNumber: 62),
        ]
        let events = NoteEvent.fromNotation(sargamNotes: sargam, westernNotes: western, tempo: 120)

        #expect(events.count == 2)
        #expect(events[0].swarName == "Sa")
        #expect(events[0].midiNote == 60)
        #expect(events[1].swarName == "Re")
        #expect(events[1].midiNote == 62)
    }

    @Test func timestampsAreCumulative() {
        let sargam = [
            SargamNote(note: "Sa", octave: 4, duration: 1.0),
            SargamNote(note: "Re", octave: 4, duration: 2.0),
            SargamNote(note: "Ga", octave: 4, duration: 1.0),
        ]
        let western = [
            WesternNote(note: "C4", duration: 1.0, midiNumber: 60),
            WesternNote(note: "D4", duration: 2.0, midiNumber: 62),
            WesternNote(note: "E4", duration: 1.0, midiNumber: 64),
        ]
        // At 120 BPM: beatsPerSecond = 2.0
        // durations: 0.5s, 1.0s, 0.5s
        // timestamps: 0.0, 0.5, 1.5
        let events = NoteEvent.fromNotation(sargamNotes: sargam, westernNotes: western, tempo: 120)

        #expect(events[0].timestamp == 0.0)
        #expect(abs(events[1].timestamp - 0.5) < 0.001)
        #expect(abs(events[2].timestamp - 1.5) < 0.001)
    }

    @Test func durationsConvertedFromBeatsToSeconds() {
        let sargam = [SargamNote(note: "Sa", octave: 4, duration: 2.0)]
        let western = [WesternNote(note: "C4", duration: 2.0, midiNumber: 60)]
        // At 60 BPM: beatsPerSecond = 1.0, so 2.0 beats = 2.0 seconds
        let events = NoteEvent.fromNotation(sargamNotes: sargam, westernNotes: western, tempo: 60)

        #expect(abs(events[0].duration - 2.0) < 0.001)
    }

    @Test func tempoAffectsDuration() {
        let sargam = [SargamNote(note: "Sa", octave: 4, duration: 1.0)]
        let western = [WesternNote(note: "C4", duration: 1.0, midiNumber: 60)]

        let at60 = NoteEvent.fromNotation(sargamNotes: sargam, westernNotes: western, tempo: 60)
        let at120 = NoteEvent.fromNotation(sargamNotes: sargam, westernNotes: western, tempo: 120)

        // At 60 BPM: 1 beat = 1.0s, at 120 BPM: 1 beat = 0.5s
        #expect(abs(at60[0].duration - 1.0) < 0.001)
        #expect(abs(at120[0].duration - 0.5) < 0.001)
    }

    // MARK: - Modifier Handling (Komal/Tivra)

    @Test func komalReProducesFullSwarName() {
        let sargam = [SargamNote(note: "Re", octave: 4, duration: 1.0, modifier: "komal")]
        let western = [WesternNote(note: "Db4", duration: 1.0, midiNumber: 61)]
        let events = NoteEvent.fromNotation(sargamNotes: sargam, westernNotes: western, tempo: 120)

        #expect(events[0].swarName == "Komal Re")
    }

    @Test func komalGaProducesFullSwarName() {
        let sargam = [SargamNote(note: "Ga", octave: 4, duration: 1.0, modifier: "komal")]
        let western = [WesternNote(note: "Eb4", duration: 1.0, midiNumber: 63)]
        let events = NoteEvent.fromNotation(sargamNotes: sargam, westernNotes: western, tempo: 120)

        #expect(events[0].swarName == "Komal Ga")
    }

    @Test func komalDhaProducesFullSwarName() {
        let sargam = [SargamNote(note: "Dha", octave: 4, duration: 1.0, modifier: "komal")]
        let western = [WesternNote(note: "Ab4", duration: 1.0, midiNumber: 68)]
        let events = NoteEvent.fromNotation(sargamNotes: sargam, westernNotes: western, tempo: 120)

        #expect(events[0].swarName == "Komal Dha")
    }

    @Test func komalNiProducesFullSwarName() {
        let sargam = [SargamNote(note: "Ni", octave: 4, duration: 1.0, modifier: "komal")]
        let western = [WesternNote(note: "Bb4", duration: 1.0, midiNumber: 70)]
        let events = NoteEvent.fromNotation(sargamNotes: sargam, westernNotes: western, tempo: 120)

        #expect(events[0].swarName == "Komal Ni")
    }

    @Test func tivraMaProducesFullSwarName() {
        let sargam = [SargamNote(note: "Ma", octave: 4, duration: 1.0, modifier: "tivra")]
        let western = [WesternNote(note: "F#4", duration: 1.0, midiNumber: 66)]
        let events = NoteEvent.fromNotation(sargamNotes: sargam, westernNotes: western, tempo: 120)

        #expect(events[0].swarName == "Tivra Ma")
    }

    @Test func nilModifierUsesBaseNote() {
        let sargam = [SargamNote(note: "Pa", octave: 4, duration: 1.0, modifier: nil)]
        let western = [WesternNote(note: "G4", duration: 1.0, midiNumber: 67)]
        let events = NoteEvent.fromNotation(sargamNotes: sargam, westernNotes: western, tempo: 120)

        #expect(events[0].swarName == "Pa")
    }

    @Test func emptyModifierUsesBaseNote() {
        let sargam = [SargamNote(note: "Dha", octave: 4, duration: 1.0, modifier: "")]
        let western = [WesternNote(note: "A4", duration: 1.0, midiNumber: 69)]
        let events = NoteEvent.fromNotation(sargamNotes: sargam, westernNotes: western, tempo: 120)

        #expect(events[0].swarName == "Dha")
    }

    // MARK: - Edge Cases

    @Test func mismatchedArrayCountsReturnsEmpty() {
        let sargam = [SargamNote(note: "Sa", octave: 4, duration: 1.0)]
        let western: [WesternNote] = []
        let events = NoteEvent.fromNotation(sargamNotes: sargam, westernNotes: western, tempo: 120)

        #expect(events.isEmpty)
    }

    @Test func emptyArraysReturnsEmpty() {
        let events = NoteEvent.fromNotation(sargamNotes: [], westernNotes: [], tempo: 120)
        #expect(events.isEmpty)
    }

    @Test func westernNameIsPreserved() {
        let sargam = [SargamNote(note: "Sa", octave: 4, duration: 1.0)]
        let western = [WesternNote(note: "C4", duration: 1.0, midiNumber: 60)]
        let events = NoteEvent.fromNotation(sargamNotes: sargam, westernNotes: western, tempo: 120)

        #expect(events[0].westernName == "C4")
    }

    @Test func octaveIsPreserved() {
        let sargam = [SargamNote(note: "Sa", octave: 5, duration: 1.0)]
        let western = [WesternNote(note: "C5", duration: 1.0, midiNumber: 72)]
        let events = NoteEvent.fromNotation(sargamNotes: sargam, westernNotes: western, tempo: 120)

        #expect(events[0].octave == 5)
    }

    @Test func velocityDefaultsTo100() {
        let sargam = [SargamNote(note: "Sa", octave: 4, duration: 1.0)]
        let western = [WesternNote(note: "C4", duration: 1.0, midiNumber: 60)]
        let events = NoteEvent.fromNotation(sargamNotes: sargam, westernNotes: western, tempo: 120)

        #expect(events[0].velocity == 100)
    }
}

// MARK: - NoteEvent fromMIDI Tests

@MainActor
struct NoteEventFromMIDITests {

    @Test func convertsMIDIEventsPreservingTimestamps() {
        let events = NoteEvent.fromMIDI(events: MIDIFixtures.cMajorScale)

        #expect(events.count == 4)
        #expect(events[0].timestamp == 0.0)
        #expect(events[1].timestamp == 0.5)
        #expect(events[2].timestamp == 1.0)
        #expect(events[3].timestamp == 1.5)
    }

    @Test func derivesSwarNamesFromMIDI() {
        let events = NoteEvent.fromMIDI(events: MIDIFixtures.cMajorScale)

        #expect(events[0].swarName == "Sa")       // MIDI 60 = C4 = Sa
        #expect(events[1].swarName == "Re")        // MIDI 62 = D4 = Re
        #expect(events[2].swarName == "Ga")        // MIDI 64 = E4 = Ga
        #expect(events[3].swarName == "Ma")        // MIDI 65 = F4 = Ma
    }

    @Test func derivesKomalTivraSwarNames() {
        let events = NoteEvent.fromMIDI(events: MIDIFixtures.komalTivraSequence)

        #expect(events[0].swarName == "Sa")        // MIDI 60
        #expect(events[1].swarName == "Komal Re")  // MIDI 61
        #expect(events[2].swarName == "Tivra Ma")  // MIDI 66
        #expect(events[3].swarName == "Pa")         // MIDI 67
    }

    @Test func preservesMIDINoteNumbers() {
        let events = NoteEvent.fromMIDI(events: MIDIFixtures.cMajorScale)

        #expect(events[0].midiNote == 60)
        #expect(events[1].midiNote == 62)
        #expect(events[2].midiNote == 64)
        #expect(events[3].midiNote == 65)
    }

    @Test func preservesVelocity() {
        let midi = [MIDIEvent(noteNumber: 60, velocity: 80, timestamp: 0, duration: 1.0)]
        let events = NoteEvent.fromMIDI(events: midi)

        #expect(events[0].velocity == 80)
    }

    @Test func preservesDuration() {
        let events = NoteEvent.fromMIDI(events: MIDIFixtures.singleNote)

        #expect(events[0].duration == 1.0)
    }

    @Test func emptyMIDIReturnsEmpty() {
        let events = NoteEvent.fromMIDI(events: [])
        #expect(events.isEmpty)
    }

    @Test func derivesOctaveFromMIDI() {
        let midi = [
            MIDIEvent(noteNumber: 48, velocity: 100, timestamp: 0, duration: 0.5),  // C3
            MIDIEvent(noteNumber: 60, velocity: 100, timestamp: 0.5, duration: 0.5), // C4
            MIDIEvent(noteNumber: 72, velocity: 100, timestamp: 1.0, duration: 0.5), // C5
        ]
        let events = NoteEvent.fromMIDI(events: midi)

        #expect(events[0].octave == 3)
        #expect(events[1].octave == 4)
        #expect(events[2].octave == 5)
    }
}

// MARK: - fullSwarName Helper Tests

@MainActor
struct FullSwarNameTests {

    @Test func noModifierReturnsBaseNote() {
        #expect(NoteEvent.fullSwarName(note: "Sa", modifier: nil) == "Sa")
    }

    @Test func emptyModifierReturnsBaseNote() {
        #expect(NoteEvent.fullSwarName(note: "Re", modifier: "") == "Re")
    }

    @Test func komalModifierCapitalized() {
        #expect(NoteEvent.fullSwarName(note: "Re", modifier: "komal") == "Komal Re")
    }

    @Test func tivraModifierCapitalized() {
        #expect(NoteEvent.fullSwarName(note: "Ma", modifier: "tivra") == "Tivra Ma")
    }

    @Test func allKomalVariants() {
        #expect(NoteEvent.fullSwarName(note: "Re", modifier: "komal") == "Komal Re")
        #expect(NoteEvent.fullSwarName(note: "Ga", modifier: "komal") == "Komal Ga")
        #expect(NoteEvent.fullSwarName(note: "Dha", modifier: "komal") == "Komal Dha")
        #expect(NoteEvent.fullSwarName(note: "Ni", modifier: "komal") == "Komal Ni")
    }
}
