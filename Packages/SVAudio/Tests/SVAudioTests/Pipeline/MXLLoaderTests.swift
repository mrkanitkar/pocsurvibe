import Foundation
import Testing

@testable import SVAudio

@Suite("MXLLoader")
struct MXLLoaderTests {

    /// Build a tiny in-memory `.mxl` (zip with META-INF/container.xml + score.xml)
    /// using ZIPFoundation, so tests don't depend on a bundled audition asset.
    private static func makeFixtureMXL() throws -> Data {
        let containerXML = """
            <?xml version="1.0"?>
            <container>
              <rootfiles>
                <rootfile full-path="score.xml"/>
              </rootfiles>
            </container>
            """
        let scoreXML = """
            <?xml version="1.0"?>
            <score-partwise version="3.1">
              <part-list><score-part id="P1"><part-name>Test</part-name></score-part></part-list>
              <part id="P1"><measure number="1"/></part>
            </score-partwise>
            """
        return try MXLFixture.makeZip(entries: [
            "META-INF/container.xml": containerXML,
            "score.xml": scoreXML,
        ])
    }

    @Test("Loads valid .mxl and extracts MusicXML")
    func loadValidMXL() throws {
        let mxl = try Self.makeFixtureMXL()
        let xml = try MXLLoader.loadMusicXML(from: mxl)
        #expect(xml.contains("score-partwise"))
        #expect(xml.contains("Test"))
    }

    @Test("Throws when .mxl is malformed (not a zip)")
    func malformedThrows() {
        let junk = Data([0x00, 0x01, 0x02, 0x03])
        #expect(throws: PipelineError.self) {
            try MXLLoader.loadMusicXML(from: junk)
        }
    }

    @Test("Throws when container.xml is missing")
    func missingContainer() throws {
        let zip = try MXLFixture.makeZip(entries: ["score.xml": "<x/>"])
        #expect(throws: PipelineError.self) {
            try MXLLoader.loadMusicXML(from: zip)
        }
    }

    @Test("Throws when rootfile referenced by container.xml is missing")
    func missingRootfile() throws {
        let containerXML = """
            <?xml version="1.0"?>
            <container><rootfiles><rootfile full-path="missing.xml"/></rootfiles></container>
            """
        let zip = try MXLFixture.makeZip(entries: [
            "META-INF/container.xml": containerXML,
        ])
        #expect(throws: PipelineError.self) {
            try MXLLoader.loadMusicXML(from: zip)
        }
    }
}
