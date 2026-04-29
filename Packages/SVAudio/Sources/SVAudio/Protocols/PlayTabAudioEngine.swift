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
public protocol PlayTabAudioEngine: AnyObject, Sendable {
    /// Load a General MIDI program into the given sampler index.
    ///
    /// Used by the Play tab to swap the touch sampler's instrument when the
    /// user picks a new GM program from the instrument picker.
    ///
    /// MainActor-isolated: SF2 program loads touch the sampler graph and
    /// must run on the main actor.
    ///
    /// - Parameters:
    ///   - index: Sampler index (0 = touch sampler; 1...15 = song slots).
    ///   - program: GM program number (0–127).
    ///   - isPercussion: When true, uses the percussion bank.
    /// - Throws: `MultiChannelEngineError.bankLoadFailed` on any SoundFont
    ///   resolution or sampler-load failure.
    @MainActor
    func loadProgram(into index: Int, program: UInt8, isPercussion: Bool) throws

    /// Play a touch-input note on the touch sampler (sampler index 0).
    ///
    /// `nonisolated`: SurVibe's touch-to-sound budget is 3–10 ms. The
    /// concrete `ProductionMultiChannelEngine` calls
    /// `AVAudioUnitSampler.startNote` (documented thread-safe) so this can
    /// run on a CoreMIDI callback thread without a MainActor hop.
    ///
    /// - Parameters:
    ///   - midiNote: MIDI note number (0–127).
    ///   - velocity: Key velocity (0–127).
    nonisolated func playTouchNote(_ midiNote: UInt8, velocity: UInt8)

    /// Stop a single touch-input note on the touch sampler.
    ///
    /// `nonisolated`: see `playTouchNote`.
    ///
    /// - Parameter midiNote: MIDI note number to stop (0–127).
    nonisolated func stopTouchNote(_ midiNote: UInt8)

    /// Stop every currently-ringing touch note. Used on tab disappear and
    /// instrument change to prevent stuck notes.
    ///
    /// `nonisolated`: see `playTouchNote`.
    nonisolated func stopAllTouchNotes()
}
