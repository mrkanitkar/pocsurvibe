import Foundation

/// The input source currently routing events to the playalong view model.
///
/// `InputRouter` (in SVAudio) auto-selects between MIDI and mic based on
/// whether a physical MIDI device is connected. Consumers display the
/// active source in the UI (e.g., `SourceChip`) and can react to
/// transitions via `InputRouter.onSourceChange`.
public enum InputSource: Equatable, Sendable {
    /// No input source active (session not started, or MIDI disconnected
    /// and mic permission denied).
    case none
    /// A physical MIDI device. The `deviceName` is the human-readable
    /// endpoint name from CoreMIDI (e.g. "Yamaha PSR-400").
    case midi(deviceName: String)
    /// The iPad microphone.
    case mic
}
