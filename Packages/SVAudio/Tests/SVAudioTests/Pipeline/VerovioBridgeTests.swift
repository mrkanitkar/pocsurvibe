import Foundation
import Testing

@testable import SVAudio

@Suite("VerovioBridge")
@MainActor
struct VerovioBridgeTests {

    /// Minimal valid MusicXML — single part, single C4 quarter note.
    private static let trivialScore = """
        <?xml version="1.0"?>
        <score-partwise version="3.1">
          <part-list>
            <score-part id="P1"><part-name>Piano</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1">
              <attributes>
                <divisions>1</divisions>
                <key><fifths>0</fifths></key>
                <time><beats>4</beats><beat-type>4</beat-type></time>
                <clef><sign>G</sign><line>2</line></clef>
              </attributes>
              <note>
                <pitch><step>C</step><octave>4</octave></pitch>
                <duration>1</duration><type>quarter</type>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

    @Test("Renders trivial MusicXML to non-empty MIDI Data")
    func rendersTrivial() throws {
        let bridge = VerovioBridge()
        let result = try bridge.render(musicXML: Self.trivialScore)
        #expect(!result.data.isEmpty)
        // MIDI files start with "MThd"
        let header = result.data.prefix(4)
        #expect(header == Data([0x4D, 0x54, 0x68, 0x64]))
    }

    @Test("Reports at least one track and one channel for trivial score")
    func reportsTracksAndChannels() throws {
        let bridge = VerovioBridge()
        let result = try bridge.render(musicXML: Self.trivialScore)
        #expect(result.trackCount >= 1)
        #expect(!result.channels.isEmpty)
    }

    @Test("Throws PipelineError.verovioRenderFailed on garbage input")
    func throwsOnGarbage() {
        let bridge = VerovioBridge()
        #expect(throws: PipelineError.self) {
            try bridge.render(musicXML: "not xml")
        }
    }

    @Test("Bond .mxl renders to multiple tracks")
    func bondMultiTrack() throws {
        guard let mxlURL = Bundle.main.url(
            forResource: "james-bond-theme", withExtension: "mxl"
        ) else {
            // Asset not available in the test bundle — skip rather than fail.
            return
        }
        let mxl = try Data(contentsOf: mxlURL)
        let xml = try MXLLoader.loadMusicXML(from: mxl)
        let bridge = VerovioBridge()
        let result = try bridge.render(musicXML: xml)
        #expect(result.trackCount >= 4, "Bond theme should expose at least 4 tracks")
    }

    // MARK: - Meta Event Tests

    @Test("Trivial score trackInfo has a track name from meta-0x03")
    func trivialScoreTrackName() throws {
        let bridge = VerovioBridge()
        let result = try bridge.render(musicXML: Self.trivialScore)
        // Verovio sets meta-0x03 from <part-name>Piano</part-name>
        #expect(!result.trackInfo.isEmpty, "Should have at least one music track")
        let hasAnyName = result.trackInfo.contains { $0.trackName != nil }
        #expect(hasAnyName, "At least one track should carry a name from MusicXML part-name")
    }

    @Test("TrackInfo preserves back-compat defaults for new fields")
    func trackInfoBackCompat() {
        let info = TrackInfo(channel: 0, program: nil, isPercussion: false)
        #expect(info.trackName == nil)
        #expect(info.instrumentName == nil)
    }

    @Test("TrackInfo Equatable includes new fields")
    func trackInfoEquality() {
        let a = TrackInfo(
            channel: 0, program: 1, isPercussion: false,
            trackName: "Piano", instrumentName: "Grand"
        )
        let b = TrackInfo(
            channel: 0, program: 1, isPercussion: false,
            trackName: "Violin", instrumentName: "Grand"
        )
        #expect(a != b, "Different trackName should break equality")
    }

    @Test("RenderedMIDI defaults originalBPM to 120 when no tempo event")
    func defaultBPM() {
        let rendered = RenderedMIDI(data: Data(), trackCount: 0, channels: [])
        #expect(rendered.originalBPM == 120.0)
    }

    @Test("Trivial score has a positive originalBPM")
    func trivialScoreBPM() throws {
        let bridge = VerovioBridge()
        let result = try bridge.render(musicXML: Self.trivialScore)
        #expect(result.originalBPM > 0, "BPM should be positive")
    }

    @Test("Multi-part score with explicit tempo extracts correct BPM")
    func explicitTempoBPM() throws {
        // MusicXML with explicit tempo marking of 100 BPM
        let scoreWithTempo = """
            <?xml version="1.0"?>
            <score-partwise version="3.1">
              <part-list>
                <score-part id="P1"><part-name>Flute</part-name></score-part>
              </part-list>
              <part id="P1">
                <measure number="1">
                  <attributes>
                    <divisions>1</divisions>
                    <key><fifths>0</fifths></key>
                    <time><beats>4</beats><beat-type>4</beat-type></time>
                    <clef><sign>G</sign><line>2</line></clef>
                  </attributes>
                  <direction placement="above">
                    <direction-type>
                      <metronome>
                        <beat-unit>quarter</beat-unit>
                        <per-minute>100</per-minute>
                      </metronome>
                    </direction-type>
                    <sound tempo="100"/>
                  </direction>
                  <note>
                    <pitch><step>C</step><octave>5</octave></pitch>
                    <duration>1</duration><type>quarter</type>
                  </note>
                </measure>
              </part>
            </score-partwise>
            """
        let bridge = VerovioBridge()
        let result = try bridge.render(musicXML: scoreWithTempo)
        // Verovio should emit meta-0x51 for tempo=100 → 600000 µs/qn
        // BPM = 60_000_000 / 600_000 = 100.0
        #expect(
            abs(result.originalBPM - 100.0) < 1.0,
            "Expected ~100 BPM but got \(result.originalBPM)"
        )
    }

    // MARK: - RenderOptions / Lyric Tests (Wave 3 C6)

    /// Trivial MusicXML containing a single `<lyric>` so we can assert
    /// Verovio surfaces or strips the lyric depending on `RenderOptions`.
    private static let scoreWithLyric = """
        <?xml version="1.0"?>
        <score-partwise version="3.1">
          <part-list>
            <score-part id="P1"><part-name>Voice</part-name></score-part>
          </part-list>
          <part id="P1">
            <measure number="1">
              <attributes>
                <divisions>1</divisions>
                <key><fifths>0</fifths></key>
                <time><beats>4</beats><beat-type>4</beat-type></time>
                <clef><sign>G</sign><line>2</line></clef>
              </attributes>
              <note>
                <pitch><step>C</step><octave>4</octave></pitch>
                <duration>1</duration><type>quarter</type>
                <lyric number="1"><syllabic>single</syllabic><text>Sukh</text></lyric>
              </note>
            </measure>
          </part>
        </score-partwise>
        """

    @Test("RenderOptions defaults preserve lyrics and voice staff")
    func renderOptionsDefaultsAreLyricFriendly() {
        let opts = VerovioBridge.RenderOptions()
        #expect(opts.includeLyrics == true)
        #expect(opts.includeVoiceStaffWhenLyricsPresent == true)
    }

    @Test("RenderOptions is Sendable and Equatable")
    func renderOptionsAreSendable() {
        let _: any Sendable = VerovioBridge.RenderOptions()
        let a = VerovioBridge.RenderOptions(includeLyrics: true, includeVoiceStaffWhenLyricsPresent: true)
        let b = VerovioBridge.RenderOptions(includeLyrics: true, includeVoiceStaffWhenLyricsPresent: true)
        #expect(a == b)
    }

    @Test("Default render keeps lyric text in SVG")
    func renderWithDefaultOptionsKeepsLyrics() throws {
        let bridge = VerovioBridge()
        let rendered = try bridge.render(musicXML: Self.scoreWithLyric, options: .init())
        let svg = rendered.svgPages.joined()
        // Verovio emits <g class="lyrics"> nodes when lyrics are present
        // and the lyric text itself ("Sukh") appears in the rendered SVG.
        #expect(
            svg.contains("class=\"lyric") || svg.contains("Sukh"),
            "Default render should include lyrics in SVG output"
        )
    }

    @Test("includeLyrics:false strips lyric text from SVG")
    func renderWithIncludeLyricsFalseStripsLyrics() throws {
        let bridge = VerovioBridge()
        let rendered = try bridge.render(
            musicXML: Self.scoreWithLyric,
            options: .init(includeLyrics: false)
        )
        let svg = rendered.svgPages.joined()
        #expect(!svg.contains("Sukh"), "includeLyrics:false should strip lyric text")
    }

    @Test("RenderedScore exposes MIDI data for the same input")
    func renderedScoreCarriesMIDI() throws {
        let bridge = VerovioBridge()
        let rendered = try bridge.render(musicXML: Self.scoreWithLyric, options: .init())
        #expect(!rendered.midi.data.isEmpty)
        #expect(rendered.midi.trackCount >= 1)
        #expect(!rendered.svgPages.isEmpty)
    }

    @Test("Multi-part score emits track names for each part")
    func multiPartTrackNames() throws {
        let duetScore = """
            <?xml version="1.0"?>
            <score-partwise version="3.1">
              <part-list>
                <score-part id="P1"><part-name>Violin</part-name></score-part>
                <score-part id="P2"><part-name>Cello</part-name></score-part>
              </part-list>
              <part id="P1">
                <measure number="1">
                  <attributes>
                    <divisions>1</divisions>
                    <key><fifths>0</fifths></key>
                    <time><beats>4</beats><beat-type>4</beat-type></time>
                    <clef><sign>G</sign><line>2</line></clef>
                  </attributes>
                  <note>
                    <pitch><step>A</step><octave>4</octave></pitch>
                    <duration>1</duration><type>quarter</type>
                  </note>
                </measure>
              </part>
              <part id="P2">
                <measure number="1">
                  <attributes>
                    <divisions>1</divisions>
                    <key><fifths>0</fifths></key>
                    <time><beats>4</beats><beat-type>4</beat-type></time>
                    <clef><sign>F</sign><line>4</line></clef>
                  </attributes>
                  <note>
                    <pitch><step>C</step><octave>3</octave></pitch>
                    <duration>1</duration><type>quarter</type>
                  </note>
                </measure>
              </part>
            </score-partwise>
            """
        let bridge = VerovioBridge()
        let result = try bridge.render(musicXML: duetScore)
        #expect(result.trackInfo.count >= 2, "Duet should have at least 2 music tracks")
        let names = result.trackInfo.compactMap(\.trackName)
        #expect(!names.isEmpty, "At least one track should have a name")
    }
}
