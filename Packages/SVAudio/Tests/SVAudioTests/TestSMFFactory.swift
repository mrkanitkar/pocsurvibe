import Foundation

/// Helper for synthesizing minimal Standard MIDI File bytes for tests.
/// Mirrors the inline SMF builder in `MIDIProgramExtractorTests` so the
/// same shape can be reused across multiple test suites.
enum TestSMFFactory {
    /// Build a minimal Format-1 SMF with N tracks. Each track contains a
    /// single Program Change event (or none, if the corresponding entry
    /// is `nil`) followed by an end-of-track meta event.
    static func buildSMF(programs: [UInt8?]) -> Data {
        var data = Data()
        data.append(contentsOf: "MThd".utf8)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x06])  // length
        data.append(contentsOf: [0x00, 0x01])              // format 1
        let ntrks = UInt16(programs.count)
        data.append(contentsOf: [UInt8((ntrks >> 8) & 0xFF), UInt8(ntrks & 0xFF)])
        data.append(contentsOf: [0x01, 0xE0])              // division 480

        for program in programs {
            data.append(contentsOf: "MTrk".utf8)
            var track = Data()
            if let p = program {
                track.append(contentsOf: [0x00, 0xC0, p])  // delta=0, ProgramChange ch0
            }
            track.append(contentsOf: [0x00, 0xFF, 0x2F, 0x00])  // end-of-track
            let len = UInt32(track.count)
            data.append(contentsOf: [
                UInt8((len >> 24) & 0xFF),
                UInt8((len >> 16) & 0xFF),
                UInt8((len >> 8) & 0xFF),
                UInt8(len & 0xFF)
            ])
            data.append(track)
        }
        return data
    }
}
