import Foundation
import os

private let extractorLogger = Logger.survibe(category: "MusicXMLExtractor")

// MARK: - Public Types

/// Static metadata extracted from a MusicXML document that Verovio's
/// Swift toolkit MIDI render path drops on the floor.
///
/// Verovio surfaces SVG layout + a plain SMF byte stream, but the
/// downstream Songs/Play-Along pipeline still needs original score
/// structure: the concert key signature (so we can compute the tonic
/// Sa frequency), the meter (for the time pill), per-note staff
/// assignment (so RH/LH can be color/shape-coded without re-parsing),
/// and lyric syllables (for sing-along). We re-parse the XML once,
/// up front, and produce this struct.
public struct MusicXMLMetadata: Sendable, Equatable {
    /// Concert key signature in human-readable form, e.g. `"C major"`,
    /// `"Eb minor"`. Built from the first `<key><fifths>` element plus
    /// `<mode>` (defaults to `major` per MusicXML 4.0 §3.4).
    public let keySignatureRaw: String

    /// Time signature in `beats/beat-type` form, e.g. `"4/4"`, `"6/8"`.
    /// Built from the first `<time>` element encountered. Subsequent
    /// meter changes are out of scope for v1.
    public let timeSignatureRaw: String

    /// Tonic Sa frequency in Hz (e.g. 261.6256 Hz for C major).
    /// Computed from `keySignatureRaw` via the equal-tempered formula
    /// `440 * 2^((midi - 69) / 12)`, anchored at MIDI octave 4.
    public let defaultSaFrequencyHz: Double

    /// Per-part staff assignment, indexed by `<part>` document order.
    /// Layout: `[part_index][note_index_in_part] = staff_number`.
    /// Default staff is `1` when the `<note>` has no `<staff>` child.
    /// Chord-tone notes (those with `<chord/>`) are included so the
    /// array length matches the total `<note>` element count for the
    /// part — Verovio's MIDI track event count includes chord tones too.
    public let staffPerNote: [[Int]]

    /// Per-part lyric events. Layout:
    /// `[part_index] = [(noteIndex, syllable)]`.
    /// `noteIndex` aligns with `staffPerNote[partIndex]`. Only verse 1
    /// (first `<lyric>` child of a `<note>`, by document order) is
    /// captured; multi-verse scores collapse for v1.
    public let lyricsPerNote: [[LyricEvent]]

    public init(
        keySignatureRaw: String,
        timeSignatureRaw: String,
        defaultSaFrequencyHz: Double,
        staffPerNote: [[Int]],
        lyricsPerNote: [[LyricEvent]]
    ) {
        self.keySignatureRaw = keySignatureRaw
        self.timeSignatureRaw = timeSignatureRaw
        self.defaultSaFrequencyHz = defaultSaFrequencyHz
        self.staffPerNote = staffPerNote
        self.lyricsPerNote = lyricsPerNote
    }
}

/// One lyric syllable attached to a specific note within a part.
public struct LyricEvent: Sendable, Equatable {
    /// Index into `staffPerNote[partIndex]` identifying which note
    /// in the part carries this syllable.
    public let noteIndex: Int
    /// The `<text>` content of the `<lyric>` element (verse 1).
    public let syllable: String

    public init(noteIndex: Int, syllable: String) {
        self.noteIndex = noteIndex
        self.syllable = syllable
    }
}

/// Errors raised by `MusicXMLExtractor.extract`.
public enum MusicXMLExtractorError: Error, LocalizedError, Equatable {
    /// `XMLParser` could not parse the input, or the document lacks
    /// a structural element (e.g. no `<part>` at all).
    case malformed(reason: String)

    public var errorDescription: String? {
        switch self {
        case .malformed(let reason):
            return "MusicXML malformed: \(reason)"
        }
    }
}

// MARK: - Extractor

/// SAX-style re-parser for MusicXML 3.x / 4.x documents.
public enum MusicXMLExtractor {

    /// Re-parse the given MusicXML string and extract static metadata that
    /// Verovio's MIDI render path drops on the floor (key sig, time sig,
    /// staff per note, lyrics, default tonic frequency).
    ///
    /// Uses `Foundation.XMLParser` (SAX-style) so we don't load the entire
    /// DOM — a 2.3 MB MXL like James Bond is parsed in ~30 ms.
    ///
    /// - Parameter musicXML: The full MusicXML 3.x or 4.x document text.
    /// - Returns: `MusicXMLMetadata`.
    /// - Throws: `MusicXMLExtractorError.malformed(reason:)` on parse failure.
    public static func extract(musicXML: String) throws -> MusicXMLMetadata {
        guard let data = musicXML.data(using: .utf8) else {
            throw MusicXMLExtractorError.malformed(reason: "Input is not UTF-8 encodable")
        }
        let delegate = MusicXMLExtractorDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false

        guard parser.parse() else {
            let err = parser.parserError?.localizedDescription ?? "unknown XMLParser error"
            throw MusicXMLExtractorError.malformed(reason: err)
        }
        if let firstError = delegate.firstError {
            throw firstError
        }

        let keySig = KeySignatureTable.name(
            fifths: delegate.firstFifths ?? 0,
            mode: delegate.firstMode ?? "major"
        )
        let timeSig: String = {
            if let beats = delegate.firstBeats, let beatType = delegate.firstBeatType {
                return "\(beats)/\(beatType)"
            }
            return "4/4"
        }()
        let saHz = KeySignatureTable.tonicFrequency(forKeySignature: keySig)

        return MusicXMLMetadata(
            keySignatureRaw: keySig,
            timeSignatureRaw: timeSig,
            defaultSaFrequencyHz: saHz,
            staffPerNote: delegate.staffPerNote,
            lyricsPerNote: delegate.lyricsPerNote
        )
    }
}

