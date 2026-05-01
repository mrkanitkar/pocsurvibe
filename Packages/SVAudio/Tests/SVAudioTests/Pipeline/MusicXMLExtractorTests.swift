import Foundation
import Testing

@testable import SVAudio

@Suite("MusicXMLExtractor")
struct MusicXMLExtractorTests {

    // MARK: - Score builders

    /// Minimal valid MusicXML with caller-controlled key, mode, and time sig.
    private static func minimalScore(
        fifths: Int,
        mode: String? = nil,
        beats: Int = 4,
        beatType: Int = 4,
        extraNoteXML: String = ""
    ) -> String {
        let modeXML = mode.map { "<mode>\($0)</mode>" } ?? ""
        return """
            <?xml version="1.0"?>
            <score-partwise version="3.1">
              <part-list>
                <score-part id="P1"><part-name>Piano</part-name></score-part>
              </part-list>
              <part id="P1">
                <measure number="1">
                  <attributes>
                    <divisions>1</divisions>
                    <key><fifths>\(fifths)</fifths>\(modeXML)</key>
                    <time><beats>\(beats)</beats><beat-type>\(beatType)</beat-type></time>
                    <clef><sign>G</sign><line>2</line></clef>
                  </attributes>
                  <note>
                    <pitch><step>C</step><octave>4</octave></pitch>
                    <duration>1</duration><type>quarter</type>
                  </note>
                  \(extraNoteXML)
                </measure>
              </part>
            </score-partwise>
            """
    }

    private static let trivialCMajor = minimalScore(fifths: 0)

    // MARK: - Key signature: major (15 entries)

    @Test("0 fifths + no mode → C major")
    func cMajorDefaultMode() throws {
        let meta = try MusicXMLExtractor.extract(musicXML: Self.trivialCMajor)
        #expect(meta.keySignatureRaw == "C major")
    }

    @Test("0 fifths + explicit major → C major")
    func cMajorExplicit() throws {
        let xml = Self.minimalScore(fifths: 0, mode: "major")
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        #expect(meta.keySignatureRaw == "C major")
    }

    @Test("1 fifth major → G major")
    func gMajor() throws {
        let meta = try MusicXMLExtractor.extract(musicXML: Self.minimalScore(fifths: 1))
        #expect(meta.keySignatureRaw == "G major")
    }

    @Test("3 fifths major → A major (Sukhkarta key)")
    func aMajor() throws {
        let meta = try MusicXMLExtractor.extract(musicXML: Self.minimalScore(fifths: 3))
        #expect(meta.keySignatureRaw == "A major")
    }

    @Test("-3 fifths major → Eb major")
    func ebMajor() throws {
        let meta = try MusicXMLExtractor.extract(musicXML: Self.minimalScore(fifths: -3))
        #expect(meta.keySignatureRaw == "Eb major")
    }

    @Test("-5 fifths major → Db major")
    func dbMajor() throws {
        let meta = try MusicXMLExtractor.extract(musicXML: Self.minimalScore(fifths: -5))
        #expect(meta.keySignatureRaw == "Db major")
    }

    @Test("-7 fifths major → Cb major")
    func cbMajor() throws {
        let meta = try MusicXMLExtractor.extract(musicXML: Self.minimalScore(fifths: -7))
        #expect(meta.keySignatureRaw == "Cb major")
    }

    @Test("+7 fifths major → C# major")
    func cSharpMajor() throws {
        let meta = try MusicXMLExtractor.extract(musicXML: Self.minimalScore(fifths: 7))
        #expect(meta.keySignatureRaw == "C# major")
    }

    @Test("Out-of-range fifths fall back to C major")
    func outOfRangeMajor() throws {
        let meta = try MusicXMLExtractor.extract(musicXML: Self.minimalScore(fifths: 12))
        #expect(meta.keySignatureRaw == "C major")
    }

    // MARK: - Key signature: minor

    @Test("0 fifths minor → A minor")
    func aMinor() throws {
        let xml = Self.minimalScore(fifths: 0, mode: "minor")
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        #expect(meta.keySignatureRaw == "A minor")
    }

    @Test("3 fifths minor → F# minor")
    func fSharpMinor() throws {
        let xml = Self.minimalScore(fifths: 3, mode: "minor")
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        #expect(meta.keySignatureRaw == "F# minor")
    }

    @Test("-3 fifths minor → C minor")
    func cMinor() throws {
        let xml = Self.minimalScore(fifths: -3, mode: "minor")
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        #expect(meta.keySignatureRaw == "C minor")
    }

