import Foundation
import os

/// Configures connected MIDI devices for optimal Indian classical music performance.
///
/// Sends RPN 0 (Pitch Bend Sensitivity) to set the pitch bend range on the
/// connected keyboard. Indian classical music needs ±12 semitones for full
/// meend (glides spanning an octave), versus the standard ±2 semitones.
///
/// ## MIDI 1.0 Path
/// Uses CC sequence: CC101=0, CC100=0, CC6=range, CC38=0 (RPN 0 data entry).
///
/// ## MIDI 2.0 Path
/// Uses `MIDI2RegisteredControl` for atomic RPN delivery.
public enum MIDIProfileConfigurator {

    private static let logger = Logger.survibe(category: "MIDIProfileConfigurator")

    // MARK: - Configuration Presets

    /// Configure the connected device for Indian classical music.
    ///
    /// Sets pitch bend range to ±12 semitones for full-saptak meend.
    ///
    /// - Parameter output: MIDI output manager to send configuration messages.
    public static func configureForIndianMusic(output: MIDIOutputManager) {
        setPitchBendRange(semitones: 12, output: output)
        logger.info("Configured for Indian music: pitch bend range ±12 semitones")
    }

    /// Configure the connected device for standard Western music.
    ///
    /// Sets pitch bend range to ±2 semitones (MIDI default).
    ///
    /// - Parameter output: MIDI output manager to send configuration messages.
    public static func configureForWesternMusic(output: MIDIOutputManager) {
        setPitchBendRange(semitones: 2, output: output)
        logger.info("Configured for Western music: pitch bend range ±2 semitones")
    }

    // MARK: - RPN 0: Pitch Bend Sensitivity

    /// Set the pitch bend range on the connected device.
    ///
    /// Sends RPN 0 (Pitch Bend Sensitivity) via CC sequence for maximum
    /// compatibility. Works on both MIDI 1.0 and MIDI 2.0 devices.
    ///
    /// - Parameters:
    ///   - semitones: Bend range in semitones (e.g., 2 for ±2, 12 for ±12).
    ///   - output: MIDI output manager.
    public static func setPitchBendRange(semitones: Int, output: MIDIOutputManager) {
        let channel: UInt8 = 0

        // RPN 0 via CC sequence (universal compatibility):
        // CC 101 = 0 (RPN MSB - Pitch Bend Sensitivity)
        output.controlChange(controller: 101, value: 0, channel: channel)
        // CC 100 = 0 (RPN LSB)
        output.controlChange(controller: 100, value: 0, channel: channel)
        // CC 6 = semitones (Data Entry MSB)
        output.controlChange(controller: 6, value: UInt8(clamping: semitones), channel: channel)
        // CC 38 = 0 (Data Entry LSB - cents, not needed)
        output.controlChange(controller: 38, value: 0, channel: channel)
        // CC 101 = 127, CC 100 = 127 (RPN Null - deselect)
        output.controlChange(controller: 101, value: 127, channel: channel)
        output.controlChange(controller: 100, value: 127, channel: channel)

        logger.debug("Sent RPN 0 pitch bend range: ±\(semitones) semitones")
    }
}
