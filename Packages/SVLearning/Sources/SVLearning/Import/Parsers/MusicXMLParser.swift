import Foundation
import os

private let musicXMLLogger = Logger.survibe(category: "MusicXMLParser")

/// Parses MusicXML documents into a `ParsedNotation` using Foundation's `XMLParser`.
///
/// Extracts note pitch (step + octave), duration type, and accidentals from
/// `<note>`, `<pitch>`, `<step>`, `<octave>`, `<alter>`, `<type>`, and `<rest>` elements.
/// Handles `<score-partwise>` and `<score-timewise>` root elements.
/// Only the first `<part>` is parsed (multi-part support is deferred to Phase 2).
///
/// No external dependencies — uses Foundation's built-in SAX-style `XMLParser`.
public struct MusicXMLParser: NotationParserProtocol {

    public let supportedFormat: NotationInput.Format = .musicXML

    public init() {}

    // MARK: - NotationParserProtocol

    /// Parses a MusicXML text document into a structured `ParsedNotation`.
    ///
    /// - Parameter input: Raw MusicXML text input.
    /// - Returns: Parsed notation extracted from the first part of the score.
    /// - Throws: `ImportError.emptyInput` if text is blank.
    ///           `ImportError.parsingFailed` if XML is malformed or contains no notes.
    public func parse(_ input: NotationInput) throws -> ParsedNotation {
        let trimmed = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyInput }

        guard let data = trimmed.data(using: .utf8) else {
            musicXMLLogger.error("Could not encode MusicXML as UTF-8")
            throw ImportError.parsingFailed("Could not encode MusicXML as UTF-8.")
        }

        let delegate = MusicXMLParserDelegate()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = delegate
        let success = xmlParser.parse()

        if !success, let error = xmlParser.parserError {
            musicXMLLogger.error("XML parse error: \(error.localizedDescription, privacy: .public)")
            throw ImportError.parsingFailed("XML parse error: \(error.localizedDescription)")
        }

        guard !delegate.notes.isEmpty else {
            musicXMLLogger.error("No notes found in MusicXML document")
            throw ImportError.parsingFailed("No notes found in MusicXML document.")
        }

        musicXMLLogger.info(
            "MusicXML parse complete: \(delegate.notes.count, privacy: .public) notes extracted"
        )

        return ParsedNotation(
            format: .musicXML,
            notes: delegate.notes,
            tempo: delegate.tempo ?? 120,
            keySignature: delegate.keySignature,
            timeSignature: delegate.timeSignature
        )
    }
}

// MARK: - MusicXMLParserDelegate

/// SAX-style delegate for Foundation's XMLParser.
///
/// Marked `@unchecked Sendable` because it is created, used, and discarded
/// entirely within a single synchronous `XMLParser.parse()` call on the
/// calling thread. It is never shared across threads or stored beyond the
/// scope of `MusicXMLParser.parse(_:)`.
private final class MusicXMLParserDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {

    // MARK: - Parsed Output

    var notes: [ParsedNotation.Note] = []
    var tempo: Int?
    var keySignature: String = ""
    var timeSignature: String = "4/4"

    // MARK: - Parser State

    private var currentElement: String = ""
    private var currentText: String = ""

    // Current note being assembled
    private var currentStep: String?
    private var currentOctave: Int?
    private var currentAlter: Double?
    private var currentDurationType: String?
    private var currentIsRest: Bool = false

    // Key/time signature state
    private var currentFifths: Int?
    private var currentMode: String?
    private var currentBeats: String?
    private var currentBeatType: String?

