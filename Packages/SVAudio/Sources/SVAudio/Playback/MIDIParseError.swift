import Foundation
import SVCore

/// Errors that can occur during Standard MIDI File parsing.
///
/// Each case provides a user-readable description via `LocalizedError`
/// conformance, suitable for display in error UI or logging.
public enum MIDIParseError: SurVibeError {
    /// The data does not begin with the "MThd" header magic bytes.
    case invalidHeader

    /// The MIDI data is structurally corrupt (unexpected EOF, invalid chunks).
    case corruptedData

    /// The file parsed successfully but contains no note events.
    case noNotesFound

    /// The MIDI file uses format 2 (independent patterns), which is not supported.
    case unsupportedFormat

    public var domain: String { "SVAudio" }

    public var code: String {
        switch self {
        case .invalidHeader: "invalid_header"
        case .corruptedData: "corrupted_data"
        case .noNotesFound: "no_notes_found"
        case .unsupportedFormat: "unsupported_format"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidHeader:
            String(localized: "Invalid MIDI file header — expected MThd magic bytes", bundle: .module)
        case .corruptedData:
            String(localized: "Corrupted MIDI data — unexpected end of file or invalid chunk", bundle: .module)
        case .noNotesFound:
            String(localized: "No note events found in the MIDI file", bundle: .module)
        case .unsupportedFormat:
            String(localized: "MIDI format 2 (independent patterns) is not supported", bundle: .module)
        }
    }
}
