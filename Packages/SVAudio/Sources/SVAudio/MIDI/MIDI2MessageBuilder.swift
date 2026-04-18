import CoreMIDI
import Foundation

// MARK: - MIDI2MessageBuilder

/// Wraps all 16 Apple MIDI 2.0 C functions, returning UMP words as `[UInt32]`.
///
/// Each static method selects the correct Apple C function and returns either:
/// - **Two words** `[word0, word1]` for MIDI 2.0 messages (`MIDIMessage_64`).
/// - **One word** `[word]` for MIDI 1.0 UP messages (`UInt32` directly from `MIDI1UP*`).
///
/// This adapts the two different return-type conventions used by Apple's CoreMIDI
/// C API into a uniform `[UInt32]` array consumed by `MIDIOutputManager.sendWords(_:)`.
///
/// ## Apple API Spelling Note
///
/// `MIDI2PerNoteManagment` — Apple's CoreMIDI header spells this with a single 'e'
/// (missing the second 'e' in "Management"). The method name matches Apple's spelling
/// exactly to avoid a linker error.
public enum MIDI2MessageBuilder {

    // MARK: - Note Messages (MIDI 2.0)

    /// Build a MIDI 2.0 Note On UMP (64-bit).
    ///
    /// Velocity is an 8-bit value (0–127) scaled to the 16-bit MIDI 2.0 range
    /// by Apple's `MIDI2NoteOn` C function.
    ///
    /// - Parameters:
    ///   - note: MIDI note number (0–127).
    ///   - velocity: Note velocity (0–127).
    ///   - channel: MIDI channel (0–15).
    ///   - group: UMP group (0–15). Defaults to `0`.
    /// - Returns: Two-word UMP `[word0, word1]`.
    public static func noteOn(
        note: UInt8,
        velocity: UInt8,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let msg = MIDI2NoteOn(group, channel, note, 0, UInt16(velocity) << 9, 0)
        return [msg.word0, msg.word1]
    }

    /// Build a MIDI 2.0 Note Off UMP (64-bit).
    ///
    /// - Parameters:
    ///   - note: MIDI note number (0–127).
    ///   - velocity: Release velocity (0–127).
    ///   - channel: MIDI channel (0–15).
    ///   - group: UMP group (0–15). Defaults to `0`.
    /// - Returns: Two-word UMP `[word0, word1]`.
    public static func noteOff(
        note: UInt8,
        velocity: UInt8,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let msg = MIDI2NoteOff(group, channel, note, 0, UInt16(velocity) << 9, 0)
        return [msg.word0, msg.word1]
    }

    // MARK: - Polyphonic Messages (MIDI 2.0)

    /// Build a MIDI 2.0 Poly Pressure (aftertouch) UMP (64-bit).
    ///
    /// - Parameters:
    ///   - note: MIDI note number (0–127).
    ///   - pressure: 32-bit pressure value.
    ///   - channel: MIDI channel (0–15).
    ///   - group: UMP group (0–15). Defaults to `0`.
    /// - Returns: Two-word UMP `[word0, word1]`.
    public static func polyPressure(
        note: UInt8,
        pressure: UInt32,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let msg = MIDI2PolyPressure(group, channel, note, pressure)
        return [msg.word0, msg.word1]
    }

    /// Build a MIDI 2.0 Registered Per-Note Controller UMP (64-bit).
    ///
    /// - Parameters:
    ///   - note: MIDI note number (0–127).
    ///   - index: Controller index (0–255).
    ///   - value: 32-bit controller value.
    ///   - channel: MIDI channel (0–15).
    ///   - group: UMP group (0–15). Defaults to `0`.
    /// - Returns: Two-word UMP `[word0, word1]`.
    public static func registeredPerNoteController(
        note: UInt8,
        index: UInt8,
        value: UInt32,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let msg = MIDI2RegisteredPNC(group, channel, note, index, value)
        return [msg.word0, msg.word1]
    }

