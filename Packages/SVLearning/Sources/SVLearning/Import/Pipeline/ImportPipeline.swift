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
        // T5' removed the JSON-blob sargam/western notation fields from
        // Song @Model. The canonical representation is now midiData only;
        // both notation data slots are always nil.
        return ImportedSongDTO(
            title: configuration.title.trimmingCharacters(in: .whitespacesAndNewlines),
            artist: configuration.artist.trimmingCharacters(in: .whitespacesAndNewlines),
            language: configuration.language,
            difficulty: max(1, min(5, configuration.difficulty)),
            category: configuration.category,
            tempo: normalised.tempo,
            durationSeconds: durationSeconds,
            sargamNotationData: nil,
            westernNotationData: nil,
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

}
