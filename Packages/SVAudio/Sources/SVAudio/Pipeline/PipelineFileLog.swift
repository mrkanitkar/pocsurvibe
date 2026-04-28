import Foundation
import os

/// Append-only file logger for the audition pipeline POC. Mirrors every
/// `log(_:)` call into `Documents/pipeline_log.txt` AND into `os.Logger`.
///
/// Why we need both: real-iOS-device os.Logger output cannot be pulled
/// from the host Mac without sysdiagnose, but `Documents/` files can be
/// pulled in seconds via `xcrun devicectl device copy from --domain-type
/// appDataContainer`. So a file mirror is the simplest path to capture
/// diagnostic output for offline analysis.
///
/// Marked `@unchecked Sendable` because the only mutable state is a
/// dispatch queue (itself thread-safe) plus a single FileHandle that is
/// only ever written from inside the queue's serial closures.
public final class PipelineFileLog: @unchecked Sendable {

    public static let shared = PipelineFileLog()

    /// On-disk URL of the log file.
    public let url: URL

    private let queue = DispatchQueue(label: "com.survibe.PipelineFileLog")
    private let osLogger = Logger.survibe(category: "PipelineFileLog")
    private var handle: FileHandle?
    private let isoFormatter: ISO8601DateFormatter

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.url = docs.appendingPathComponent("pipeline_log.txt")
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = formatter
    }

    /// Open (or re-open) the log file for writes. When `truncate == true`
    /// the file is recreated empty; when `false` writes append to whatever
    /// is already on disk. The file handle is positioned at end-of-file
    /// after this call so the next `log(_:)` writes a fresh trailing line
    /// rather than overwriting existing content.
    ///
    /// Use `truncate: true` for a hard reset (e.g. cold app launch). Use
    /// `truncate: false` to mark the start of a new session within the
    /// same on-disk file so multiple song-cycles in one app run all land
    /// in one log.
    ///
    /// - Parameter truncate: When `true`, recreate the file. Default `true`
    ///   for backwards compatibility with existing call sites.
    public func start(truncate: Bool = true) {
        queue.sync {
            handle?.closeFile()
            if truncate || !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            handle = try? FileHandle(forWritingTo: url)
            if !truncate {
                try? handle?.seekToEnd()
            }
            let kind = truncate ? "started" : "session"
            let header = "=== pipeline_log \(kind) \(isoFormatter.string(from: Date())) ===\n"
            handle?.write(Data(header.utf8))
        }
        let kind = truncate ? "started" : "session"
        osLogger.info("PipelineFileLog: \(kind, privacy: .public) → \(self.url.path, privacy: .public)")
    }

    /// Append one line. Adds an ISO8601 timestamp prefix and a newline.
    public func log(_ message: String) {
        let line = "\(isoFormatter.string(from: Date())) \(message)\n"
        queue.async { [weak self] in
            self?.handle?.write(Data(line.utf8))
        }
        osLogger.info("\(message, privacy: .public)")
    }
}
