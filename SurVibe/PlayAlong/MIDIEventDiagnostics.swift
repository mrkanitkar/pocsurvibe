import CoreMIDI
import Foundation
import os
import SVCore
import SVAudio

/// Real-time diagnostic logger for MIDI note detection in the play-along pipeline.
///
/// Writes every event to **two** destinations simultaneously:
/// 1. `os.Logger` (visible in Console.app when attached via Xcode debugger)
/// 2. `Documents/midi_diag.log` on the iPad — readable via Xcode Devices & Simulators
///    without needing a simultaneous USB connection. Each session overwrites the file.
///
/// ## How to retrieve the log file
/// 1. Play a session with your MIDI keyboard connected.
/// 2. Tap Stop.
/// 3. Disconnect keyboard, connect iPad to Mac via USB.
/// 4. In Xcode: Window → Devices and Simulators → select your iPad →
///    SurVibe → click the gear icon → Download Container.
/// 5. Right-click the `.xcappdata` file → Show Package Contents →
///    AppData/Documents/midi_diag.log
///
/// ## Key patterns
/// - `[DROP]` — note-on before previous note-off (fast repeat)
/// - `[LAG] ` — MainActor queue delay > 10 ms
/// - `IOI=XXms` — inter-onset: 107 ms ≈ 140 BPM 16th notes
/// - Summary `Pending=N` > 0 — Tasks still queued at session end
///
/// `nonisolated` opts this class out of the project-wide @MainActor default
/// (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). All methods use `OSAllocatedUnfairLock`
/// and are safe to call from any thread, including CoreMIDI's real-time thread.
nonisolated final class MIDIEventDiagnostics: Sendable {

    static let shared = MIDIEventDiagnostics()

    nonisolated private static let logger = Logger.survibe(category: "MIDIDiagnostics")

    /// Set to false to disable all logging with zero overhead.
    ///
    /// `nonisolated(unsafe)` is safe because:
    /// 1. Written only at session boundaries (reset/init) on known threads.
    /// 2. Read atomically by CoreMIDI callbacks (Bool is naturally atomic on ARM64).
    /// 3. A stale read (seeing old value) is benign — at worst logs one extra event.
    nonisolated(unsafe) var isEnabled: Bool = false

    // MARK: - Thread-safe state

    private struct DiagState: Sendable {
        var lastNoteOnNs: [Int: UInt64] = [:]
        var isOn: [Int: Bool] = [:]
        var lastAnyNoteOnNs: UInt64 = 0
        var coreMidiCount: Int = 0
        var mainActorCount: Int = 0
        var totalLagNs: UInt64 = 0
        var maxLagNs: UInt64 = 0
        var dropCount: Int = 0
    }

    private let stateLock = OSAllocatedUnfairLock(initialState: DiagState())

    // File handle for the current session log — written from any thread via fileLock.
    private let fileLock = OSAllocatedUnfairLock(initialState: false) // just used as a mutex
    nonisolated(unsafe) private var fileHandle: FileHandle?

    private init() {}

    // MARK: - Public API

    /// Reset counters and open a fresh log file for a new session.
    nonisolated func reset() {
        stateLock.withLock { $0 = DiagState() }
        openLogFile()
        appendLine("=== SurVibe MIDI Diagnostics — \(Date()) ===")
        appendLine("FORMAT: [TAG] event note=N vel=V IOI=Xms bpm≈Y seq=Z")
        appendLine("---")
    }

    // MARK: - CoreMIDI thread (Phase 1)

    /// Record a MIDI event on the CoreMIDI thread, before any Task dispatch.
    nonisolated func recordCoremidi(event: MIDIInputEvent) {
        guard isEnabled else { return }

        let note = Int(event.noteNumber)
        let eventNs = hardwareNs(from: event.midiTimestamp) ?? wallClockNs()

        struct NoteOnLog {
            let seq: Int; let ioi: Double; let bpm: Double
            let isDrop: Bool; let gapMs: Double; let dropTotal: Int
        }
        struct NoteOffLog { let heldMs: Double }

        if event.isNoteOn {
            let d: NoteOnLog = stateLock.withLock { state in
                state.coreMidiCount += 1
                let isDrop = state.isOn[note] == true
                var gapMs = 0.0
                var dropTotal = state.dropCount
                if isDrop {
                    state.dropCount += 1
                    dropTotal = state.dropCount
                    gapMs = Double(eventNs - (state.lastNoteOnNs[note] ?? eventNs)) / 1_000_000.0
                }
                let ioi = state.lastAnyNoteOnNs > 0
                    ? Double(eventNs - state.lastAnyNoteOnNs) / 1_000_000.0 : 0.0
                let bpm = ioi > 5 ? 60_000.0 / ioi : 0.0
                state.isOn[note] = true
                state.lastNoteOnNs[note] = eventNs
                state.lastAnyNoteOnNs = eventNs
                return NoteOnLog(seq: state.coreMidiCount, ioi: ioi, bpm: bpm,
                                 isDrop: isDrop, gapMs: gapMs, dropTotal: dropTotal)
            }
            if d.isDrop {
                let msg = "[DROP] note=\(note) gap=\(String(format: "%.1f", d.gapMs))ms drops=\(d.dropTotal)"
                Self.logger.warning("\(msg, privacy: .public)")
                appendLine(msg)
            }
            let ioi = String(format: "%.1f", d.ioi)
            let bpm = String(format: "%.0f", d.bpm)
            let msg = "[MIDI] ON  note=\(note) vel=\(event.velocity) IOI=\(ioi)ms bpm≈\(bpm) seq=\(d.seq)"
            Self.logger.info("\(msg, privacy: .public)")
            appendLine(msg)
        } else {
            let d: NoteOffLog = stateLock.withLock { state in
                state.isOn[note] = false
                let heldMs = Double(eventNs - (state.lastNoteOnNs[note] ?? eventNs)) / 1_000_000.0
                return NoteOffLog(heldMs: heldMs)
            }
            let msg = "[MIDI] OFF note=\(note) held=\(String(format: "%.1f", d.heldMs))ms"
            Self.logger.info("\(msg, privacy: .public)")
            appendLine(msg)
        }
    }

    // MARK: - MainActor (Phase 2)

    /// Record when the MainActor processes a note-on. Measures queue lag.
    nonisolated func recordMainActor(event: MIDIInputEvent) {
        guard isEnabled, event.isNoteOn else { return }

        let note = Int(event.noteNumber)
        let nowNs = wallClockNs()
        let eventWallNs = UInt64(event.timestamp.timeIntervalSince1970 * 1_000_000_000)
        let lagNs = nowNs > eventWallNs ? nowNs - eventWallNs : 0

        struct LogData {
            let lagMs: Double; let avgLagMs: Double; let maxLagMs: Double
            let midiTotal: Int; let mainTotal: Int; let pending: Int
        }

        let d: LogData = stateLock.withLock { state in
            state.mainActorCount += 1
            state.totalLagNs += lagNs
            if lagNs > state.maxLagNs { state.maxLagNs = lagNs }
            let avg = Double(state.totalLagNs) / Double(state.mainActorCount) / 1_000_000.0
            return LogData(
                lagMs: Double(lagNs) / 1_000_000.0, avgLagMs: avg,
                maxLagMs: Double(state.maxLagNs) / 1_000_000.0,
                midiTotal: state.coreMidiCount, mainTotal: state.mainActorCount,
                pending: state.coreMidiCount - state.mainActorCount
            )
        }

        let tag = d.lagMs > 10 ? "[LAG] " : "[MAIN]"
        let lag = String(format: "%.1f", d.lagMs)
        let avg = String(format: "%.1f", d.avgLagMs)
        let max = String(format: "%.1f", d.maxLagMs)
        let msg = "\(tag) ON  note=\(note) lag=\(lag)ms avg=\(avg)ms max=\(max)ms pending=\(d.pending)"
        Self.logger.info("\(msg, privacy: .public)")
        appendLine(msg)
    }

    // MARK: - Summary

    /// Log a session summary to both os.Logger and the file. Call at session end.
    nonisolated func printSummary() {
        guard isEnabled else { return }

        struct SummaryData {
            let coreMidi: Int; let mainActor: Int
            let avgLagMs: Double; let maxLagMs: Double; let drops: Int
        }

        let s: SummaryData = stateLock.withLock { state in
            let avg = state.mainActorCount > 0
                ? Double(state.totalLagNs) / Double(state.mainActorCount) / 1_000_000.0 : 0
            return SummaryData(
                coreMidi: state.coreMidiCount, mainActor: state.mainActorCount,
                avgLagMs: avg, maxLagMs: Double(state.maxLagNs) / 1_000_000.0,
                drops: state.dropCount
            )
        }

        let unprocessed = s.coreMidi - s.mainActor
        let msg = """
            ---
            ══ MIDI Summary ══
            CoreMIDI note-ons : \(s.coreMidi)
            MainActor processed: \(s.mainActor)
            Pending in queue  : \(unprocessed)
            Drops             : \(s.drops)
            Avg MainActor lag : \(String(format: "%.1f", s.avgLagMs))ms
            Max MainActor lag : \(String(format: "%.1f", s.maxLagMs))ms
            ══════════════════
            """
        Self.logger.info("\(msg, privacy: .public)")
        appendLine(msg)
        closeLogFile()
    }

    // MARK: - File helpers

    /// Path of the current log file in the app's Documents directory.
    ///
    /// Uses `NSSearchPathForDirectoriesInDomains` which is safe to call from any thread,
    /// unlike `FileManager.default.urls(for:in:)` which can be main-actor only.
    nonisolated static var logFileURL: URL {
        let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
        let docs = paths.first ?? NSTemporaryDirectory()
        return URL(fileURLWithPath: docs).appendingPathComponent("midi_diag.log")
    }

    nonisolated private func openLogFile() {
        let url = Self.logFileURL
        // Ensure the Documents directory exists
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Overwrite previous session
        do {
            try "".write(to: url, atomically: true, encoding: .utf8)
            fileHandle = try FileHandle(forWritingTo: url)
            fileHandle?.seekToEndOfFile()
            Self.logger.info("[DIAG] Log file opened at \(url.path, privacy: .private)")
        } catch {
            Self.logger.error(
                """
                [DIAG] Failed to open log file: \
                \(error.localizedDescription, privacy: .public) \
                path=\(url.path, privacy: .private)
                """
            )
        }
    }

    nonisolated private func closeLogFile() {
        try? fileHandle?.close()
        fileHandle = nil
    }

    /// Append a line to the log file. Thread-safe via fileLock.
    nonisolated private func appendLine(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        fileLock.withLock { _ in
            fileHandle?.write(data)
        }
    }

    // MARK: - Timing helpers

    nonisolated private func wallClockNs() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1_000_000_000)
    }

    nonisolated private func hardwareNs(from midiTimestamp: MIDITimeStamp?) -> UInt64? {
        guard let ts = midiTimestamp, ts > 0 else { return nil }
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return ts * UInt64(tb.numer) / UInt64(tb.denom)
    }
}
