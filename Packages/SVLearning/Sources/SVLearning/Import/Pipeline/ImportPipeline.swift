import Foundation
import os

private let pipelineLogger = Logger.survibe(category: "ImportPipeline")

/// Orchestrates the full 5-stage song import pipeline.
///
/// ## Pipeline stages
/// 1. **Format Detection** -- Identifies the notation format automatically.
/// 2. **Parsing** -- Delegates to the appropriate format-specific parser.
/// 3. **Normalisation** -- Fills in missing octave and duration values.
/// 4. **Validation** -- Generates smart warnings; emits `.warningsGenerated` if any exist.
/// 5. **MIDI Synthesis** -- Generates MIDI binary data from the normalised notation.
///
/// Results are streamed via `AsyncStream<ImportPipelineResult>`. The caller
/// receives progress updates, optional warnings, and finally either
/// `.completed(ImportedSongDTO)` or `.failed(ImportError)`.
///
/// ## Usage
/// ```swift
/// let pipeline = ImportPipeline()
/// let config = ImportConfiguration(title: "Raag Yaman", artist: "", language: "hi", difficulty: 3, category: "classical")
/// for await result in pipeline.run(input: input, configuration: config) {
///     switch result {
///     case .progress(let update): updateProgressBar(update.fraction)
///     case .warningsGenerated(let warnings): showWarningsUI(warnings)
///     case .completed(let dto): saveToSwiftData(dto)
///     case .failed(let error): showError(error)
///     }
/// }
/// ```
public struct ImportPipeline: ImportPipelineProtocol {

    private let formatDetector: FormatDetector
    private let sargamParser: SargamNotationParser
    private let westernParser: WesternNotationParser
    private let musicXMLParser: MusicXMLParser
    private let normalizer: NotationNormalizer
    private let validator: ImportValidator
    private let midiSynthesizer: ImportMIDISynthesizer

    /// Creates a pipeline with default implementations of all stages.
    public init() {
        self.formatDetector = FormatDetector()
        self.sargamParser = SargamNotationParser()
        self.westernParser = WesternNotationParser()
        self.musicXMLParser = MusicXMLParser()
        self.normalizer = NotationNormalizer()
        self.validator = ImportValidator()
        self.midiSynthesizer = ImportMIDISynthesizer()
    }

    // MARK: - ImportPipelineProtocol

    /// Runs the 5-stage import pipeline and streams results.
    ///
    /// - Parameters:
    ///   - input: Raw notation input from the user.
    ///   - configuration: Bundled song metadata (title, artist, language, difficulty, category).
    /// - Returns: An `AsyncStream<ImportPipelineResult>` that emits progress, warnings, and the final result.
    public func run(
        input: NotationInput,
        configuration: ImportConfiguration
    ) -> AsyncStream<ImportPipelineResult> {
        AsyncStream { continuation in
            Task {
                await runPipeline(
                    input: input,
                    configuration: configuration,
                    continuation: continuation
                )
            }
        }
    }

    // MARK: - Private Pipeline Execution

    /// Execute all five pipeline stages sequentially.
    private func runPipeline(
        input: NotationInput,
        configuration: ImportConfiguration,
        continuation: AsyncStream<ImportPipelineResult>.Continuation
    ) async {
        // Validate metadata first
        guard !configuration.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            continuation.yield(.failed(.missingMetadata("title")))
            continuation.finish()
            return
        }

        // Stages 1-2: Detect format and parse
        let resolvedInput = detectFormat(input: input, continuation: continuation)
        guard let parsed = parseNotation(input: resolvedInput, continuation: continuation) else { return }

        // Stage 3: Normalise
        guard let normalised = normaliseNotation(parsed: parsed, continuation: continuation) else { return }

        // Stage 4: Validate
        let warnings = validateNotation(normalised: normalised, continuation: continuation)
        if warnings == nil { return }

