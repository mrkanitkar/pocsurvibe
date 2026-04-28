import Foundation

/// Synthesises MIDI data from a parsed notation.
///
/// Renders notes via SVAudio's production audio engine.
/// Returns raw MIDI binary data suitable for storage in `Song.midiData`.
public protocol ImportMIDISynthesisProtocol: Sendable {

    /// Generates MIDI binary data from a parsed notation.
    ///
    /// - Parameters:
    ///   - notation: The normalised, validated parsed notation.
    ///   - tempo: Tempo in BPM used for timing MIDI events.
    /// - Returns: Raw MIDI binary data, or `nil` if synthesis produced no events.
    /// - Throws: `ImportError.midiSynthesisFailed` if MIDI generation fails.
    func synthesise(from notation: ParsedNotation, tempo: Int) async throws -> Data?
}
