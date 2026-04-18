import Foundation

// MARK: - KeyIlluminationProvider

/// Abstraction for sending key-lighting commands to a connected MIDI keyboard.
///
/// Implementations send MIDI messages (typically on a dedicated lighting channel)
/// to illuminate or extinguish keys on hardware that supports LED illumination
/// (e.g., Yamaha NP-Series "Smart Pianist" or Roland LX-Series).
///
/// Conforming types must be `Sendable` because `StandardKeyIllumination` is
/// consumed from both `@MainActor` UI code and audio-thread callbacks.
///
/// ## Protocol Usage
///
/// ```swift
/// let lighting: any KeyIlluminationProvider = StandardKeyIllumination(output: manager)
/// if lighting.isSupported {
///     lighting.illuminate(notes: [60, 64, 67]) // C major chord
///     lighting.clearAll()
/// }
/// ```
public protocol KeyIlluminationProvider: Sendable {

    /// Whether the connected hardware supports key illumination.
    ///
    /// Implementations should return `false` when no hardware is connected or
    /// when the connected device is known to not support MIDI lighting commands.
    var isSupported: Bool { get }

    /// Illuminate a set of MIDI notes on the keyboard.
    ///
    /// Turns on LEDs for every note in `notes` and turns off any note that was
    /// previously illuminated but is not in the new set (diff-based update).
    /// Implementors must be idempotent — calling with the same set twice must
    /// not produce duplicate MIDI messages.
    ///
    /// - Parameter notes: Set of MIDI note numbers (0–127) to illuminate.
    func illuminate(notes: Set<UInt8>)

    /// Turn off all illuminated keys.
    ///
    /// Sends Note Off (velocity 0) on the lighting channel for every currently
    /// lit key, then clears the internal lit-key set.
    func clearAll()
}
