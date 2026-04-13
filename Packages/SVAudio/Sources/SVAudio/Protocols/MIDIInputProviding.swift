import Foundation

/// Protocol for receiving live MIDI note events from a connected input device.
///
/// Abstracting CoreMIDI behind this protocol enables:
/// - Unit testing `PlayAlongViewModel` without real MIDI hardware.
/// - Future alternative sources (virtual MIDI, Bluetooth MIDI) without
///   changing the consumer.
///
/// ## Two delivery paths
///
/// - `onNoteEvent`: A direct `@Sendable` closure fired synchronously on CoreMIDI's
///   high-priority thread. Bypasses AsyncStream buffering and Swift's cooperative
///   scheduler for minimum latency (~1–3ms from keypress to closure call).
///   **The closure must dispatch UI work to `@MainActor` itself.**
///   Use this for latency-critical consumers (keyboard highlighting, scoring).
///
/// - `noteOnStream`: An `AsyncStream` that buffers events and delivers them via
///   Swift's cooperative scheduler. Suitable for non-latency-critical consumers
///   (analytics, logging, non-real-time UI). Kept for testability and backwards
///   compatibility.
///
/// Conforming types are `Sendable` I/O managers — they own no `@MainActor`
/// state directly. `isConnected` and `connectedDeviceName` are written on
/// the main actor by the implementation (via `Task { @MainActor in }`) and
/// must be read on the main actor by consumers.
public protocol MIDIInputProviding: AnyObject, Sendable {
    /// Whether at least one MIDI source is currently connected.
    ///
    /// Updated on the main actor. Read on the main actor by UI consumers.
    @MainActor
    var isConnected: Bool { get }

    /// Human-readable name of the first connected MIDI source, or nil if none.
    ///
    /// Updated on the main actor. Read on the main actor by UI consumers.
    @MainActor
    var connectedDeviceName: String? { get }

    /// Direct low-latency callback for MIDI note events.
    ///
    /// **Called synchronously on CoreMIDI's high-priority real-time thread.**
    /// The closure must be real-time-safe (no allocation, no blocking, no actor
    /// hops inside the closure itself). To update UI, dispatch via
    /// `Task(priority: .userInteractive) { @MainActor in ... }` inside the closure.
    ///
    /// Set to `nil` to unregister. Replaces the previous callback.
    /// This path eliminates the AsyncStream buffer + cooperative-scheduler
    /// resume overhead (~5–20 ms) for latency-critical consumers.
    var onNoteEvent: (@Sendable (MIDIInputEvent) -> Void)? { get set }

    /// Direct low-latency callback for MIDI Control Change events.
    ///
    /// **Called synchronously on CoreMIDI's high-priority real-time thread.**
    /// Delivers all CC messages (sustain pedal CC64, mod wheel CC1, volume CC7,
    /// etc.). Filter on `event.controller` for specific controllers.
    ///
    /// Primary use case: CC64 sustain pedal handling in play-along mode.
    var onControlChangeEvent: (@Sendable (MIDIControlChangeEvent) -> Void)? { get set }

    /// An async stream that yields MIDI note events from connected sources.
    ///
    /// Yields both note-on (velocity > 0) and note-off (velocity == 0) events.
    /// Consumers use `event.isNoteOn` to distinguish them and maintain a `Set`
    /// of currently-held keys for accurate chord display.
    /// The stream finishes when `stop()` is called.
    var noteOnStream: AsyncStream<MIDIInputEvent> { get }

    /// An async stream that yields `true` when a MIDI source connects and
    /// `false` when all sources disconnect.
    ///
    /// Consumers can use this to reactively update UI state without polling.
    /// The stream finishes when `stop()` is called.
    var connectionStateStream: AsyncStream<Bool> { get }

    /// Refresh the list of connected MIDI sources and start delivering events.
    ///
    /// Safe to call multiple times. Idempotent when already started.
    func start()

    /// Stop delivering events and finish the note stream.
    func stop()
}
