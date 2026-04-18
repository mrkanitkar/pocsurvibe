import Foundation

/// Cross-module sink for appending diagnostic lines to the session log file
/// that `MIDIEventDiagnostics` (app target) owns. SVAudio cannot depend on the
/// app target, so this bridge holds a closure the app sets at startup.
///
/// Thread safety: `writer` is set once at launch before any worker thread reads
/// it. `nonisolated(unsafe)` is sound because (a) assignment is single-writer
/// at init, (b) closure invocation is idempotent, (c) a stale read can only
/// drop a log line — never corrupt state.
public enum MIDIDiagBridge {
    public nonisolated(unsafe) static var writer: (@Sendable (String) -> Void)?

    /// Forward a line to the installed writer, if any. No-op when unset.
    public static func recordLine(_ line: String) {
        writer?(line)
    }
}