    @Test("-5 fifths minor → Bb minor")
    func bbMinor() throws {
        let xml = Self.minimalScore(fifths: -5, mode: "minor")
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        #expect(meta.keySignatureRaw == "Bb minor")
    }

    @Test("Mode case-insensitive: 'MAJOR' parses as major")
    func modeCaseInsensitive() throws {
        let xml = Self.minimalScore(fifths: 0, mode: "MAJOR")
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        #expect(meta.keySignatureRaw == "C major")
    }

    // MARK: - Time signature

    @Test("4/4 from minimal score")
    func timeSig44() throws {
        let meta = try MusicXMLExtractor.extract(musicXML: Self.trivialCMajor)
        #expect(meta.timeSignatureRaw == "4/4")
    }

    @Test("6/8 time signature")
    func timeSig68() throws {
        let xml = Self.minimalScore(fifths: 0, beats: 6, beatType: 8)
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        #expect(meta.timeSignatureRaw == "6/8")
    }

    @Test("3/4 time signature")
    func timeSig34() throws {
        let xml = Self.minimalScore(fifths: 0, beats: 3, beatType: 4)
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        #expect(meta.timeSignatureRaw == "3/4")
    }

    @Test("12/8 time signature (compound)")
    func timeSig128() throws {
        let xml = Self.minimalScore(fifths: 0, beats: 12, beatType: 8)
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        #expect(meta.timeSignatureRaw == "12/8")
    }

    // MARK: - Sa frequency

    @Test("C major → Sa ≈ 261.6256 Hz (C4)")
    func saHzCMajor() throws {
        let meta = try MusicXMLExtractor.extract(musicXML: Self.trivialCMajor)
        #expect(abs(meta.defaultSaFrequencyHz - 261.625_565_300_598_6) < 0.001)
    }

    @Test("A major → Sa ≈ 440 Hz (A4)")
    func saHzAMajor() throws {
        let meta = try MusicXMLExtractor.extract(musicXML: Self.minimalScore(fifths: 3))
        #expect(abs(meta.defaultSaFrequencyHz - 440.0) < 0.001)
    }

    @Test("Eb minor → Sa ≈ 311.13 Hz (Eb4)")
    func saHzEbMinor() throws {
        let xml = Self.minimalScore(fifths: -6, mode: "minor")
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        // Eb minor has -6 fifths, tonic Eb. MIDI 63 → 311.127 Hz.
        #expect(abs(meta.defaultSaFrequencyHz - 311.127) < 0.01)
    }

    @Test("G major → Sa ≈ 392 Hz (G4)")
    func saHzGMajor() throws {
        let meta = try MusicXMLExtractor.extract(musicXML: Self.minimalScore(fifths: 1))
        #expect(abs(meta.defaultSaFrequencyHz - 391.995) < 0.01)
    }

    // MARK: - Staff per note

    @Test("Note without <staff> defaults to 1")
    func staffDefaultsToOne() throws {
        let meta = try MusicXMLExtractor.extract(musicXML: Self.trivialCMajor)
        #expect(meta.staffPerNote.count == 1)
        #expect(meta.staffPerNote[0] == [1])
    }

    @Test("Note with <staff>2</staff> recorded as 2 (LH)")
    func staffTwoForLH() throws {
        let extra = """
            <note>
              <pitch><step>D</step><octave>3</octave></pitch>
              <duration>1</duration><type>quarter</type>
              <staff>2</staff>
            </note>
            """
        let xml = Self.minimalScore(fifths: 0, extraNoteXML: extra)
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        #expect(meta.staffPerNote.count == 1)
        #expect(meta.staffPerNote[0] == [1, 2])
    }

    @Test("Multiple parts produce one staff array per part")
    func multiPartStaff() throws {
        let xml = """
            <?xml version="1.0"?>
            <score-partwise version="3.1">
              <part-list>
                <score-part id="P1"><part-name>RH</part-name></score-part>
                <score-part id="P2"><part-name>LH</part-name></score-part>
              </part-list>
              <part id="P1">
                <measure number="1">
                  <attributes><divisions>1</divisions><key><fifths>0</fifths></key>
                  <time><beats>4</beats><beat-type>4</beat-type></time></attributes>
                  <note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note>
                </measure>
              </part>
              <part id="P2">
                <measure number="1">
                  <note><pitch><step>C</step><octave>3</octave></pitch>
                    <duration>1</duration><staff>2</staff></note>
                  <note><pitch><step>D</step><octave>3</octave></pitch>
                    <duration>1</duration><staff>2</staff></note>
                </measure>
              </part>
            </score-partwise>
            """
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        #expect(meta.staffPerNote.count == 2)
        #expect(meta.staffPerNote[0] == [1])
        #expect(meta.staffPerNote[1] == [2, 2])
    }

