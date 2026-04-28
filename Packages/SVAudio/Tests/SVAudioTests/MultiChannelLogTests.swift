// Packages/SVAudio/Tests/SVAudioTests/MultiChannelLogTests.swift
import Foundation
import Testing

@testable import SVAudio

@Suite("MultiChannelLog", .serialized)
struct MultiChannelLogTests {

    private func tempLog() -> MultiChannelLog {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_audio_log_\(UUID().uuidString).txt")
        return MultiChannelLog(fileURL: url, maxFileSize: 1024)
    }

    @Test("log writes one line per call when file mirror enabled")
    func logsLine() throws {
        let logger = tempLog()
        logger.isFileMirrorEnabled = true
        logger.log(.info, "hello world")
        // Wait briefly for the async write
        Thread.sleep(forTimeInterval: 0.05)
        let contents = try String(contentsOf: logger.logFileURL, encoding: .utf8)
        #expect(contents.contains("hello world"))
        #expect(contents.contains("INFO"))
    }

    @Test("log skips disk write when file mirror disabled")
    func disabledNoDisk() throws {
        let logger = tempLog()
        logger.isFileMirrorEnabled = false
        logger.log(.info, "should not appear")
        Thread.sleep(forTimeInterval: 0.05)
        let exists = FileManager.default.fileExists(atPath: logger.logFileURL.path)
        if exists {
            let contents = try String(contentsOf: logger.logFileURL, encoding: .utf8)
            #expect(contents.isEmpty)
        } else {
            #expect(!exists)
        }
    }

    @Test("debug level is suppressed from file mirror by default")
    func debugSuppressedFromFile() throws {
        let logger = tempLog()
        logger.isFileMirrorEnabled = true
        logger.log(.debug, "noisy per-note")
        logger.log(.info, "lifecycle")
        Thread.sleep(forTimeInterval: 0.05)
        let contents = try String(contentsOf: logger.logFileURL, encoding: .utf8)
        #expect(!contents.contains("noisy per-note"))
        #expect(contents.contains("lifecycle"))
    }

    @Test("session marker is appended without truncating")
    func sessionMarker() throws {
        let logger = tempLog()
        logger.isFileMirrorEnabled = true
        logger.log(.info, "first line")
        logger.session("new song")
        logger.log(.info, "second line")
        Thread.sleep(forTimeInterval: 0.05)
        let contents = try String(contentsOf: logger.logFileURL, encoding: .utf8)
        #expect(contents.contains("first line"))
        #expect(contents.contains("=== session new song"))
        #expect(contents.contains("second line"))
    }

    @Test("rolling truncates when exceeding maxFileSize")
    func rollingTruncate() throws {
        let logger = tempLog()  // maxFileSize = 1024
        logger.isFileMirrorEnabled = true
        for i in 0..<200 {
            logger.log(.info, "line number \(i) padding xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
        }
        Thread.sleep(forTimeInterval: 0.2)
        let attrs = try FileManager.default.attributesOfItem(atPath: logger.logFileURL.path)
        let size = (attrs[.size] as? Int) ?? 0
        #expect(size <= 2 * 1024)  // bounded by ~2x maxFileSize during rolling
    }
}
