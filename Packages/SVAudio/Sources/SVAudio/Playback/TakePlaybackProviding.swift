import Foundation

/// Transport surface for the Play tab v2 take-playback engine.
///
/// Implemented by `TakePlaybackEngine`; injected as a protocol so the
/// `PlayTab` view-model can be instantiated with a mock for unit tests
/// without spinning up `AVAudioEngine`.
@MainActor
public protocol TakePlaybackProviding: AnyObject {
    /// Loads a snapshot for playback.
    ///
    /// Filters notes by `handFilter`, scales onset/offset times by `speed`,
    /// re-encodes via `MIDISerializer.serializeType0`, and loads the result
    /// into the underlying `AVAudioSequencer` with every track wired to the
    /// playback sampler slot. `saMidi` is reserved for future shifting; the
    /// current implementation passes it through unchanged.
    ///
    /// - Parameters:
    ///   - snapshot: Take to play back.
    ///   - speed: Playback rate (1.0 = normal, 2.0 = 2× faster).
    ///   - handFilter: Treble-only / bass-only / both.
    ///   - saMidi: Sa MIDI note (reserved for future pitch shifting).
    func schedule(snapshot: TakeSnapshot, speed: Double, handFilter: HandFilter, saMidi: UInt8) async

    /// Starts the sequencer + visual highlight loop.
    func play()
    /// Stops the sequencer at the current position; pauseable.
    func pause()
    /// Seeks the sequencer to `sec` (in playback seconds, post-`speed`).
    func seek(to sec: TimeInterval)
    /// Stops the sequencer, rewinds to 0, and clears any lit highlights.
    func stop()

    /// Whether the sequencer is currently playing.
    var isPlaying: Bool { get }
    /// Current playback position in seconds (post-`speed`).
    var currentPositionSec: TimeInterval { get }
}
