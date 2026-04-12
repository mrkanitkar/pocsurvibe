import Foundation
import os

private let sargamParserLogger = Logger.survibe(category: "SargamParser")

/// Parses Indian sargam notation text into a `ParsedNotation`.
///
/// Supports both English transliteration (Sa Re Ga Ma Pa Dha Ni) and
/// Devanagari (सा रे ग म प ध नि). Handles komal/tivra modifiers,
/// octave markers (', '' for upper; . for lower), and duration hints (-)
/// for sustain notes.
///
/// ## Input format examples
/// ```
/// Sa Re Ga Ma Pa Dha Ni Sa
/// Sa' Re' Ga' Ma   (upper octave with apostrophe)
/// Sa Komal.Re Ga Ma   (komal modifier)
/// Sa - - Re Ga   (dash = sustain previous note duration)
/// ```
public struct SargamNotationParser: NotationParserProtocol {

    public let supportedFormat: NotationInput.Format = .sargam

    public init() {}

    // MARK: - NotationParserProtocol

    /// Parses sargam notation text into a structured `ParsedNotation`.
    ///
    /// - Parameter input: Raw sargam notation input.
    /// - Returns: Parsed notation with note sequence.
    /// - Throws: `ImportError.emptyInput` if text is blank.
    ///           `ImportError.parsingFailed` if no sargam notes are found.
    public func parse(_ input: NotationInput) throws -> ParsedNotation {
        let trimmed = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            sargamParserLogger.warning("Sargam parse called with empty input")
            throw ImportError.emptyInput
        }

        let tokens = tokenise(trimmed)
        guard !tokens.isEmpty else {
            sargamParserLogger.warning("No tokens found in sargam input")
            throw ImportError.parsingFailed("No tokens found in sargam input.")
        }

        var notes: [ParsedNotation.Note] = []
        var noteIndex = 0

        for token in tokens {
            if let note = parseToken(token, index: noteIndex) {
                notes.append(note)
                noteIndex += 1
            }
            // Sustain dashes (-) are skipped — they extend the previous note's duration
            // but we defer duration inference to NotationNormalizer
        }

        guard !notes.isEmpty else {
            sargamParserLogger.warning("Could not extract any sargam notes from input")
            throw ImportError.parsingFailed("Could not extract any sargam notes from input.")
        }

        sargamParserLogger.info(
            "Sargam parse complete: \(tokens.count, privacy: .public) tokens, \(notes.count, privacy: .public) notes"
        )

        return ParsedNotation(format: .sargam, notes: notes)
    }

    // MARK: - Private Tokenisation

    /// Splits input text into individual tokens separated by whitespace or commas.
    private func tokenise(_ text: String) -> [String] {
        // Normalize Devanagari to transliteration before splitting
        let normalised = devanagariToTransliteration(text)
        return normalised
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: ",")))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "-" }
    }

    /// Attempts to parse a single token into a `ParsedNotation.Note`.
    ///
    /// Returns nil for unrecognised tokens (e.g. bar lines, punctuation).
    private func parseToken(_ token: String, index: Int) -> ParsedNotation.Note? {
        var remaining = token
        var modifier: String?
        var octave: Int?

        // Extract komal/tivra prefix (case-insensitive)
        let lowerToken = remaining.lowercased()
        if lowerToken.hasPrefix("komal") || lowerToken.hasPrefix("k.") {
            modifier = "komal"
            remaining = remaining.dropFirst(lowerToken.hasPrefix("komal") ? 5 : 2).trimmingCharacters(in: .whitespaces)
        } else if lowerToken.hasPrefix("tivra") || lowerToken.hasPrefix("t.") {
            modifier = "tivra"
            remaining = remaining.dropFirst(lowerToken.hasPrefix("tivra") ? 5 : 2).trimmingCharacters(in: .whitespaces)
        }

        // Extract octave markers: '' = octave+2, ' = octave+1, . = octave-1
        if remaining.hasSuffix("''") {
            octave = 6
            remaining = String(remaining.dropLast(2))
        } else if remaining.hasSuffix("'") {
            octave = 5
            remaining = String(remaining.dropLast(1))
        } else if remaining.hasSuffix(".") {
            octave = 3
            remaining = String(remaining.dropLast(1))
        }

        // Match the note name (case-insensitive)
        let noteName = matchSargamNote(remaining)
        guard let name = noteName else { return nil }

        return ParsedNotation.Note(
            name: name,
            octave: octave,        // nil = normaliser will infer middle octave (4)
            durationBeats: nil,    // nil = normaliser will infer 1 beat
            modifier: modifier,
            index: index
        )
    }

    /// Returns the canonical sargam note name if the token matches, else nil.
    private func matchSargamNote(_ token: String) -> String? {
        let canonical: [String: String] = [
            "sa": "Sa", "re": "Re", "ga": "Ga", "ma": "Ma",
            "pa": "Pa", "dha": "Dha", "ni": "Ni",
        ]
        return canonical[token.lowercased()]
    }

    /// Converts common Devanagari sargam characters to English transliteration.
    private func devanagariToTransliteration(_ text: String) -> String {
        let map: [(String, String)] = [
            ("सा", "Sa"), ("रे", "Re"), ("ग", "Ga"), ("म", "Ma"),
            ("प", "Pa"), ("ध", "Dha"), ("नि", "Ni"),
            // Short forms
            ("स", "Sa"), ("र", "Re"),
        ]
        var result = text
        for (devanagari, latin) in map {
            result = result.replacingOccurrences(of: devanagari, with: latin)
        }
        return result
    }
}