    private var noteIndex: Int = 0
    private var insideNote: Bool = false
    private var insidePitch: Bool = false
    private var insideKey: Bool = false
    private var insideTime: Bool = false

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "note":
            insideNote = true
            currentStep = nil
            currentOctave = nil
            currentAlter = nil
            currentDurationType = nil
            currentIsRest = false
        case "pitch":
            insidePitch = true
        case "rest":
            currentIsRest = true
        case "key":
            insideKey = true
        case "time":
            insideTime = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        let value = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        handleEndElement(elementName, value: value)
        currentText = ""
    }

    /// Routes end-element events to focused handler methods to keep cyclomatic complexity low.
    private func handleEndElement(_ elementName: String, value: String) {
        switch elementName {
        case "step", "octave", "alter", "type":
            handlePitchAndNoteFields(elementName, value: value)
        case "pitch":
            insidePitch = false
        case "fifths", "mode", "beats", "beat-type":
            handleKeyTimeFields(elementName, value: value)
        case "key":
            handleKeyEnd()
        case "time":
            handleTimeEnd()
        case "note":
            handleNoteEnd()
        default:
            break
        }
    }

    /// Handles pitch-level and note-level scalar fields.
    private func handlePitchAndNoteFields(_ elementName: String, value: String) {
        switch elementName {
        case "step":
            if insidePitch { currentStep = value }
        case "octave":
            if insidePitch { currentOctave = Int(value) }
        case "alter":
            if insidePitch { currentAlter = Double(value) }
        case "type":
            if insideNote { currentDurationType = value }
        default:
            break
        }
    }

    /// Handles key and time signature scalar fields.
    private func handleKeyTimeFields(_ elementName: String, value: String) {
        switch elementName {
        case "fifths":
            if insideKey { currentFifths = Int(value) }
        case "mode":
            if insideKey { currentMode = value }
        case "beats":
            if insideTime { currentBeats = value }
        case "beat-type":
            if insideTime { currentBeatType = value }
        default:
            break
        }
    }

    /// Finalises the key signature when the </key> element closes.
    private func handleKeyEnd() {
        insideKey = false
        keySignature = buildKeySignature(fifths: currentFifths ?? 0, mode: currentMode ?? "major")
        currentFifths = nil
        currentMode = nil
    }

    /// Finalises the time signature when the </time> element closes.
    private func handleTimeEnd() {
        insideTime = false
        if let beats = currentBeats, let beatType = currentBeatType {
            timeSignature = "\(beats)/\(beatType)"
        }
        currentBeats = nil
        currentBeatType = nil
    }

    /// Builds and appends a note when the </note> element closes.
    private func handleNoteEnd() {
        insideNote = false
        guard !currentIsRest, let step = currentStep else { return }
        let accidental = accidentalString(for: currentAlter)
        let name = step + accidental
        let modifier: String? = accidental.isEmpty ? nil : (accidental == "#" ? "sharp" : "flat")
        let note = ParsedNotation.Note(
            name: name,
            octave: currentOctave,
            durationBeats: durationBeats(for: currentDurationType),
            modifier: modifier,
            index: noteIndex
        )
        notes.append(note)
        noteIndex += 1
    }

    // MARK: - Helpers

    /// Converts MusicXML alter value to accidental string.
    private func accidentalString(for alter: Double?) -> String {
        guard let alter else { return "" }
        if alter >= 0.5 { return "#" }
        if alter <= -0.5 { return "b" }
        return ""
    }

    /// Maps MusicXML duration type strings to beat counts.
    private func durationBeats(for type: String?) -> Double? {
        switch type {
        case "whole": return 4.0
        case "half": return 2.0
        case "quarter": return 1.0
        case "eighth": return 0.5
        case "16th": return 0.25
        case "32nd": return 0.125
        default: return nil
        }
    }

    /// Builds a human-readable key signature from fifths and mode.
    private func buildKeySignature(fifths: Int, mode: String) -> String {
        let majorKeys = ["C", "G", "D", "A", "E", "B", "F#", "C#"]
        let flatKeys  = ["C", "F", "Bb", "Eb", "Ab", "Db", "Gb", "Cb"]
        let keyName: String
        if fifths >= 0, fifths < majorKeys.count {
            keyName = majorKeys[fifths]
        } else if fifths < 0, abs(fifths) < flatKeys.count {
            keyName = flatKeys[abs(fifths)]
        } else {
            keyName = "C"
        }
        return "\(keyName) \(mode)"
    }
}
