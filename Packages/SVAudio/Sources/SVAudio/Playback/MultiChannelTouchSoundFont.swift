import Foundation

/// Adapter that exposes `MultiChannelEngineProtocol`'s touch surface
/// through the legacy `SoundFontPlaying` interface.
///
/// Used by `PlayAlongViewModel` / `PlaybackCoordinator` so that the
/// existing manual scheduler (which fires `playNote / stopNote` per
/// note timeline event) routes through `samplers[0]` (Acoustic Grand)
/// of the new `ProductionMultiChannelEngine` instead of the legacy
/// single `AVAudioUnitSampler`.
///
/// The adapter resolves `multiChannel` lazily on each call because
/// `AudioEngineManager.shared.multiChannel` is constructed only after
/// `startForPlayback()` runs. Calls before construction are no-ops
/// (and logged as warnings).
@MainActor
public final class MultiChannelTouchSoundFont: SoundFontPlaying {

    /// Returns true once `multiChannel` exists. Existing callers use this
    /// signal as a proxy for "audio is ready" — it's true after
    /// `AudioEngineManager.shared.startForPlayback()` succeeds, even
    /// before any explicit per-bank load (multiChannel preloads
    /// Acoustic Grand into samplers[0] at construction).
    public var isLoaded: Bool { multiChannel != nil }

    /// `channel` is accepted for protocol conformance but ignored —
    /// touch input always plays on channel 0 (the spec dedicates
    /// `samplers[0]` to touch).
    public func playNote(midiNote: UInt8, velocity: UInt8, channel: UInt8) {
        multiChannel?.playTouchNote(midiNote, velocity: velocity)
    }

    public func stopNote(midiNote: UInt8, channel: UInt8) {
        multiChannel?.stopTouchNote(midiNote)
    }

    public func stopAllNotes() {
        multiChannel?.stopAllTouchNotes()
    }

    public init() {}

    private var multiChannel: ProductionMultiChannelEngine? {
        AudioEngineManager.shared.multiChannel
    }
}
