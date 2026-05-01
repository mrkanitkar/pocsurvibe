import Testing

@testable import SVAudio

// MARK: - MusicTime Tests

struct MusicTimeTests {

    // MARK: - beatsToSeconds

    @Test("beatsToSeconds returns correct value at 120 BPM")
    func beatsToSecondsAt120BPM() {
        // 4 beats at 120 BPM = 2 seconds
        #expect(MusicTime.beatsToSeconds(beats: 4.0, bpm: 120.0) == 2.0)
    }

    @Test("beatsToSeconds returns correct value at 60 BPM")
    func beatsToSecondsAt60BPM() {
        // 1 beat at 60 BPM = 1 second
        #expect(MusicTime.beatsToSeconds(beats: 1.0, bpm: 60.0) == 1.0)
    }

    @Test("beatsToSeconds returns correct value at 90 BPM")
    func beatsToSecondsAt90BPM() {
        // 3 beats at 90 BPM = 2 seconds exactly
        #expect(MusicTime.beatsToSeconds(beats: 3.0, bpm: 90.0) == 2.0)
    }

    @Test("beatsToSeconds with zero beats returns zero")
    func beatsToSecondsZeroBeats() {
        #expect(MusicTime.beatsToSeconds(beats: 0.0, bpm: 120.0) == 0.0)
    }

    @Test("beatsToSeconds with non-positive BPM clamps to 1")
    func beatsToSecondsInvalidBPMClamped() {
        // Zero BPM should not divide by zero — clamps to 1 BPM
        let result = MusicTime.beatsToSeconds(beats: 1.0, bpm: 0.0)
        #expect(result.isFinite)
        #expect(result == 60.0)  // 1 beat at 1 BPM = 60 seconds
    }

    // MARK: - secondsToBeats

    @Test("secondsToBeats returns correct value at 120 BPM")
    func secondsToBeatsAt120BPM() {
        // 2 seconds at 120 BPM = 4 beats
        #expect(MusicTime.secondsToBeats(seconds: 2.0, bpm: 120.0) == 4.0)
    }

    @Test("secondsToBeats returns correct value at 60 BPM")
    func secondsToBeatsAt60BPM() {
        // 1 second at 60 BPM = 1 beat
        #expect(MusicTime.secondsToBeats(seconds: 1.0, bpm: 60.0) == 1.0)
    }

    @Test("secondsToBeats round-trips with beatsToSeconds")
    func secondsToBeatsRoundTrip() {
        let bpm = 137.5
        let originalBeats = 7.25
        let seconds = MusicTime.beatsToSeconds(beats: originalBeats, bpm: bpm)
        let recovered = MusicTime.secondsToBeats(seconds: seconds, bpm: bpm)
        #expect(abs(recovered - originalBeats) < 1e-10)
    }

    @Test("secondsToBeats with zero seconds returns zero")
    func secondsToBeatsZeroSeconds() {
        #expect(MusicTime.secondsToBeats(seconds: 0.0, bpm: 120.0) == 0.0)
    }

    @Test("secondsToBeats with non-positive BPM clamps to 1")
    func secondsToBeatsInvalidBPMClamped() {
        // Negative BPM should clamp to 1 BPM
        let result = MusicTime.secondsToBeats(seconds: 60.0, bpm: -10.0)
        #expect(result.isFinite)
        #expect(result == 1.0)  // 60 seconds at 1 BPM = 1 beat
    }
}

// MARK: - Swar MIDI Name Tests

struct SwarMIDINameTests {

    @Test("sargamName for MIDI 60 is Sa (C4)")
    func sargamNameMIDI60isSa() {
        #expect(Swar.sargamName(forMIDI: 60) == "Sa")
    }

    @Test("sargamName for MIDI 62 is Re (D4)")
    func sargamNameMIDI62isRe() {
        #expect(Swar.sargamName(forMIDI: 62) == "Re")
    }

    @Test("sargamName for MIDI 61 is Komal Re (Db4)")
    func sargamNameMIDI61isKomalRe() {
        #expect(Swar.sargamName(forMIDI: 61) == "Komal Re")
    }

    @Test("sargamName for MIDI 66 is Tivra Ma (F#4)")
    func sargamNameMIDI66isTivraMa() {
        #expect(Swar.sargamName(forMIDI: 66) == "Tivra Ma")
    }

    @Test("sargamName wraps correctly across octaves")
    func sargamNameWrapsAcrossOctaves() {
        // MIDI 72 = C5 = Sa (same semitone as MIDI 60)
        #expect(Swar.sargamName(forMIDI: 72) == "Sa")
        // MIDI 48 = C3 = Sa
        #expect(Swar.sargamName(forMIDI: 48) == "Sa")
    }

    @Test("westernName for MIDI 60 is C4")
    func westernNameMIDI60isC4() {
        #expect(Swar.westernName(forMIDI: 60) == "C4")
    }

    @Test("westernName for MIDI 69 is A4")
    func westernNameMIDI69isA4() {
        #expect(Swar.westernName(forMIDI: 69) == "A4")
    }

    @Test("westernName for MIDI 63 is Eb4")
    func westernNameMIDI63isEb4() {
        #expect(Swar.westernName(forMIDI: 63) == "Eb4")
    }

    @Test("westernName for MIDI 72 is C5")
    func westernNameMIDI72isC5() {
        #expect(Swar.westernName(forMIDI: 72) == "C5")
    }

    @Test("westernName for MIDI 45 is A3")
    func westernNameMIDI45isA3() {
        #expect(Swar.westernName(forMIDI: 45) == "A3")
    }

    @Test("westernName for MIDI 0 is C-1")
    func westernNameMIDI0isC_1() {
        #expect(Swar.westernName(forMIDI: 0) == "C-1")
    }
}
