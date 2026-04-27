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

    /// On-disk URL of the log file. Truncated at every `start()`.
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

    /// Truncate the log file and prepare it for fresh writes.
    /// Call once per pipeline session (e.g. when the user toggles the
    /// "Use multi-channel pipeline" switch ON).
    public func start() {
        queue.sync {
            handle?.closeFile()
            FileManager.default.createFile(atPath: url.path, contents: nil)
            handle = try? FileHandle(forWritingTo: url)
            let header = "=== pipeline_log started \(isoFormatter.string(from: Date())) ===\n"
            handle?.write(Data(header.utf8))
        }
        osLogger.info("PipelineFileLog: started → \(self.url.path, privacy: .public)")
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
