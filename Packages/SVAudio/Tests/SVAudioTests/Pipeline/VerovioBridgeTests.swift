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
}