    /// Build a MIDI 2.0 Assignable Per-Note Controller UMP (64-bit).
    ///
    /// - Parameters:
    ///   - note: MIDI note number (0–127).
    ///   - index: Controller index (0–255).
    ///   - value: 32-bit controller value.
    ///   - channel: MIDI channel (0–15).
    ///   - group: UMP group (0–15). Defaults to `0`.
    /// - Returns: Two-word UMP `[word0, word1]`.
    public static func assignablePerNoteController(
        note: UInt8,
        index: UInt8,
        value: UInt32,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let msg = MIDI2AssignablePNC(group, channel, note, index, value)
        return [msg.word0, msg.word1]
    }

    /// Build a MIDI 2.0 Per-Note Management UMP (64-bit).
    ///
    /// Note: Apple's CoreMIDI header spells this function `MIDI2PerNoteManagment`
    /// (single 'e' — missing the second 'e' in "Management"). This wrapper uses
    /// Apple's exact spelling to avoid a linker error.
    ///
    /// - Parameters:
    ///   - note: MIDI note number (0–127).
    ///   - optionFlags: Management option flags.
    ///   - channel: MIDI channel (0–15).
    ///   - group: UMP group (0–15). Defaults to `0`.
    /// - Returns: Two-word UMP `[word0, word1]`.
    public static func perNoteManagement(
        note: UInt8,
        detach: Bool,
        reset: Bool,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let msg = MIDI2PerNoteManagment(group, channel, note, detach, reset)
        return [msg.word0, msg.word1]
    }

    // MARK: - Channel Voice Messages (MIDI 2.0)

    /// Build a MIDI 2.0 Control Change UMP (64-bit).
    ///
    /// - Parameters:
    ///   - controller: CC number (0–127).
    ///   - value: 32-bit controller value.
    ///   - channel: MIDI channel (0–15).
    ///   - group: UMP group (0–15). Defaults to `0`.
    /// - Returns: Two-word UMP `[word0, word1]`.
    public static func controlChange2(
        controller: UInt8,
        value: UInt32,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let msg = MIDI2ControlChange(group, channel, controller, value)
        return [msg.word0, msg.word1]
    }

    /// Build a MIDI 2.0 Registered Controller (RPN) UMP (64-bit).
    ///
    /// - Parameters:
    ///   - bank: RPN bank (0–127).
    ///   - index: RPN index (0–127).
    ///   - value: 32-bit value.
    ///   - channel: MIDI channel (0–15).
    ///   - group: UMP group (0–15). Defaults to `0`.
    /// - Returns: Two-word UMP `[word0, word1]`.
    public static func registeredController(
        bank: UInt8,
        index: UInt8,
        value: UInt32,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let msg = MIDI2RegisteredControl(group, channel, bank, index, value)
        return [msg.word0, msg.word1]
    }

    /// Build a MIDI 2.0 Assignable Controller (NRPN) UMP (64-bit).
    ///
    /// - Parameters:
    ///   - bank: NRPN bank (0–127).
    ///   - index: NRPN index (0–127).
    ///   - value: 32-bit value.
    ///   - channel: MIDI channel (0–15).
    ///   - group: UMP group (0–15). Defaults to `0`.
    /// - Returns: Two-word UMP `[word0, word1]`.
    public static func assignableController(
        bank: UInt8,
        index: UInt8,
        value: UInt32,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let msg = MIDI2AssignableControl(group, channel, bank, index, value)
        return [msg.word0, msg.word1]
    }

    /// Build a MIDI 2.0 Relative Registered Controller UMP (64-bit).
    ///
    /// - Parameters:
    ///   - bank: RPN bank (0–127).
    ///   - index: RPN index (0–127).
    ///   - value: Signed 32-bit relative delta value.
    ///   - channel: MIDI channel (0–15).
    ///   - group: UMP group (0–15). Defaults to `0`.
    /// - Returns: Two-word UMP `[word0, word1]`.
    public static func relativeRegisteredController(
        bank: UInt8,
        index: UInt8,
        value: UInt32,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let msg = MIDI2RelRegisteredControl(group, channel, bank, index, value)
        return [msg.word0, msg.word1]
    }

