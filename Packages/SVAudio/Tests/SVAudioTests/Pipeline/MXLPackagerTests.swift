import Foundation
import Testing
import ZIPFoundation
@testable import SVAudio

struct MXLPackagerTests {
    @Test func mimetypeIsFirstEntry() throws {
        let mxl = try MXLPackager.package(musicXML: "<score-partwise version=\"4.0\"></score-partwise>")
        let archive = try Archive(data: mxl, accessMode: .read)
        let first = archive.first
        #expect(first?.path == "mimetype")
    }

    @Test func mimetypeContentExact() throws {
        let mxl = try MXLPackager.package(musicXML: "<x/>")
        let archive = try Archive(data: mxl, accessMode: .read)
        guard let entry = archive["mimetype"] else { Issue.record("mimetype missing"); return }
        var buf = Data()
        _ = try archive.extract(entry) { buf.append($0) }
        #expect(buf == Data("application/vnd.recordare.musicxml".utf8))
    }

    @Test func mimetypeStoredUncompressed() throws {
        let mxl = try MXLPackager.package(musicXML: "<x/>")
        let archive = try Archive(data: mxl, accessMode: .read)
        guard let entry = archive["mimetype"] else { Issue.record("mimetype missing"); return }
        #expect(entry.compressedSize == entry.uncompressedSize, "mimetype must be stored uncompressed")
    }

    @Test func containerXMLPresent() throws {
        let mxl = try MXLPackager.package(musicXML: "<x/>")
        let archive = try Archive(data: mxl, accessMode: .read)
        #expect(archive["META-INF/container.xml"] != nil)
    }

    @Test func scoreMusicXMLPresent() throws {
        let xml = "<score-partwise version=\"4.0\"></score-partwise>"
        let mxl = try MXLPackager.package(musicXML: xml)
        let archive = try Archive(data: mxl, accessMode: .read)
        guard let entry = archive["score.musicxml"] else { Issue.record("score missing"); return }
        var buf = Data()
        _ = try archive.extract(entry) { buf.append($0) }
        #expect(String(data: buf, encoding: .utf8) == xml)
    }
}
