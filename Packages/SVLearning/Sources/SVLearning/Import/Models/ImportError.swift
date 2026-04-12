import Foundation
import SVCore

/// Errors thrown by the import pipeline.
public enum ImportError: SurVibeError {
    /// The input text is empty or contains only whitespace.
    case emptyInput
    /// The format could not be detected from the input.
    case unrecognisedFormat
    /// The parser failed to extract any notes from the input.
    case parsingFailed(String)
    /// Normalisation produced zero valid notes.
    case normalisationFailed
    /// MIDI synthesis failed.
    case midiSynthesisFailed(String)
    /// File size exceeds the 5MB limit.
    case fileTooLarge(Int)
    /// A required metadata field (title, artist) is missing.
    case missingMetadata(String)

    public var domain: String { "SVLearning" }

    public var code: String {
        switch self {
        case .emptyInput: "empty_input"
        case .unrecognisedFormat: "unrecognised_format"
        case .parsingFailed: "parsing_failed"
        case .normalisationFailed: "normalisation_failed"
        case .midiSynthesisFailed: "midi_synthesis_failed"
        case .fileTooLarge: "file_too_large"
        case .missingMetadata: "missing_metadata"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .emptyInput:
            return String(localized: "The notation input is empty.")
        case .unrecognisedFormat:
            return String(
                localized:
                    "Could not detect the notation format. Try selecting a format manually."
            )
        case .parsingFailed(let detail):
            return String(localized: "Parsing failed: \(detail)")
        case .normalisationFailed:
            return String(localized: "No valid notes were found after normalisation.")
        case .midiSynthesisFailed(let detail):
            return String(localized: "MIDI synthesis failed: \(detail)")
        case .fileTooLarge(let bytes):
            let mb = Double(bytes) / 1_048_576
            return String(format: "File is too large (%.1f MB). Maximum is 5 MB.", mb)
        case .missingMetadata(let field):
            return String(localized: "Required field '\(field)' is missing.")
        }
    }
}