    /// Build a MIDI 2.0 Relative Assignable Controller UMP (64-bit).
    ///
    /// - Parameters:
    ///   - bank: NRPN bank (0–127).
    ///   - index: NRPN index (0–127).
    ///   - value: Signed 32-bit relative delta value.
    ///   - channel: MIDI channel (0–15).
    ///   - group: UMP group (0–15). Defaults to `0`.
    /// - Returns: Two-word UMP `[word0, word1]`.
    public static func relativeAssignableController(
        bank: UInt8,
        index: UInt8,
        value: UInt32,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let msg = MIDI2RelAssignableControl(group, channel, bank, index, value)
        return [msg.word0, msg.word1]
    }

    /// Build a MIDI 2.0 Program Change UMP (64-bit).
    ///
    /// - Parameters:
    ///   - program: Program number (0–127).
    ///   - bankMSB: Bank select MSB (0–127). Set to `0x7F` if unused.
    ///   - bankLSB: Bank select LSB (0–127). Set to `0x7F` if unused.
    ///   - channel: MIDI channel (0–15).
    ///   - group: UMP group (0–15). Defaults to `0`.
    /// - Returns: Two-word UMP `[word0, word1]`.
    public static func programChange(
        program: UInt8,
        bankMSB: UInt8 = 0x7F,
        bankLSB: UInt8 = 0x7F,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let bankIsValid = bankMSB != 0x7F || bankLSB != 0x7F
        let msg = MIDI2ProgramChange(group, channel, bankIsValid, program, bankMSB, bankLSB)
        return [msg.word0, msg.word1]
    }

    /// Build a MIDI 2.0 Channel Pressure UMP (64-bit).
    ///
    /// - Parameters:
    ///   - pressure: 32-bit channel pressure value.
    ///   - channel: MIDI channel (0–15).
    ///   - group: UMP group (0–15). Defaults to `0`.
    /// - Returns: Two-word UMP `[word0, word1]`.
    public static func channelPressure(
        pressure: UInt32,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let msg = MIDI2ChannelPressure(group, channel, pressure)
        return [msg.word0, msg.word1]
    }

    /// Build a MIDI 2.0 Pitch Bend UMP (64-bit).
    ///
    /// Center (no pitch bend) is `0x80000000`.
    ///
    /// - Parameters:
    ///   - value: 32-bit pitch bend value. `0x80000000` = center.
    ///   - channel: MIDI channel (0–15).
    ///   - group: UMP group (0–15). Defaults to `0`.
    /// - Returns: Two-word UMP `[word0, word1]`.
    public static func pitchBend(
        value: UInt32,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let msg = MIDI2PitchBend(group, channel, value)
        return [msg.word0, msg.word1]
    }

    // MARK: - Per-Note Pitch Bend & Generic Channel Voice (MIDI 2.0)

    /// Build a MIDI 2.0 Per-Note Pitch Bend UMP (64-bit).
    ///
    /// - Parameters:
    ///   - note: MIDI note number (0-127).
    ///   - value: 32-bit pitch bend value.
    ///   - channel: MIDI channel (0-15).
    ///   - group: UMP group (0-15). Defaults to 0.
    /// - Returns: Two-word UMP `[word0, word1]`.
    public static func perNotePitchBend(
        note: UInt8,
        value: UInt32,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let msg = MIDI2PerNotePitchBend(group, channel, note, value)
        return [msg.word0, msg.word1]
    }

    /// Build a generic MIDI 2.0 Channel Voice message UMP (64-bit).
    ///
    /// - Parameters:
    ///   - status: Channel Voice status nibble.
    ///   - channel: MIDI channel (0-15).
    ///   - word1Data: Upper 16 bits of word 1 (note number, controller, etc.).
    ///   - word2: Full second 32-bit word.
    ///   - group: UMP group (0-15). Defaults to 0.
    /// - Returns: Two-word UMP `[word0, word1]`.
    public static func channelVoiceMessage(
        status: UInt8,
        channel: UInt8,
        word1Data: UInt16,
        word2: UInt32,
        group: UInt8 = 0
    ) -> [UInt32] {
        let msg = MIDI2ChannelVoiceMessage(group, status, channel, word1Data, word2)
        return [msg.word0, msg.word1]
    }

    // MARK: - MIDI 1.0 UP (Compatibility)

