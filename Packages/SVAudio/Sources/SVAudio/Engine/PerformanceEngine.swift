import Foundation
import os

/// Unified real-time pipeline that routes both MIDI and microphone events
/// through a single subscriber interface.
///
/// ## Architecture
///
/// ```
/// MIDI callback ──→ PerformanceEngine ──→ subscriber closure
/// Mic pitch DSP ──→ PerformanceEngine ──→ subscriber closure
/// ```
///
/// Both input paths produce ``PerformanceEvent`` values. The engine serializes
/// events from concurrent sources (CoreMIDI thread, DSP task) and delivers them
/// to a single `@Sendable` subscriber closure. This unifies the measurement
/// point for latency probes — both paths flow through the same channel.
///
/// ## Thread Safety
///
/// The engine is `Sendable`. The subscriber closure is stored in an
/// `OSAllocatedUnfairLock` for lock-free-like access from CoreMIDI's
/// high-priority thread. Event delivery is synchronous on the caller's thread
/// (no actor hops) for minimum latency.
///
/// ## Usage
///
/// ```swift
/// let engine = PerformanceEngine()
/// engine.subscriber = { event in
///     // Process unified event (MIDI or mic)
/// }
/// // Wire MIDI:
/// midiInput.onNoteEvent = { midi in
///     engine.deliver(.from(midi))
/// }
/// // Wire mic:
/// for await pitch in pitchStream {
///     engine.deliver(.from(pitch))
/// }
/// ```
public final class PerformanceEngine: Sendable {

    // MARK: - Subscriber

    /// Lock-protected subscriber closure for thread-safe delivery.
    private let subscriberLock = OSAllocatedUnfairLock<(@Sendable (PerformanceEvent) -> Void)?>(
        initialState: nil
    )

    /// The subscriber closure that receives unified performance events.
    ///
    /// Set this before wiring input sources. The closure is called synchronously
    /// on the thread that delivers the event (CoreMIDI thread for MIDI, DSP task
    /// for mic). Implementations must be non-blocking.
    public var subscriber: (@Sendable (PerformanceEvent) -> Void)? {
        get { subscriberLock.withLock { $0 } }
        set { subscriberLock.withLock { $0 = newValue } }
    }

    // MARK: - Logger

    private static let logger = Logger.survibe(category: "PerformanceEngine")

    // MARK: - Initialization

    /// Create a new performance engine.
    public init() {}

    // MARK: - Event Delivery

    /// Deliver a unified performance event to the subscriber.
    ///
    /// Called from MIDI callback (CoreMIDI thread) or DSP task. Synchronous
    /// delivery with no actor hop for minimum latency. If no subscriber is
    /// registered, the event is silently dropped.
    ///
    /// - Parameter event: The performance event to deliver.
    public func deliver(_ event: PerformanceEvent) {
        subscriberLock.withLock { $0?(event) }
    }

    /// Deliver a MIDI input event by converting to ``PerformanceEvent``.
    ///
    /// Convenience method that wraps ``MIDIInputEvent`` conversion.
    ///
    /// - Parameter midiEvent: The raw MIDI event from CoreMIDI.
    public func deliverMIDI(_ midiEvent: MIDIInputEvent) {
        deliver(.from(midiEvent))
    }

    /// Deliver a pitch detection result by converting to ``PerformanceEvent``.
    ///
    /// Convenience method that wraps ``PitchResult`` conversion.
    ///
    /// - Parameter pitchResult: The pitch detection result from DSP.
    public func deliverPitch(_ pitchResult: PitchResult) {
        deliver(.from(pitchResult))
    }

    /// Clear the subscriber. Call when stopping the session.
    public func stop() {
        subscriber = nil
        Self.logger.debug("PerformanceEngine stopped")
    }
}
