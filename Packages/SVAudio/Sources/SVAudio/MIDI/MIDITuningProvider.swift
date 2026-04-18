import Foundation

/// Provides per-note tuning offsets for just intonation raga performance.
///
/// Future-ready protocol for MIDI Tuning Standard (MTS) SysEx integration.
/// Implementations map each MIDI note to a cents offset from 12-tone equal
/// temperament based on the active raga and tonic.
///
/// ## Usage
///
/// ```swift
/// let tuning: MIDITuningProvider = RagaTuning(raga: "Yaman", tonic: 60)
/// let offsets = tuning.tuningOffsets()
/// // offsets[62] = -4.0 (Re is 4 cents flat in JI for Yaman)
/// ```
public protocol MIDITuningProvider: Sendable {
    /// Generate per-note tuning offsets in cents for the active raga.
    ///
    /// Maps MIDI note numbers (0–127) to cents deviation from 12-tone
    /// equal temperament. Notes not in the raga return 0.0.
    ///
    /// - Returns: Dictionary mapping MIDI note number to cents offset.
    func tuningOffsets() -> [UInt8: Double]

    /// The raga name this tuning is configured for.
    var ragaName: String { get }

    /// The tonic MIDI note number (Sa).
    var tonicNote: UInt8 { get }
}
