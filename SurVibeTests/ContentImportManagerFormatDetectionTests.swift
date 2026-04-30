import Foundation
import Testing
@testable import SurVibe

// MARK: - ContentImportManager Format Detection Tests

/// Tests for `ContentImportManager.detectFormat(_:)` content-sniffing logic (A9 gap).
///
/// Each test writes a temporary file, runs `detectFormat`, and cleans up with `defer`.
/// Tests cover ZIP magic bytes, XML preambles, and unknown/empty content.
@Suite("ContentImportManager Format Detection")
@MainActor
struct ContentImportManagerFormatDetectionTests {

    // MARK: - Helpers

    /// Write `bytes` to a temporary file, returning its URL.
    /// The caller owns cleanup via `defer { try? FileManager.default.removeItem(at: url) }`.
    private func temporaryFile(containing data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try data.write(to: url)
        return url
    }

    private func temporaryFile(containing string: String, encoding: String.Encoding = .utf8) throws -> URL {
        let data = string.data(using: encoding) ?? Data()
        return try temporaryFile(containing: data)
    }

    // MARK: - MXL (ZIP magic bytes)

    @Test("detectFormatRecognizesMxlByZipMagic — PK\\x03\\x04 leading bytes return .mxl")
    func detectFormatRecognizesMxlByZipMagic() throws {
        var zipMagic = Data([0x50, 0x4B, 0x03, 0x04])
        zipMagic.append(contentsOf: [UInt8](repeating: 0x00, count: 100))

        let url = try temporaryFile(containing: zipMagic)
        defer { try? FileManager.default.removeItem(at: url) }

        let format = try ContentImportManager.detectFormat(url)
        #expect(format == .mxl)
    }

    // MARK: - MusicXML (XML preamble, score-partwise)

    @Test("detectFormatRecognizesMusicXMLByScorePartwise — score-partwise root returns .musicxml")
    func detectFormatRecognizesMusicXMLByScorePartwise() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN"
                "http://www.musicxml.org/dtds/partwise.dtd">
            <score-partwise version="4.0">
            </score-partwise>
            """

        let url = try temporaryFile(containing: xml)
        defer { try? FileManager.default.removeItem(at: url) }

        let format = try ContentImportManager.detectFormat(url)
        #expect(format == .musicxml)
    }

    @Test("detectFormatRecognizesMusicXMLByScoreTimewise — score-timewise root returns .musicxml")
    func detectFormatRecognizesMusicXMLByScoreTimewise() throws {
        let xml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <score-timewise version="4.0">
            </score-timewise>
            """

        let url = try temporaryFile(containing: xml)
        defer { try? FileManager.default.removeItem(at: url) }

        let format = try ContentImportManager.detectFormat(url)
        #expect(format == .musicxml)
    }

    @Test("detectFormatRecognizesMusicXMLByXMLPreamble — bare <?xml preamble returns .musicxml")
    func detectFormatRecognizesMusicXMLByXMLPreamble() throws {
        // File that has <?xml but no score root — still matches via preamble rule
        let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?><root/>"

        let url = try temporaryFile(containing: xml)
        defer { try? FileManager.default.removeItem(at: url) }

        let format = try ContentImportManager.detectFormat(url)
        #expect(format == .musicxml)
    }

    // MARK: - Unknown

    @Test("detectFormatReturnsUnknownForRandomBytes — non-XML content returns .unknown")
    func detectFormatReturnsUnknownForRandomBytes() throws {
        // Arbitrary binary bytes that are not ZIP magic and not valid UTF-8 XML
        let randomBytes = Data([0xFF, 0xFE, 0x00, 0x01, 0xAB, 0xCD, 0xEF, 0x42])

        let url = try temporaryFile(containing: randomBytes)
        defer { try? FileManager.default.removeItem(at: url) }

        let format = try ContentImportManager.detectFormat(url)
        #expect(format == .unknown)
    }

    @Test("detectFormatReturnsUnknownForEmptyFile — zero-byte file returns .unknown")
    func detectFormatReturnsUnknownForEmptyFile() throws {
        let url = try temporaryFile(containing: Data())
        defer { try? FileManager.default.removeItem(at: url) }

        let format = try ContentImportManager.detectFormat(url)
        #expect(format == .unknown)
    }

    @Test("detectFormatReturnsUnknownForPlainText — plain text without XML markers returns .unknown")
    func detectFormatReturnsUnknownForPlainText() throws {
        let url = try temporaryFile(containing: "Hello, this is not a MusicXML file.")
        defer { try? FileManager.default.removeItem(at: url) }

        let format = try ContentImportManager.detectFormat(url)
        #expect(format == .unknown)
    }

    // MARK: - Error case

    @Test("detectFormatThrowsForMissingFile — non-existent file throws fileUnreadable")
    func detectFormatThrowsForMissingFile() throws {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).mxl")

        #expect(throws: (any Error).self) {
            _ = try ContentImportManager.detectFormat(missingURL)
        }
    }
}