    @Test("Chord-tone notes are included in staff array")
    func chordTonesIncluded() throws {
        let extra = """
            <note>
              <chord/>
              <pitch><step>E</step><octave>4</octave></pitch>
              <duration>1</duration>
            </note>
            <note>
              <chord/>
              <pitch><step>G</step><octave>4</octave></pitch>
              <duration>1</duration>
            </note>
            """
        let xml = Self.minimalScore(fifths: 0, extraNoteXML: extra)
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        // 1 base note + 2 chord tones = 3 entries.
        #expect(meta.staffPerNote[0].count == 3)
    }

    // MARK: - Lyrics

    @Test("Note with <lyric><text> records syllable")
    func lyricCaptured() throws {
        let extra = """
            <note>
              <pitch><step>D</step><octave>4</octave></pitch>
              <duration>1</duration>
              <lyric number="1"><text>Sa</text></lyric>
            </note>
            """
        let xml = Self.minimalScore(fifths: 0, extraNoteXML: extra)
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        #expect(meta.lyricsPerNote.count == 1)
        #expect(meta.lyricsPerNote[0].count == 1)
        #expect(meta.lyricsPerNote[0][0].syllable == "Sa")
        #expect(meta.lyricsPerNote[0][0].noteIndex == 1)
    }

    @Test("Note without lyric does not appear in lyrics array")
    func noteWithoutLyric() throws {
        let meta = try MusicXMLExtractor.extract(musicXML: Self.trivialCMajor)
        #expect(meta.lyricsPerNote.count == 1)
        #expect(meta.lyricsPerNote[0].isEmpty)
    }

    @Test("Lyric noteIndex aligns with staff array when interleaved")
    func lyricNoteIndexAlignment() throws {
        // Note 0: no lyric. Note 1: lyric "Re". Note 2: no lyric.
        let extra = """
            <note>
              <pitch><step>D</step><octave>4</octave></pitch><duration>1</duration>
              <lyric number="1"><text>Re</text></lyric>
            </note>
            <note>
              <pitch><step>E</step><octave>4</octave></pitch><duration>1</duration>
            </note>
            """
        let xml = Self.minimalScore(fifths: 0, extraNoteXML: extra)
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        #expect(meta.staffPerNote[0].count == 3)
        #expect(meta.lyricsPerNote[0].count == 1)
        #expect(meta.lyricsPerNote[0][0].noteIndex == 1)
        #expect(meta.lyricsPerNote[0][0].syllable == "Re")
    }

    @Test("Multiple lyric verses collapse to verse 1 only")
    func multipleVerseCollapse() throws {
        let extra = """
            <note>
              <pitch><step>D</step><octave>4</octave></pitch><duration>1</duration>
              <lyric number="1"><text>Sa</text></lyric>
              <lyric number="2"><text>Re</text></lyric>
            </note>
            """
        let xml = Self.minimalScore(fifths: 0, extraNoteXML: extra)
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        #expect(meta.lyricsPerNote[0].count == 1)
        #expect(meta.lyricsPerNote[0][0].syllable == "Sa")
    }

    // MARK: - Malformed input

