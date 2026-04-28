import Foundation
import os

/// Adapter that exposes `MultiChannelEngineProtocol`'s touch surface
/// through the legacy `SoundFontPlaying` interface.
///
/// Injected as the default `soundFont` in `PlayAlongViewModel.init`,
/// then handed to `PlaybackCoordinator` as `any SoundFontPlaying`.
/// `PlaybackCoordinator`'s manual scheduler fires `playNote / stopNote`
/// per timeline event; this adapter forwards those calls to
/// `samplers[0]` (Acoustic Grand) of the new
/// `ProductionMultiChannelEngine` instead of the legacy single
/// `AVAudioUnitSampler`.
///
/// `multiChannel` is resolved lazily on each call because
/// `AudioEngineManager.shared.multiChannel` is constructed only after
/// `startForPlayback()` runs. Calls before construction are no-ops
/// and emit a `.warning` log line via `MultiChannelLog.shared` so the
/// pre-ready window is diagnosable in production.
@MainActor
public final class MultiChannelTouchSoundFont: SoundFontPlaying {

    /// Returns true once `multiChannel` exists. Existing callers use this
    /// signal as a proxy for "audio is ready" — it's true after
    /// `AudioEngineManager.shared.startForPlayback()` succeeds, even
    /// before any explicit per-bank load (multiChannel preloads
    /// Acoustic Grand into samplers[0] at construction).
    public var isLoaded: Bool { multiChannel != nil }

    /// Trigger a note on `samplers[0]`.
    ///
    /// `channel` is accepted for protocol conformance but ignored —
    /// touch input always plays on channel 0 (the spec dedicates
    /// `samplers[0]` to touch input).
    public func playNote(midiNote: UInt8, velocity: UInt8, channel: UInt8) {
        guard let mc = multiChannel else {
            MultiChannelLog.shared.log(
                .warning,
                "MultiChannelTouchSoundFont.playNote: multiChannel not ready, ignored (midi=\(midiNote))"
            )
            return
        }
        mc.playTouchNote(midiNote, velocity: velocity)
    }

    /// Stop a note on `samplers[0]`. `channel` is ignored — see `playNote`.
    public func stopNote(midiNote: UInt8, channel: UInt8) {
        guard let mc = multiChannel else {
            MultiChannelLog.shared.log(
                .warning,
                "MultiChannelTouchSoundFont.stopNote: multiChannel not ready, ignored (midi=\(midiNote))"
            )
            return
        }
        mc.stopTouchNote(midiNote)
    }

    /// Stop every active note on `samplers[0]`.
    public func stopAllNotes() {
        guard let mc = multiChannel else {
            MultiChannelLog.shared.log(
                .warning,
                "MultiChannelTouchSoundFont.stopAllNotes: multiChannel not ready, ignored"
            )
            return
        }
        mc.stopAllTouchNotes()
    }

    public init() {}

    private var multiChannel: ProductionMultiChannelEngine? {
        AudioEngineManager.shared.multiChannel
    }
}
