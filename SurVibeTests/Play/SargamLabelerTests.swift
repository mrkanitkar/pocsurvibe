import Testing

@testable import SurVibe

struct SargamLabelerTests {
    // MARK: - Identity (Sa = C, played C → "Sa")

    @Test
    func saAtMiddleCMatchesItself() {
        let label = SargamLabeler.label(midi: 60, saPitch: 60)
        #expect(label.syllable == "Sa")
        #expect(label.octave == .middle)
    }

    // MARK: - Twelve chromatic syllables, Sa = C

    @Test(arguments: [
        (UInt8(60), "Sa"),
        (UInt8(61), "Re♭"),  // komal Re
        (UInt8(62), "Re"),
        (UInt8(63), "Ga♭"),  // komal Ga
        (UInt8(64), "Ga"),
        (UInt8(65), "Ma"),
        (UInt8(66), "Ma♯"),  // tivra Ma
        (UInt8(67), "Pa"),
        (UInt8(68), "Dha♭"),  // komal Dha
        (UInt8(69), "Dha"),
        (UInt8(70), "Ni♭"),  // komal Ni
        (UInt8(71), "Ni"),
    ])
    func twelveChromaticAtSaIsC(midi: UInt8, expected: String) {
        let label = SargamLabeler.label(midi: midi, saPitch: 60)
        #expect(label.syllable == expected)
        #expect(label.octave == .middle)
    }

    // MARK: - Movable Sa

    @Test
    func movableSaAtDPlayingDIsSa() {
        let label = SargamLabeler.label(midi: 62, saPitch: 62)
        #expect(label.syllable == "Sa")
        #expect(label.octave == .middle)
    }

    @Test
    func movableSaAtDPlayingEIsRe() {
        let label = SargamLabeler.label(midi: 64, saPitch: 62)
        #expect(label.syllable == "Re")
        #expect(label.octave == .middle)
    }

    // MARK: - Octave indicators

    @Test
    func upperOctaveSa() {
        let label = SargamLabeler.label(midi: 72, saPitch: 60)  // C5 with Sa = C4
        #expect(label.syllable == "Sa")
        #expect(label.octave == .upper)
    }

    @Test
    func lowerOctaveSa() {
        let label = SargamLabeler.label(midi: 48, saPitch: 60)  // C3 with Sa = C4
        #expect(label.syllable == "Sa")
        #expect(label.octave == .lower)
    }

    @Test
    func twoOctavesUp() {
        let label = SargamLabeler.label(midi: 84, saPitch: 60)  // C6 with Sa = C4
        #expect(label.octave == .doubleUpper)
    }

    @Test
    func twoOctavesDown() {
        let label = SargamLabeler.label(midi: 36, saPitch: 60)  // C2 with Sa = C4
        #expect(label.octave == .doubleLower)
    }

    // MARK: - Display string formatting

    @Test
    func displayUpperOctaveAddsDot() {
        let label = SargamLabeler.label(midi: 72, saPitch: 60)
        #expect(label.display == "Sa•")  // upper-octave dot suffix
    }

    @Test
    func displayLowerOctaveAddsDot() {
        let label = SargamLabeler.label(midi: 48, saPitch: 60)
        #expect(label.display == "•Sa")  // lower-octave dot prefix
    }

    @Test
    func displayMiddleOctaveNoDot() {
        let label = SargamLabeler.label(midi: 60, saPitch: 60)
        #expect(label.display == "Sa")
    }

    // MARK: - VoiceOver-friendly description

    @Test
    func voiceOverDescribesKomal() {
        let label = SargamLabeler.label(midi: 61, saPitch: 60)
        #expect(label.voiceOverDescription == "Re komal")
    }

    @Test
    func voiceOverDescribesTivra() {
        let label = SargamLabeler.label(midi: 66, saPitch: 60)
        #expect(label.voiceOverDescription == "Ma tivra")
    }
}
