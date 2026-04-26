import Foundation
import ZIPFoundation

/// Test-only helper that builds a `.mxl`-style zip in memory.
enum MXLFixture {
    static func makeZip(entries: [String: String]) throws -> Data {
        let archive = try Archive(data: Data(), accessMode: .create)
        for (path, content) in entries {
            let data = Data(content.utf8)
            try archive.addEntry(
                with: path,
                type: .file,
                uncompressedSize: Int64(data.count),
                compressionMethod: .deflate
            ) { position, size in
                data.subdata(in: Int(position)..<Int(position) + size)
            }
        }
        guard let zipData = archive.data else {
            throw NSError(domain: "MXLFixture", code: -1)
        }
        return zipData
    }
}
