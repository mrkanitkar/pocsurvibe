import Foundation
import ZIPFoundation

/// Streaming `.mxl` (compressed MusicXML) loader.
///
/// `.mxl` is a ZIP container with `META-INF/container.xml` listing one
/// or more `<rootfile full-path="..."/>` entries. The first rootfile is
/// the score document. We extract it in-memory (no disk write) and
/// return it as a `String` ready for `VerovioBridge`.
public enum MXLLoader {

    /// Path inside every `.mxl` that points to the score's true location.
    private static let containerPath = "META-INF/container.xml"

    /// Load the MusicXML score from a `.mxl` byte buffer.
    ///
    /// Reads `META-INF/container.xml` to locate the first `<rootfile full-path="..."/>`,
    /// then extracts that entry entirely in-memory — no disk write.
    ///
    /// - Parameter mxl: Raw `.mxl` (zip) bytes — typically from
    ///   `Bundle.main.url(forResource:withExtension:)` + `Data(contentsOf:)`.
    /// - Returns: The MusicXML score document as a UTF-8 string.
    /// - Throws: `PipelineError.mxlUnzipFailed` for any zip/parse failure.
    public static func loadMusicXML(from mxl: Data) throws -> String {
        let archive: Archive
        do {
            archive = try Archive(data: mxl, accessMode: .read)
        } catch {
            throw PipelineError.mxlUnzipFailed(reason: "Not a valid zip: \(error.localizedDescription)")
        }

        guard let containerEntry = archive[containerPath] else {
            throw PipelineError.mxlUnzipFailed(reason: "Missing META-INF/container.xml")
        }

        let containerData = try extract(entry: containerEntry, from: archive)
        let rootfilePath = try parseRootfilePath(from: containerData)

        guard let scoreEntry = archive[rootfilePath] else {
            throw PipelineError.mxlUnzipFailed(reason: "Rootfile '\(rootfilePath)' not in archive")
        }

        let scoreData = try extract(entry: scoreEntry, from: archive)
        guard let xml = String(data: scoreData, encoding: .utf8) else {
            throw PipelineError.mxlUnzipFailed(reason: "Score is not valid UTF-8")
        }
        return xml
    }

    // MARK: - Private helpers

    /// Extract all bytes of a single archive entry into a `Data` buffer.
    ///
    /// - Parameters:
    ///   - entry: The entry to extract.
    ///   - archive: The archive containing the entry.
    /// - Returns: The decompressed entry contents.
    /// - Throws: `PipelineError.mxlUnzipFailed` if extraction fails.
    private static func extract(entry: Entry, from archive: Archive) throws -> Data {
        var buffer = Data()
        do {
            _ = try archive.extract(entry) { chunk in
                buffer.append(chunk)
            }
        } catch {
            throw PipelineError.mxlUnzipFailed(
                reason: "Extract '\(entry.path)' failed: \(error.localizedDescription)"
            )
        }
        return buffer
    }

    /// Parse `META-INF/container.xml` and return the first rootfile path.
    ///
    /// Uses a minimal SAX parser to locate `<rootfile full-path="..."/>`.
    ///
    /// - Parameter containerXML: Raw bytes of `META-INF/container.xml`.
    /// - Returns: The `full-path` attribute value of the first `<rootfile>` element.
    /// - Throws: `PipelineError.mxlUnzipFailed` if the element or attribute is absent.
    private static func parseRootfilePath(from containerXML: Data) throws -> String {
        let delegate = ContainerXMLDelegate()
        let parser = XMLParser(data: containerXML)
        parser.delegate = delegate
        guard parser.parse(), let path = delegate.rootfilePath, !path.isEmpty else {
            throw PipelineError.mxlUnzipFailed(
                reason: "container.xml missing <rootfile full-path=...>"
            )
        }
        return path
    }
}

/// Minimal SAX parser for `META-INF/container.xml`.
///
/// Extracts the first `<rootfile full-path="..."/>` attribute.
/// Single-shot, single-thread use only.
///
/// - Note: `@unchecked Sendable` is safe here because `ContainerXMLDelegate`
///   is instantiated, used, and discarded within a single synchronous call
///   to `MXLLoader.parseRootfilePath`. No cross-isolation transfer occurs.
private final class ContainerXMLDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {

    /// The path extracted from the first `<rootfile full-path="..."/>` encountered.
    var rootfilePath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "rootfile", rootfilePath == nil else { return }
        rootfilePath = attributeDict["full-path"]
    }
}
