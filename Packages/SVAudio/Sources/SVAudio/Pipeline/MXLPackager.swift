import Foundation
import ZIPFoundation

/// Packages a MusicXML 4.0 string into a `.mxl` ZIP container per the W3C MusicXML 4.0 spec.
///
/// The `mimetype` entry MUST be the first entry in the archive, stored uncompressed,
/// US-ASCII, with no BOM and no extra field. `META-INF/container.xml` then references
/// the score file by path. The score itself is written as `score.musicxml`.
public enum MXLPackager {
    /// Errors thrown while packaging an MXL container.
    public enum Error: Swift.Error {
        /// The underlying ZIP archive could not be created or finalized.
        case archiveCreation
    }

    /// Packages the supplied MusicXML string into a ZIP-compressed `.mxl` container.
    ///
    /// The returned `Data` contains a valid MXL archive with `mimetype` as the first
    /// (uncompressed) entry, followed by `META-INF/container.xml` and `score.musicxml`.
    ///
    /// - Parameter musicXML: A MusicXML 4.0 document as a UTF-8 string.
    /// - Returns: The packaged `.mxl` archive bytes.
    /// - Throws: `MXLPackager.Error.archiveCreation` if the archive cannot be built,
    ///   or any error propagated from `ZIPFoundation` while adding entries.
    public static func package(musicXML: String) throws -> Data {
        guard let archive = Archive(accessMode: .create) else { throw Error.archiveCreation }
        // 1) mimetype FIRST, stored uncompressed.
        let mimetype = Data("application/vnd.recordare.musicxml".utf8)
        try archive.addEntry(
            with: "mimetype",
            type: .file,
            uncompressedSize: Int64(mimetype.count),
            compressionMethod: .none,
            provider: { position, size in
                let start = Int(position)
                let end = start + size
                return mimetype.subdata(in: start..<end)
            }
        )
        // 2) META-INF/container.xml.
        let container = Data(#"""
        <?xml version="1.0" encoding="UTF-8"?>
        <container>
          <rootfiles>
            <rootfile full-path="score.musicxml" media-type="application/vnd.recordare.musicxml+xml"/>
          </rootfiles>
        </container>
        """#.utf8)
        try archive.addEntry(
            with: "META-INF/container.xml",
            type: .file,
            uncompressedSize: Int64(container.count),
            compressionMethod: .deflate,
            provider: { position, size in
                container.subdata(in: Int(position)..<Int(position) + size)
            }
        )
        // 3) score.musicxml.
        let score = Data(musicXML.utf8)
        try archive.addEntry(
            with: "score.musicxml",
            type: .file,
            uncompressedSize: Int64(score.count),
            compressionMethod: .deflate,
            provider: { position, size in
                score.subdata(in: Int(position)..<Int(position) + size)
            }
        )
        guard let data = archive.data else { throw Error.archiveCreation }
        return data
    }
}