    /// Build a MIDI 1.0 UP Control Change word (32-bit).
    ///
    /// Uses `MIDI1UPControlChange` which returns a `UInt32` directly (not
    /// a `MIDIMessage_64` struct), so only one word is returned.
    ///
    /// - Parameters:
    ///   - controller: CC number (0–127).
    ///   - value: CC value (0–127).
    ///   - channel: MIDI channel (0–15).
    ///   - group: UMP group (0–15). Defaults to `0`.
    /// - Returns: Single-word UMP `[word]`.
    public static func controlChange(
        controller: UInt8,
        value: UInt8,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let word = MIDI1UPControlChange(group, channel, controller, value)
        return [word]
    }

    /// Build a MIDI 1.0 UP Program Change word (32-bit).
    ///
    /// Uses `MIDI1UPProgramChange` which returns a `UInt32` directly.
    ///
    /// - Parameters:
    ///   - program: Program number (0–127).
    ///   - channel: MIDI channel (0–15).
    ///   - group: UMP group (0–15). Defaults to `0`.
    /// - Returns: Single-word UMP `[word]`.
    public static func programChange(
        program: UInt8,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let word = MIDI1UPProgramChange(group, channel, program)
        return [word]
    }

    // MARK: - MIDI 1.0 UP Note Messages

    /// Build a MIDI 1.0 UP Note On word (32-bit).
    ///
    /// - Parameters:
    ///   - note: MIDI note number (0-127).
    ///   - velocity: Note velocity (0-127).
    ///   - channel: MIDI channel (0-15).
    ///   - group: UMP group (0-15). Defaults to 0.
    /// - Returns: Single-word UMP `[word]`.
    public static func noteOn1UP(
        note: UInt8,
        velocity: UInt8,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let word = MIDI1UPNoteOn(group, channel, note, velocity)
        return [word]
    }

    /// Build a MIDI 1.0 UP Note Off word (32-bit).
    ///
    /// - Parameters:
    ///   - note: MIDI note number (0-127).
    ///   - velocity: Release velocity (0-127). Defaults to 0.
    ///   - channel: MIDI channel (0-15).
    ///   - group: UMP group (0-15). Defaults to 0.
    /// - Returns: Single-word UMP `[word]`.
    public static func noteOff1UP(
        note: UInt8,
        velocity: UInt8 = 0,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let word = MIDI1UPNoteOff(group, channel, note, velocity)
        return [word]
    }

    /// Build a MIDI 1.0 UP Pitch Bend word (32-bit).
    ///
    /// Apple's `MIDI1UPPitchBend` takes separate LSB and MSB bytes.
    ///
    /// - Parameters:
    ///   - lsb: Pitch bend LSB (0-127).
    ///   - msb: Pitch bend MSB (0-127).
    ///   - channel: MIDI channel (0-15).
    ///   - group: UMP group (0-15). Defaults to 0.
    /// - Returns: Single-word UMP `[word]`.
    public static func pitchBend1UP(
        lsb: UInt8,
        msb: UInt8,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let word = MIDI1UPPitchBend(group, channel, lsb, msb)
        return [word]
    }

    /// Build a MIDI 1.0 UP Channel Pressure word (32-bit).
    ///
    /// - Parameters:
    ///   - pressure: Channel pressure value (0-127).
    ///   - channel: MIDI channel (0-15).
    ///   - group: UMP group (0-15). Defaults to 0.
    /// - Returns: Single-word UMP `[word]`.
    public static func channelPressure1UP(
        pressure: UInt8,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let word = MIDI1UPChannelPressure(group, channel, pressure)
        return [word]
    }

    /// Build a MIDI 1.0 UP Poly Pressure word (32-bit).
    ///
    /// - Parameters:
    ///   - note: MIDI note number (0-127).
    ///   - pressure: Polyphonic pressure value (0-127).
    ///   - channel: MIDI channel (0-15).
    ///   - group: UMP group (0-15). Defaults to 0.
    /// - Returns: Single-word UMP `[word]`.
    public static func polyPressure1UP(
        note: UInt8,
        pressure: UInt8,
        channel: UInt8,
        group: UInt8 = 0
    ) -> [UInt32] {
        let word = MIDI1UPPolyPressure(group, channel, note, pressure)
        return [word]
    }
}
