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

    // MARK: - Delivery Mode

    /// Controls how events are delivered to the subscriber.
    public enum DeliveryMode: Sendable {
        /// Deliver synchronously on the caller's thread (minimum latency).
        case synchronous
        /// Deliver via `Task { @MainActor in }` for safe UI updates.
        case mainActor
    }

    /// The delivery mode for subscriber invocation.
    public let deliveryMode: DeliveryMode

    // MARK: - Subscriber

    /// Lock-protected subscriber closure for thread-safe delivery.
    private let subscriberLock = OSAllocatedUnfairLock<(@Sendable (PerformanceEvent) -> Void)?>(
        initialState: nil
    )

    /// The subscriber closure that receives unified performance events.
    ///
    /// Set this before wiring input sources. When `deliveryMode` is `.synchronous`,
    /// the closure is called on the thread that delivers the event (CoreMIDI thread
    /// for MIDI, DSP task for mic). When `.mainActor`, delivery is wrapped in
    /// `Task { @MainActor in }`.
    public var subscriber: (@Sendable (PerformanceEvent) -> Void)? {
        get { subscriberLock.withLock { $0 } }
        set { subscriberLock.withLock { $0 = newValue } }
    }

    // MARK: - Expression Subscriber

    /// Lock-protected expression subscriber for thread-safe delivery.
    private let expressionSubscriberLock = OSAllocatedUnfairLock<(@Sendable (ExpressionResult) -> Void)?>(
        initialState: nil
    )

    /// Subscriber closure that receives expression analysis results.
    ///
    /// Expression events are delivered separately from note events because
    /// pitch bend messages arrive at ~100+ Hz during bends and should not
    /// slow down note processing.
    public var expressionSubscriber: (@Sendable (ExpressionResult) -> Void)? {
        get { expressionSubscriberLock.withLock { $0 } }
        set { expressionSubscriberLock.withLock { $0 = newValue } }
    }

    /// Deliver an expression analysis result to the expression subscriber.
    ///
    /// Uses the same delivery mode as note events (synchronous or mainActor).
    ///
    /// - Parameter result: Expression classification from MIDIExpressionAnalyzer.
    public func deliverExpression(_ result: ExpressionResult) {
        switch deliveryMode {
        case .synchronous:
            expressionSubscriberLock.withLock { $0?(result) }
        case .mainActor:
            let handler = expressionSubscriberLock.withLock { $0 }
            guard let handler else { return }
            Task(priority: .userInteractive) { @MainActor in
                handler(result)
            }
        }
    }

    // MARK: - Logger

    private static let logger = Logger.survibe(category: "PerformanceEngine")

    // MARK: - Initialization

    /// Create a new performance engine.
    ///
    /// - Parameter deliveryMode: How events reach the subscriber.
    ///   `.synchronous` (default) for minimum latency; `.mainActor` for
    ///   safe UI updates without manual dispatch.
    public init(deliveryMode: DeliveryMode = .synchronous) {
        self.deliveryMode = deliveryMode
    }

    // MARK: - Event Delivery

    /// Deliver a unified performance event to the subscriber.
    ///
    /// In `.synchronous` mode, calls the subscriber directly on the caller's
    /// thread (CoreMIDI or DSP) for minimum latency. In `.mainActor` mode,
    /// wraps the call in `Task { @MainActor in }` for safe UI updates.
    ///
    /// - Parameter event: The performance event to deliver.
    public func deliver(_ event: PerformanceEvent) {
        switch deliveryMode {
        case .synchronous:
            subscriberLock.withLock { $0?(event) }
        case .mainActor:
            let handler = subscriberLock.withLock { $0 }
            guard let handler else { return }
            Task(priority: .userInteractive) { @MainActor in
                handler(event)
            }
        }
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

    /// Deliver a pitch bend event by wrapping in ``PerformanceEvent``.
    ///
    /// Convenience method for routing pitch bend through the unified pipeline.
    ///
    /// - Parameter event: The MIDI pitch bend event.
    public func deliverPitchBend(_ event: MIDIPitchBendEvent) {
        deliver(.pitchBend(event: event))
    }

    /// Deliver a pressure event by wrapping in ``PerformanceEvent``.
    ///
    /// Convenience method for routing aftertouch through the unified pipeline.
    ///
    /// - Parameter event: The MIDI pressure event.
    public func deliverPressure(_ event: MIDIPressureEvent) {
        deliver(.pressure(event: event))
    }

    /// Deliver a program change event by wrapping in ``PerformanceEvent``.
    ///
    /// Convenience method for routing instrument changes through the unified pipeline.
    ///
    /// - Parameter event: The MIDI program change event.
    public func deliverProgramChange(_ event: MIDIProgramChangeEvent) {
        deliver(.programChange(event: event))
    }

    /// Clear the subscriber. Call when stopping the session.
    public func stop() {
        subscriber = nil
        expressionSubscriber = nil
        Self.logger.debug("PerformanceEngine stopped")
    }
}