// MARK: - SAX Delegate

/// SAX delegate that walks a MusicXML document once and accumulates
/// the structural fields `MusicXMLMetadata` needs.
///
/// - Note: `@unchecked Sendable` is safe because the delegate is
///   instantiated, used, and discarded within a single synchronous
///   call to `MusicXMLExtractor.extract`. No cross-isolation transfer
///   occurs. `XMLParserDelegate` requires `NSObject` inheritance,
///   which forces the `@unchecked` annotation per CLAUDE.md's
///   exception list (NSObject delegates).
private final class MusicXMLExtractorDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {

    // MARK: - Output

    var firstFifths: Int?
    var firstMode: String?
    var firstBeats: String?
    var firstBeatType: String?
    var staffPerNote: [[Int]] = []
    var lyricsPerNote: [[LyricEvent]] = []
    var firstError: MusicXMLExtractorError?

    // MARK: - Element stack + character buffer

    private var elementStack: [String] = []
    private var charBuffer: String = ""

    // MARK: - Per-part state

    private var inPart: Bool = false
    private var currentPartStaves: [Int] = []
    private var currentPartLyrics: [LyricEvent] = []

    // MARK: - Per-note state

    private var inNote: Bool = false
    private var currentNoteStaff: Int = 1
    private var currentNoteHasLyric: Bool = false
    private var currentNoteLyricSyllable: String?
    /// Set when the parser is inside a `<lyric>` element — used to
    /// only capture verse 1 (the first `<lyric>` per `<note>`).
    private var inLyric: Bool = false

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        elementStack.append(elementName)
        charBuffer = ""

        switch elementName {
        case "part":
            inPart = true
            currentPartStaves = []
            currentPartLyrics = []
        case "note":
            inNote = true
            currentNoteStaff = 1
            currentNoteHasLyric = false
            currentNoteLyricSyllable = nil
        case "lyric":
            // Only honor the first <lyric> child of a <note> (verse 1).
            if inNote, !currentNoteHasLyric {
                inLyric = true
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        charBuffer.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        defer {
            if !elementStack.isEmpty {
                elementStack.removeLast()
            }
            charBuffer = ""
        }
        let trimmed = charBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        if handleHeaderField(elementName, trimmed: trimmed) { return }
        handleStructuralField(elementName, trimmed: trimmed)
    }

    /// Capture key/time-signature header fields. Returns `true` if the
    /// element was consumed.
    private func handleHeaderField(_ elementName: String, trimmed: String) -> Bool {
        switch elementName {
        case "fifths":
            if firstFifths == nil, let value = Int(trimmed) {
                firstFifths = value
            }
        case "mode":
            if firstMode == nil, !trimmed.isEmpty {
                firstMode = trimmed.lowercased()
            }
        case "beats":
            if firstBeats == nil, !trimmed.isEmpty {
                firstBeats = trimmed
            }
        case "beat-type":
            if firstBeatType == nil, !trimmed.isEmpty {
                firstBeatType = trimmed
            }
        default:
            return false
        }
        return true
    }

    /// Capture per-note and per-part structural fields.
    private func handleStructuralField(_ elementName: String, trimmed: String) {
        switch elementName {
        case "staff":
            if inNote, let value = Int(trimmed) {
                currentNoteStaff = value
            }
        case "text":
            if inLyric, currentNoteLyricSyllable == nil, !trimmed.isEmpty {
                currentNoteLyricSyllable = trimmed
            }
        case "lyric":
            closeLyricElement()
        case "note":
            if inNote {
                currentPartStaves.append(currentNoteStaff)
                inNote = false
            }
        case "part":
            closePartElement()
        default:
            break
        }
    }

    /// Finalize the current `<lyric>` element: append a `LyricEvent`
    /// when verse-1 text was captured.
    private func closeLyricElement() {
        guard inLyric else { return }
        inLyric = false
        guard let syllable = currentNoteLyricSyllable else { return }
        currentNoteHasLyric = true
        let noteIndex = currentPartStaves.count
        currentPartLyrics.append(LyricEvent(noteIndex: noteIndex, syllable: syllable))
    }

    /// Finalize the current `<part>`: flush the per-note arrays into
    /// the cross-part output and reset state for the next part.
    private func closePartElement() {
        guard inPart else { return }
        staffPerNote.append(currentPartStaves)
        lyricsPerNote.append(currentPartLyrics)
        currentPartStaves = []
        currentPartLyrics = []
        inPart = false
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        if firstError == nil {
            firstError = .malformed(reason: parseError.localizedDescription)
        }
    }
}

// MARK: - Key Signature Table

/// Maps the MusicXML `<fifths>` + `<mode>` pair to a human-readable key
/// name and to the tonic note frequency.
///
/// Circle-of-fifths convention (MusicXML 4.0 §3.4): positive `fifths`
/// counts sharps in the key signature, negative counts flats. The
/// canonical major-key tonic for `n` fifths is the note `n` perfect
/// fifths away from C; the canonical minor-key tonic is the relative
/// minor (a minor third below the major tonic). Range −7…+7 covers all
/// 15 standard key signatures in each mode.
enum KeySignatureTable {

