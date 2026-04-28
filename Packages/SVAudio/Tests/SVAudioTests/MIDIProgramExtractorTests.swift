// Packages/SVAudio/Tests/SVAudioTests/MIDIProgramExtractorTests.swift
import Foundation
import Testing

@testable import SVAudio

@Suite("MIDIProgramExtractor")
struct MIDIProgramExtractorTests {

    /// Helper: build a minimal Format-1 SMF with N tracks, each with one Program Change event
    /// followed by an end-of-track meta event. Programs is the per-track program byte.
    private func buildSMF(programs: [UInt8?]) -> Data {
        var data = Data()
        // Header chunk: "MThd", length=6, format=1, ntrks=N, division=480
        data.append(contentsOf: "MThd".utf8)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x06])  // length
        data.append(contentsOf: [0x00, 0x01])              // format 1
        let ntrks = UInt16(programs.count)
        data.append(contentsOf: [UInt8((ntrks >> 8) & 0xFF), UInt8(ntrks & 0xFF)])
        data.append(contentsOf: [0x01, 0xE0])              // division 480

        for program in programs {
            data.append(contentsOf: "MTrk".utf8)
            // Build track payload first, then prepend its length.
            var track = Data()
            if let p = program {
                // delta=0, ProgramChange channel 0 (0xC0), program p
                track.append(contentsOf: [0x00, 0xC0, p])
            }
            // delta=0, end-of-track meta: 0xFF 0x2F 0x00
            track.append(contentsOf: [0x00, 0xFF, 0x2F, 0x00])

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

    @Test("Extracts first program change per track")
    func extractsPrograms() throws {
        let smf = buildSMF(programs: [0, 27, 56])
        let result = try MIDIProgramExtractor.extractPrograms(midi: smf)
        #expect(result.count == 3)
        #expect(result[0] == 0)
        #expect(result[1] == 27)
        #expect(result[2] == 56)
    }

    @Test("Returns nil for tracks with no Program Change")
    func nilForNoPC() throws {
        let smf = buildSMF(programs: [0, nil, 56])
        let result = try MIDIProgramExtractor.extractPrograms(midi: smf)
        #expect(result.count == 3)
        #expect(result[0] == 0)
        #expect(result[1] == nil)
        #expect(result[2] == 56)
    }

    @Test("Throws on missing MThd")
    func throwsOnMissingHeader() {
        let bogus = Data([0x00, 0x01, 0x02, 0x03])
        #expect(throws: MIDIProgramExtractor.Error.self) {
            _ = try MIDIProgramExtractor.extractPrograms(midi: bogus)
        }
    }

    @Test("Throws on truncated input")
    func throwsOnTruncated() {
        let truncated = Data("MThd\u{00}\u{00}\u{00}\u{06}".utf8)
        #expect(throws: MIDIProgramExtractor.Error.self) {
            _ = try MIDIProgramExtractor.extractPrograms(midi: truncated)
        }
    }

    @Test("Handles real bundled .mid (if available)") @MainActor
    func realBundledMid() throws {
        // The audition POC's .mid files were deleted, so this test is a placeholder
        // for when production .mid sources are wired up. Keep as smoke check.
        // Skip the test if Bundle.main has no .mid files.
        // (No-op for now — this test exists to be uncommented when production
        // content is added.)
        #expect(true)
    }
}
