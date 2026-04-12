import Foundation
import os

private let westernParserLogger = Logger.survibe(category: "WesternParser")

/// Parses Western notation text into a `ParsedNotation`.
///
/// Accepts note tokens in the form `<Letter>[Accidental][Octave][Duration]`
/// where:
/// - Letter: A–G (case-insensitive)
/// - Accidental: `#` (sharp) or `b` (flat), optional
/// - Octave: digit 0–9, optional (defaults inferred by normaliser)
/// - Duration: `w` whole, `h` half, `q` quarter (default), `e` eighth, `s` sixteenth, optional
///
/// ## Input format examples
/// ```
/// C4 D4 E4 F4 G4 A4 B4 C5
/// C4q D4q E4h F4w
/// C#4 Db4 F#3 Bb5
/// ```
public struct WesternNotationParser: NotationParserProtocol {

    public let supportedFormat: NotationInput.Format = .western

    public init() {}

    // MARK: - NotationParserProtocol

    /// Parses western notation text into a structured `ParsedNotation`.
    ///
    /// - Parameter input: Raw western notation input.
    /// - Returns: Parsed notation with note sequence.
    /// - Throws: `ImportError.emptyInput` if text is blank.
    ///           `ImportError.parsingFailed` if no western notes are found.
    public func parse(_ input: NotationInput) throws -> ParsedNotation {
        let trimmed = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyInput }

        let tokens = tokenise(trimmed)
        guard !tokens.isEmpty else {
            throw ImportError.parsingFailed("No tokens found in western input.")
        }

        var notes: [ParsedNotation.Note] = []
        var noteIndex = 0

        // Detect key signature from header line if present (e.g. "Key: C major")
        var keySignature = ""
        let lines = trimmed.components(separatedBy: .newlines)
        for line in lines {
            let lower = line.lowercased()
            if lower.hasPrefix("key:") {
                keySignature = line.dropFirst(4).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        for token in tokens {
            if let note = parseToken(token, index: noteIndex) {
                notes.append(note)
                noteIndex += 1
            }
        }

        guard !notes.isEmpty else {
            throw ImportError.parsingFailed("Could not extract any western notes from input.")
        }

        westernParserLogger.info(
            "Western parse complete: \(notes.count, privacy: .public) notes extracted"
        )

        return ParsedNotation(
            format: .western,
            notes: notes,
            keySignature: keySignature
        )
    }

    // MARK: - Private Tokenisation

    private func tokenise(_ text: String) -> [String] {
        text
            .components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: ",")))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Parses a single western note token.
    ///
    /// Pattern: `[A-Ga-g][#b]?[0-9]?[whqes]?`
    /// Returns nil for unrecognised tokens.
    private func parseToken(_ token: String, index: Int) -> ParsedNotation.Note? {
        var pos = token.startIndex

        // 1. Letter (required)
        guard pos < token.endIndex else { return nil }
        let letter = token[pos]
        guard "AaBbCcDdEeFfGg".contains(letter) else { return nil }
        let noteLetter = String(letter).uppercased()
        pos = token.index(after: pos)

        // 2. Accidental (optional: # or b)
        let (accidental, posAfterAccidental) = parseAccidental(
            token: token, pos: pos, noteLetter: noteLetter
        )
        pos = posAfterAccidental

        // 3. Octave (optional: 0-9)
        var octave: Int?
        if pos < token.endIndex, let digit = token[pos].wholeNumberValue {
            octave = digit
            pos = token.index(after: pos)
        }

        // 4. Duration (optional: w h q e s)
        let durationBeats = parseDuration(token: token, pos: pos)

        let name = noteLetter + accidental
        let modifier = accidental.isEmpty ? nil : (accidental == "#" ? "sharp" : "flat")

        return ParsedNotation.Note(
            name: name,
            octave: octave,
            durationBeats: durationBeats,
            modifier: modifier,
            index: index
        )
    }

    /// Extract an accidental character (# or b) from the token at the given position.
    private func parseAccidental(
        token: String, pos: String.Index, noteLetter: String
    ) -> (String, String.Index) {
        guard pos < token.endIndex else { return ("", pos) }
        if token[pos] == "#" {
            return ("#", token.index(after: pos))
        }
        if token[pos] == "b",
           "ACDFG".contains(noteLetter) || noteLetter == "B" || noteLetter == "E" {
            return ("b", token.index(after: pos))
        }
        return ("", pos)
    }

    /// Map a duration character (w/h/q/e/s) to beat value.
    private func parseDuration(token: String, pos: String.Index) -> Double? {
        guard pos < token.endIndex else { return nil }
        switch token[pos] {
        case "w": return 4.0
        case "h": return 2.0
        case "q": return 1.0
        case "e": return 0.5
        case "s": return 0.25
        default: return nil
        }
    }
}