        // Stage 5: Synthesise MIDI and build DTO
        await synthesiseAndComplete(
            normalised: normalised,
            warnings: warnings ?? [],
            configuration: configuration,
            continuation: continuation
        )
    }

    // MARK: - Pipeline Stage Helpers

    /// Stage 1: Detect the notation format.
    private func detectFormat(
        input: NotationInput,
        continuation: AsyncStream<ImportPipelineResult>.Continuation
    ) -> NotationInput {
        continuation.yield(.progress(ImportProgressUpdate(stage: 1, stageName: "Detecting format", fraction: 0.0)))
        let detectedFormat = formatDetector.detect(input)
        let resolvedInput: NotationInput
        if detectedFormat != .unknown && input.declaredFormat == .unknown {
            resolvedInput = NotationInput(
                text: input.text, filenameHint: input.filenameHint,
                declaredFormat: detectedFormat
            )
        } else {
            resolvedInput = input
        }
        continuation.yield(.progress(ImportProgressUpdate(stage: 1, stageName: "Detecting format", fraction: 0.2)))
        return resolvedInput
    }

    /// Stage 2: Parse the notation. Returns nil and finishes stream on failure.
    private func parseNotation(
        input: NotationInput,
        continuation: AsyncStream<ImportPipelineResult>.Continuation
    ) -> ParsedNotation? {
        continuation.yield(.progress(ImportProgressUpdate(stage: 2, stageName: "Parsing notation", fraction: 0.2)))
        let parsed: ParsedNotation
        do {
            parsed = try parse(input)
        } catch let error as ImportError {
            continuation.yield(.failed(error))
            continuation.finish()
            return nil
        } catch {
            continuation.yield(.failed(.parsingFailed(error.localizedDescription)))
            continuation.finish()
            return nil
        }
        continuation.yield(.progress(ImportProgressUpdate(stage: 2, stageName: "Parsing notation", fraction: 0.4)))
        return parsed
    }

    /// Stage 3: Normalise parsed notation. Returns nil and finishes stream on failure.
    private func normaliseNotation(
        parsed: ParsedNotation,
        continuation: AsyncStream<ImportPipelineResult>.Continuation
    ) -> ParsedNotation? {
        continuation.yield(.progress(ImportProgressUpdate(stage: 3, stageName: "Normalising notes", fraction: 0.4)))
        let normalised: ParsedNotation
        do {
            normalised = try normalizer.normalise(parsed)
        } catch let error as ImportError {
            continuation.yield(.failed(error))
            continuation.finish()
            return nil
        } catch {
            continuation.yield(.failed(.normalisationFailed))
            continuation.finish()
            return nil
        }
        continuation.yield(.progress(ImportProgressUpdate(stage: 3, stageName: "Normalising notes", fraction: 0.6)))
        return normalised
    }

    /// Stage 4: Validate notation and emit warnings. Returns nil if blocking errors found.
    private func validateNotation(
        normalised: ParsedNotation,
        continuation: AsyncStream<ImportPipelineResult>.Continuation
    ) -> [ParseWarning]? {
        continuation.yield(.progress(ImportProgressUpdate(stage: 4, stageName: "Validating", fraction: 0.6)))
        let warnings = validator.validate(normalised)
        if !warnings.isEmpty {
            continuation.yield(.warningsGenerated(warnings))
        }
        if warnings.contains(where: { $0.severity == .error }) {
            continuation.yield(.failed(.parsingFailed("Validation errors must be resolved before saving.")))
            continuation.finish()
            return nil
        }
        continuation.yield(.progress(ImportProgressUpdate(stage: 4, stageName: "Validating", fraction: 0.8)))
        return warnings
    }

    /// Stage 5: Synthesise MIDI, build DTO, and complete the stream.
    private func synthesiseAndComplete(
        normalised: ParsedNotation,
        warnings: [ParseWarning],
        configuration: ImportConfiguration,
        continuation: AsyncStream<ImportPipelineResult>.Continuation
    ) async {
        continuation.yield(.progress(ImportProgressUpdate(stage: 5, stageName: "Generating MIDI", fraction: 0.8)))
        let midiData: Data?
        do {
            midiData = try await midiSynthesizer.synthesise(from: normalised, tempo: normalised.tempo)
        } catch let error as ImportError {
            continuation.yield(.failed(error))
            continuation.finish()
            return
        } catch {
            continuation.yield(.failed(.midiSynthesisFailed(error.localizedDescription)))
            continuation.finish()
            return
        }
        continuation.yield(.progress(ImportProgressUpdate(stage: 5, stageName: "Generating MIDI", fraction: 1.0)))

        let dto = buildDTO(
            normalised: normalised, midiData: midiData,
            warnings: warnings, configuration: configuration
        )
        continuation.yield(.completed(dto))
        continuation.finish()
    }

    // MARK: - DTO Builder

    /// Build the final `ImportedSongDTO` from pipeline results and configuration.
    private func buildDTO(
        normalised: ParsedNotation,
        midiData: Data?,
        warnings: [ParseWarning],
        configuration: ImportConfiguration
    ) -> ImportedSongDTO {
        let durationSeconds = normalizer.estimateDurationSeconds(normalised, tempo: normalised.tempo)
        let sargamData: Data? = normalised.format == .sargam ? encodeSargamNotes(normalised.notes) : nil
        let westernData: Data? = normalised.format != .sargam ? encodeWesternNotes(normalised.notes) : nil

        return ImportedSongDTO(
            title: configuration.title.trimmingCharacters(in: .whitespacesAndNewlines),
            artist: configuration.artist.trimmingCharacters(in: .whitespacesAndNewlines),
            language: configuration.language,
            difficulty: max(1, min(5, configuration.difficulty)),
            category: configuration.category,
            tempo: normalised.tempo,
            durationSeconds: durationSeconds,
            sargamNotationData: sargamData,
            westernNotationData: westernData,
            midiData: midiData,
            keySignature: normalised.keySignature,
            timeSignature: normalised.timeSignature,
            source: "user",
            acceptedWarnings: warnings.filter { $0.severity != .error }
        )
    }

    // MARK: - Parser Dispatch

    /// Routes a notation input to the correct parser based on detected format.
    private func parse(_ input: NotationInput) throws -> ParsedNotation {
        switch input.declaredFormat {
        case .sargam:
            return try sargamParser.parse(input)
        case .western:
            return try westernParser.parse(input)
        case .musicXML:
            return try musicXMLParser.parse(input)
        case .unknown:
            throw ImportError.unrecognisedFormat
        }
    }

    // MARK: - JSON Encoding

    /// Encodes parsed sargam notes into the `[SargamNote]` JSON format expected by `Song.decodedSargamNotes`.
    ///
    /// Uses exact field names matching `SargamNote.CodingKeys`: `"note"`, `"octave"`, `"duration"`, `"modifier"`.
    private func encodeSargamNotes(_ notes: [ParsedNotation.Note]) -> Data? {
        let dicts = notes.map { note -> [String: Any] in
            var dict: [String: Any] = [
                "note": note.name,
                "octave": note.octave ?? 4,
                "duration": note.durationBeats ?? 1.0,
            ]
            if let modifier = note.modifier { dict["modifier"] = modifier }
            return dict
        }
        do {
            return try JSONSerialization.data(withJSONObject: dicts)
        } catch {
            pipelineLogger.error("Failed to encode sargam notes: \(error.localizedDescription)")
            return nil
        }
    }

    /// Encodes parsed western notes into the `[WesternNote]` JSON format expected by `Song.decodedWesternNotes`.
    ///
    /// Uses exact field names matching `WesternNote.CodingKeys`: `"note"`, `"duration"`, `"midiNumber"`.
    /// The MIDI number is derived from the note name (e.g. "C4" -> 60).
    private func encodeWesternNotes(_ notes: [ParsedNotation.Note]) -> Data? {
        let dicts = notes.map { note -> [String: Any] in
            [
                "note": note.name,
                "duration": note.durationBeats ?? 1.0,
                "midiNumber": Self.midiNumber(for: note.name, octave: note.octave),
            ] as [String: Any]
        }
        do {
            return try JSONSerialization.data(withJSONObject: dicts)
        } catch {
            pipelineLogger.error("Failed to encode western notes: \(error.localizedDescription)")
            return nil
        }
    }

    /// Derives a MIDI note number from a western note name and optional octave.
    ///
    /// Handles note names with embedded octave (e.g. "C4", "D#3", "Eb5") and
    /// standalone names combined with a separate octave parameter.
    /// Returns 60 (middle C) as a safe fallback for unparseable names.
    private static func midiNumber(for name: String, octave: Int?) -> Int {
        // Semitone offsets from C for each note letter
        let semitones: [Character: Int] = [
            "C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11,
        ]

        var chars = name.uppercased()

        // Extract letter
        guard let first = chars.first, let base = semitones[first] else { return 60 }
        chars = String(chars.dropFirst())

        // Extract accidental
        var offset = 0
        if chars.hasPrefix("#") { offset = 1; chars = String(chars.dropFirst()) } else if chars.hasPrefix("B") {
            offset = -1; chars = String(chars.dropFirst())
        }

        // Extract octave from the remaining string, or use the parameter
        let oct: Int
        if let numStr = chars.first.flatMap({ $0.isNumber ? String($0) : nil }),
           let num = Int(numStr) {
            oct = num
        } else {
            oct = octave ?? 4
        }

        // MIDI = (octave + 1) * 12 + semitone
        return (oct + 1) * 12 + base + offset
    }
}