    @Test("Garbage input throws .malformed")
    func garbageThrows() {
        #expect(throws: MusicXMLExtractorError.self) {
            try MusicXMLExtractor.extract(musicXML: "not xml at all <<<")
        }
    }

    @Test("Truncated XML throws .malformed")
    func truncatedThrows() {
        let xml = "<?xml version=\"1.0\"?><score-partwise><part-list><score-part"
        #expect(throws: MusicXMLExtractorError.self) {
            try MusicXMLExtractor.extract(musicXML: xml)
        }
    }

    @Test("Empty string throws .malformed")
    func emptyStringThrows() {
        #expect(throws: MusicXMLExtractorError.self) {
            try MusicXMLExtractor.extract(musicXML: "")
        }
    }

    // MARK: - Defaults / edge cases

    @Test("Score with no <key> at all defaults to C major")
    func noKeyElement() throws {
        let xml = """
            <?xml version="1.0"?>
            <score-partwise version="3.1">
              <part-list><score-part id="P1"/></part-list>
              <part id="P1">
                <measure number="1">
                  <note><pitch><step>C</step><octave>4</octave></pitch>
                    <duration>1</duration></note>
                </measure>
              </part>
            </score-partwise>
            """
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        #expect(meta.keySignatureRaw == "C major")
        #expect(meta.timeSignatureRaw == "4/4")  // fallback
    }

    @Test("Empty score (no parts) yields empty staffPerNote")
    func noParts() throws {
        let xml = """
            <?xml version="1.0"?>
            <score-partwise version="3.1">
              <part-list/>
            </score-partwise>
            """
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        #expect(meta.staffPerNote.isEmpty)
        #expect(meta.lyricsPerNote.isEmpty)
    }

    // MARK: - Sendable / cross-isolation

    @Test("extract works inside a detached Task (Sendable correctness)")
    func extractAcrossIsolation() async throws {
        let xml = Self.trivialCMajor
        let meta = try await Task.detached {
            try MusicXMLExtractor.extract(musicXML: xml)
        }.value
        #expect(meta.keySignatureRaw == "C major")
        #expect(meta.timeSignatureRaw == "4/4")
    }

    @Test("Returned MusicXMLMetadata is Equatable")
    func metadataEquatable() throws {
        let a = try MusicXMLExtractor.extract(musicXML: Self.trivialCMajor)
        let b = try MusicXMLExtractor.extract(musicXML: Self.trivialCMajor)
        #expect(a == b)
    }

    @Test("LyricEvent is Equatable")
    func lyricEventEquatable() {
        let a = LyricEvent(noteIndex: 5, syllable: "Sa")
        let b = LyricEvent(noteIndex: 5, syllable: "Sa")
        #expect(a == b)
    }
}

@Suite("MusicXMLExtractor + bundled MXL fixtures")
struct MusicXMLExtractorBundledFixtureTests {

    @Test("Sukhkarta MXL → A major, 4/4, lyrics present")
    func sukhkartaFixture() throws {
        guard let mxlURL = Bundle.main.url(
            forResource: "Sukhkarta_Dukhharta", withExtension: "mxl"
        ) else {
            return  // asset not in test bundle; skip
        }
        let mxl = try Data(contentsOf: mxlURL)
        let xml = try MXLLoader.loadMusicXML(from: mxl)
        let meta = try MusicXMLExtractor.extract(musicXML: xml)

        #expect(meta.keySignatureRaw == "A major")
        #expect(meta.timeSignatureRaw == "4/4")
        // 1 part, ~258 notes (with chord tones) and ≥ ~70 lyric events.
        #expect(meta.staffPerNote.count == 1)
        #expect(meta.staffPerNote[0].count > 100)
        #expect(meta.lyricsPerNote.count == 1)
        #expect(meta.lyricsPerNote[0].count >= 50)
        // Sa frequency = A4 = 440 Hz.
        #expect(abs(meta.defaultSaFrequencyHz - 440.0) < 0.01)
    }

    @Test("Sukhkarta MXL → multi-staff RH/LH note distribution")
    func sukhkartaMultiStaff() throws {
        guard let mxlURL = Bundle.main.url(
            forResource: "Sukhkarta_Dukhharta", withExtension: "mxl"
        ) else { return }
        let mxl = try Data(contentsOf: mxlURL)
        let xml = try MXLLoader.loadMusicXML(from: mxl)
        let meta = try MusicXMLExtractor.extract(musicXML: xml)
        let staves = meta.staffPerNote[0]
        let staffSet = Set(staves)
        // Sukhkarta is a piano part with both RH (1) and LH (2) notes.
        #expect(staffSet.contains(1))
        #expect(staffSet.contains(2))
    }

    @Test("James Bond MXL → multi-part orchestra, no lyrics")
    func jamesBondFixture() throws {
        guard let mxlURL = Bundle.main.url(
            forResource: "james-bond-theme", withExtension: "mxl"
        ) else {
            return
        }
        let mxl = try Data(contentsOf: mxlURL)
        let xml = try MXLLoader.loadMusicXML(from: mxl)
        let meta = try MusicXMLExtractor.extract(musicXML: xml)

        // First <key> in document is fifths=1 (G major).
        #expect(meta.keySignatureRaw == "G major")
        #expect(meta.timeSignatureRaw == "4/4")
        // 15 instrumental parts.
        #expect(meta.staffPerNote.count >= 10)
        // Total notes across all parts is large.
        let totalNotes = meta.staffPerNote.reduce(0) { $0 + $1.count }
        #expect(totalNotes > 1000)
        // No lyrics in James Bond.
        let totalLyrics = meta.lyricsPerNote.reduce(0) { $0 + $1.count }
        #expect(totalLyrics == 0)
    }
}
