import Foundation

/// Bundles all metadata parameters for the import pipeline.
///
/// Replaces multiple individual function parameters to stay within
/// SwiftLint's `function_parameter_count` limit of 5.
public struct ImportConfiguration: Sendable {
    /// Song title provided by the user.
    public let title: String
    /// Artist or composer name.
    public let artist: String
    /// ISO 639-1 language code (e.g. "hi", "mr", "en").
    public let language: String
    /// Difficulty level 1-5.
    public let difficulty: Int
    /// Category string (e.g. "folk", "classical").
    public let category: String

    /// Create an import configuration with song metadata.
    ///
    /// - Parameters:
    ///   - title: Song title.
    ///   - artist: Artist or composer name.
    ///   - language: ISO 639-1 language code.
    ///   - difficulty: Difficulty level 1-5.
    ///   - category: Category string.
    public init(
        title: String,
        artist: String,
        language: String,
        difficulty: Int,
        category: String
    ) {
        self.title = title
        self.artist = artist
        self.language = language
        self.difficulty = difficulty
        self.category = category
    }
}
