import Foundation

/// Audio engine surface used by the Play tab.
///
/// Mirrors `ProductionMultiChannelEngine`'s real touch + program-load API.
/// This is a *minimal* re-declaration with only the methods the Play tab
/// `PlayTabViewModel` needs; its purpose is to enable mocking of the audio
/// engine in `PlayTabViewModelTests` without standing up a real
/// `AVAudioEngine` graph.
///
/// Conformance on `ProductionMultiChannelEngine` is label-only: every method
/// in this protocol matches the engine's real API exactly, so adoption adds
/// no logic and no behavioural change.
///
/// Lives in SVAudio (not SVCore) because `ProductionMultiChannelEngine` is
/// the canonical implementation and `loadProgram` only makes sense in the
/// presence of SVAudio's GM SoundFont resource. Keeping the protocol in
/// SVAudio also avoids a name collision with the existing
/// `MIDIInputProviding` protocol used by Play-Along.
@MainActor
public protocol PlayTabAudioEngine: AnyObject {
    /// Load a General MIDI program into the given sampler index.
    ///
    /// Used by the Play tab to swap the touch sampler's instrument when the
    /// user picks a new GM program from the instrument picker.
    ///
    /// - Parameters:
    ///   - index: Sampler index (0 = touch sampler; 1...15 = song slots).
    ///   - program: GM program number (0–127).
    ///   - isPercussion: When true, uses the percussion bank.
    /// - Throws: `MultiChannelEngineError.bankLoadFailed` on any SoundFont
    ///   resolution or sampler-load failure.
    func loadProgram(into index: Int, program: UInt8, isPercussion: Bool) throws

    /// Play a touch-input note on the touch sampler (sampler index 0).
    ///
    /// - Parameters:
    ///   - midiNote: MIDI note number (0–127).
    ///   - velocity: Key velocity (0–127).
    func playTouchNote(_ midiNote: UInt8, velocity: UInt8)

    /// Stop a single touch-input note on the touch sampler.
    ///
    /// - Parameter midiNote: MIDI note number to stop (0–127).
    func stopTouchNote(_ midiNote: UInt8)

    /// Stop every currently-ringing touch note. Used on tab disappear and
    /// instrument change to prevent stuck notes.
    func stopAllTouchNotes()
}
