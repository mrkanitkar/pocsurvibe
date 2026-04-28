import Foundation
import os

/// File-mirror logger for the production multi-channel engine. Mirrors every
/// `.info/.warning/.error` call to both `os.Logger` and an on-disk file (when
/// `isFileMirrorEnabled`). `.debug` is always written to `os.Logger` but
/// suppressed from the file mirror to keep per-note events out of disk logs.
///
/// Disk writes are queued on a serial DispatchQueue. File rolls when size
/// exceeds `maxFileSize` (truncates first half, keeps latest half).
///
/// Marked `@unchecked Sendable` because mutable state is the dispatch queue
/// (thread-safe) plus a `FileHandle` only written from inside queue closures.
public final class MultiChannelLog: @unchecked Sendable {

    /// Shared production logger writing to `Documents/audio_log.txt` with a
    /// 5 MB rolling cap.
    public static let shared: MultiChannelLog = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return MultiChannelLog(
            fileURL: docs.appendingPathComponent("audio_log.txt"),
            maxFileSize: 5 * 1024 * 1024  // 5 MB
        )
    }()

    /// Severity levels for log events.
    public enum Level: Int, Comparable, Sendable {
        /// Verbose per-note events — os.Logger only, never written to disk.
        case debug = 0
        /// Lifecycle and informational messages.
        case info = 1
        /// Non-fatal unexpected conditions.
        case warning = 2
        /// Errors that affect audio output.
        case error = 3

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }

        var label: String {
            switch self {
            case .debug: return "DEBUG"
            case .info: return "INFO"
            case .warning: return "WARN"
            case .error: return "ERROR"
            }
        }
    }

    /// URL of the on-disk log file.
    public let logFileURL: URL

    /// Maximum file size in bytes before rolling occurs.
    public let maxFileSize: Int

    /// Writes to disk only when true. DEBUG: defaults true. Release: opt-in
    /// via Settings (caller is responsible for setting from `@AppStorage`).
    public var isFileMirrorEnabled: Bool {
        get { lock.withLock { _isFileMirrorEnabled } }
        set { lock.withLock { _isFileMirrorEnabled = newValue } }
    }

    private let lock = NSLock()
    nonisolated(unsafe) private var _isFileMirrorEnabled: Bool
    private let queue = DispatchQueue(label: "com.survibe.MultiChannelLog")
    private let isoFormatter: ISO8601DateFormatter
    private let osLog = Logger.survibe(category: "MultiChannelEngine")

    /// Designated init — used by tests. Production uses `.shared`.
    ///
    /// - Parameters:
    ///   - fileURL: Destination file for the on-disk mirror.
    ///   - maxFileSize: Byte threshold that triggers a roll.
    ///   - defaultEnabled: Overrides the debug/release default when non-nil.
    public init(fileURL: URL, maxFileSize: Int, defaultEnabled: Bool? = nil) {
        self.logFileURL = fileURL
        self.maxFileSize = maxFileSize
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.isoFormatter = formatter
        if let defaultEnabled {
            self._isFileMirrorEnabled = defaultEnabled
        } else {
            #if DEBUG
            self._isFileMirrorEnabled = true
            #else
            self._isFileMirrorEnabled = false
            #endif
        }
    }

    /// Append a log line. `category` defaults to `"MultiChannelEngine"`.
    ///
    /// `.debug` events go to `os.Logger` only; higher levels also write to
    /// the file mirror when `isFileMirrorEnabled` is `true`.
    public func log(_ level: Level, _ message: String,
                    category: String = "MultiChannelEngine") {
        // Always mirror to os.Logger.
        switch level {
        case .debug:
            osLog.debug("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .info:
            osLog.info("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .warning:
            osLog.warning("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .error:
            osLog.error("[\(category, privacy: .public)] \(message, privacy: .public)")
        }
        // Suppress .debug from file mirror.
        guard level >= .info else { return }
        guard isFileMirrorEnabled else { return }

        let line = "\(isoFormatter.string(from: Date())) [\(level.label)] [\(category)] \(message)\n"
        queue.async { [weak self] in
            self?.appendAndRoll(line)
        }
    }

    /// Append a non-truncating session marker (used at song-load boundaries).
    ///
    /// No-ops when `isFileMirrorEnabled` is `false`.
    public func session(_ marker: String) {
        guard isFileMirrorEnabled else { return }
        let line = "=== session \(marker) \(isoFormatter.string(from: Date())) ===\n"
        queue.async { [weak self] in
            self?.appendAndRoll(line)
        }
    }

    /// Delete the on-disk log file (Settings "Delete logs" action).
    public func purge() {
        queue.async { [weak self] in
            guard let self else { return }
            try? FileManager.default.removeItem(at: self.logFileURL)
        }
    }

    // MARK: - Private

    private func appendAndRoll(_ line: String) {
        // Ensure file exists.
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forUpdating: logFileURL) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        handle.write(Data(line.utf8))

        // Roll if oversized.
        let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path)
        let size = (attrs?[.size] as? Int) ?? 0
        if size > maxFileSize {
            roll()
        }
    }

    private func roll() {
        // Read current file, keep the latest half, rewrite.
        guard let data = try? Data(contentsOf: logFileURL), !data.isEmpty else { return }
        let halfPoint = data.count / 2
        // Find next newline at or after halfPoint to avoid splitting a line.
        var cutPoint = halfPoint
        while cutPoint < data.count && data[cutPoint] != 0x0A {
            cutPoint += 1
        }
        if cutPoint < data.count { cutPoint += 1 }
        let kept = data.subdata(in: cutPoint..<data.count)
        let header = "=== rolled \(isoFormatter.string(from: Date())) (kept latest \(kept.count) bytes) ===\n"
        let rewritten = Data(header.utf8) + kept
        try? rewritten.write(to: logFileURL, options: .atomic)
    }
}
