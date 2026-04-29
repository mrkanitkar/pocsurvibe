import Foundation

/// Visual-sync sink for a take-playback engine.
///
/// Lives in SVCore so SVAudio can drive visual highlighting without importing
/// the SurVibe app target. The `MIDINoteHighlightCoordinator` in the app target
/// gains an additive conformance — its existing `nonisolated` `noteOn / noteOff /
/// sustainDown / sustainUp` methods already match these signatures.
public protocol HighlightSink: AnyObject, Sendable {
    /// Highlights `midiNote` as currently sounding.
    func noteOn(_ midiNote: Int)
    /// Removes highlight for `midiNote` on the given MIDI channel.
    func noteOff(_ midiNote: Int, channel: UInt8)
    /// Marks the sustain pedal as down on the given MIDI channel.
    func sustainDown(channel: UInt8)
    /// Marks the sustain pedal as up on the given MIDI channel.
    func sustainUp(channel: UInt8)
}

// Default-arg adapter so both the protocol and existing call sites match
// MIDINoteHighlightCoordinator's `channel: UInt8 = 0` defaults verbatim.
public extension HighlightSink {
    /// Convenience for `noteOff(_:channel:)` on channel 0.
    func noteOff(_ midiNote: Int) { noteOff(midiNote, channel: 0) }
    /// Convenience for `sustainDown(channel:)` on channel 0.
    func sustainDown() { sustainDown(channel: 0) }
    /// Convenience for `sustainUp(channel:)` on channel 0.
    func sustainUp() { sustainUp(channel: 0) }
}
