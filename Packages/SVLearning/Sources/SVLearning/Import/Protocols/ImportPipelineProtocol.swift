import Foundation

/// Orchestrates the full 5-stage import pipeline.
///
/// Stages: format detection -> parsing -> normalisation -> validation -> MIDI synthesis.
/// Progress is reported via `ImportProgressUpdate` values.
public protocol ImportPipelineProtocol: Sendable {

    /// Runs the full import pipeline on the given input.
    ///
    /// - Parameters:
    ///   - input: The raw notation input from the user.
    ///   - configuration: Bundled song metadata (title, artist, language, difficulty, category).
    /// - Returns: An `AsyncStream` of `ImportPipelineResult` values ending with `.completed` or `.failed`.
    func run(
        input: NotationInput,
        configuration: ImportConfiguration
    ) -> AsyncStream<ImportPipelineResult>
}

/// A single result event emitted by the import pipeline stream.
public enum ImportPipelineResult: Sendable {
    /// Pipeline stage progress update.
    case progress(ImportProgressUpdate)
    /// Warnings were generated — pipeline paused awaiting user decision.
    case warningsGenerated([ParseWarning])
    /// Pipeline completed successfully.
    case completed(ImportedSongDTO)
    /// Pipeline failed with an error.
    case failed(ImportError)
}

/// Progress update emitted during pipeline execution.
public struct ImportProgressUpdate: Sendable {
    /// Stage number (1-5).
    public let stage: Int
    /// Human-readable stage name.
    public let stageName: String
    /// Fractional progress 0.0-1.0.
    public let fraction: Double

    public init(stage: Int, stageName: String, fraction: Double) {
        self.stage = stage
        self.stageName = stageName
        self.fraction = fraction
    }
}