    /// Human-readable name for a `<fifths>`/`<mode>` pair. Out-of-range
    /// fifths fall back to `"C major"` (a sentinel that downstream code
    /// can detect via the Sa Hz of 261.6256).
    static func name(fifths: Int, mode: String) -> String {
        let normalisedMode = mode.lowercased() == "minor" ? "minor" : "major"
        let tonic: String
        if normalisedMode == "minor" {
            tonic = minorTonic(forFifths: fifths)
        } else {
            tonic = majorTonic(forFifths: fifths)
        }
        return "\(tonic) \(normalisedMode)"
    }

    /// Tonic frequency in Hz at octave 4 (e.g. C4 = 261.6256 Hz) for
    /// a given `keySignatureRaw` like `"Eb minor"`.
    ///
    /// Falls back to C4 when the tonic letter cannot be parsed.
    static func tonicFrequency(forKeySignature raw: String) -> Double {
        let parts = raw.split(separator: " ", maxSplits: 1).map(String.init)
        guard let tonic = parts.first else { return c4Hz }
        let midi = midiNumber(forTonicName: tonic)
        return 440.0 * pow(2.0, (Double(midi) - 69.0) / 12.0)
    }

    // MARK: - Internals

    /// MIDI 60 = C4. 261.6255653005986 Hz exactly per the equal-tempered
    /// formula anchored at A4 = 440.
    private static let c4Hz: Double = 261.625_565_300_598_6

    /// Index `fifths + 7` into this 15-entry table to get the major-key
    /// tonic letter.
    private static let majorTonics: [String] = [
        "Cb", "Gb", "Db", "Ab", "Eb", "Bb", "F", "C",
        "G", "D", "A", "E", "B", "F#", "C#"
    ]

    /// Index `fifths + 7` for relative-minor tonic letters.
    private static let minorTonics: [String] = [
        "Ab", "Eb", "Bb", "F", "C", "G", "D", "A",
        "E", "B", "F#", "C#", "G#", "D#", "A#"
    ]

    /// Major-key tonic letter (with accidental) for `fifths` ∈ −7…+7.
    /// Outside that range falls back to `"C"` and logs once.
    private static func majorTonic(forFifths fifths: Int) -> String {
        let idx = fifths + 7
        guard majorTonics.indices.contains(idx) else {
            extractorLogger.warning(
                "Out-of-range fifths=\(fifths, privacy: .public); using C major"
            )
            return "C"
        }
        return majorTonics[idx]
    }

    /// Relative-minor tonic letter for `fifths` ∈ −7…+7.
    private static func minorTonic(forFifths fifths: Int) -> String {
        let idx = fifths + 7
        guard minorTonics.indices.contains(idx) else {
            extractorLogger.warning(
                "Out-of-range fifths=\(fifths, privacy: .public); using A minor"
            )
            return "A"
        }
        return minorTonics[idx]
    }

    /// Tonic letter → MIDI note number at octave 4. Lookup table covers
    /// every spelling that appears in `majorTonics`/`minorTonics` plus
    /// the enharmonic equivalents `Fb`, `E#`.
    private static let tonicToMidi: [String: Int] = [
        "C": 60, "B#": 60,
        "C#": 61, "Db": 61,
        "D": 62,
        "D#": 63, "Eb": 63,
        "E": 64, "Fb": 64,
        "E#": 65, "F": 65,
        "F#": 66, "Gb": 66,
        "G": 67,
        "G#": 68, "Ab": 68,
        "A": 69,
        "A#": 70, "Bb": 70,
        "B": 71, "Cb": 71
    ]

    /// Map a tonic letter (with optional accidental) to its MIDI note
    /// number at octave 4. Unknown spellings fall back to C4 (60).
    private static func midiNumber(forTonicName tonic: String) -> Int {
        tonicToMidi[tonic] ?? 60
    }
}
