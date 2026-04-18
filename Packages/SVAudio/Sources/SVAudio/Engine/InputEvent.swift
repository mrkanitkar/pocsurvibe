import Foundation
import SVCore

/// A unified event from either the MIDI or mic input pipeline.
///
/// `InputRouter` vends an `AsyncStream<InputEvent>` that merges:
/// - MIDI note-on / note-off from `MIDIInputManager`
/// - Continuous pitch samples from `MicPitchDetector`
///
/// Each event carries the active `InputSource` so consumers can
/// display provenance in the UI.
public enum InputEvent: Sendable {
    /// A discrete note-on event. For MIDI, from the device; for mic,
    /// synthesized on attack onset when a pitch is first detected.
    case noteOn(note: Int, velocity: Int, source: InputSource, timestampNs: UInt64)
    /// A discrete note-off event. MIDI-only for now (mic has no
    /// reliable offset signal — tracked indirectly via confidence drop).
    case noteOff(note: Int, source: InputSource, timestampNs: UInt64)
    /// Continuous mic pitch sample. No MIDI equivalent.
    case pitch(result: PitchResult, source: InputSource)
}
