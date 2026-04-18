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

    /// Direct low-latency callback for MIDI pitch bend events.
    ///
    /// **Called synchronously on CoreMIDI's high-priority real-time thread.**
    /// Delivers both channel-wide and per-note pitch bend messages.
    var onPitchBendEvent: (@Sendable (MIDIPitchBendEvent) -> Void)? { get set }

    /// Direct low-latency callback for MIDI pressure (aftertouch) events.
    ///
    /// **Called synchronously on CoreMIDI's high-priority real-time thread.**
    /// Delivers both polyphonic key pressure and channel pressure messages.
    var onPressureEvent: (@Sendable (MIDIPressureEvent) -> Void)? { get set }

    /// Direct low-latency callback for MIDI program change events.
    ///
    /// **Called synchronously on CoreMIDI's high-priority real-time thread.**
    /// Delivers program (instrument) selection changes with optional bank select.
    var onProgramChangeEvent: (@Sendable (MIDIProgramChangeEvent) -> Void)? { get set }

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

    /// Whether this provider replays recorded data rather than live MIDI input.
    ///
    /// Default is `false` (live input). `PracticeReplayEngine` conformances
    /// return `true` to let consumers distinguish replay from live sources.
    var isReplaySource: Bool { get }

    /// Names of all available physical MIDI devices.
    @MainActor var availableDeviceNames: [String] { get }

    /// Name of the currently selected MIDI device.
    @MainActor var selectedDeviceName: String? { get }

    /// Select a MIDI device by name.
    ///
    /// - Parameter name: Device display name to select.
    func selectDevice(named name: String)
}

// MARK: - Default Implementation

extension MIDIInputProviding {
    /// Live input providers are not replay sources by default.
    public var isReplaySource: Bool { false }

    /// Default nil pitch bend callback for providers that do not support it.
    public var onPitchBendEvent: (@Sendable (MIDIPitchBendEvent) -> Void)? {
        get { nil }
        set { _ = newValue }
    }

    /// Default nil pressure callback for providers that do not support it.
    public var onPressureEvent: (@Sendable (MIDIPressureEvent) -> Void)? {
        get { nil }
        set { _ = newValue }
    }

    /// Default nil program change callback for providers that do not support it.
    public var onProgramChangeEvent: (@Sendable (MIDIProgramChangeEvent) -> Void)? {
        get { nil }
        set { _ = newValue }
    }

    /// Default empty device names for providers that don't support multi-device.
    @MainActor public var availableDeviceNames: [String] { [] }

    /// Default nil selected device for providers that don't support multi-device.
    @MainActor public var selectedDeviceName: String? { nil }

    /// Default no-op device selection for providers that don't support multi-device.
    public func selectDevice(named name: String) {}
}

// MARK: - Replay Source Protocol

/// A MIDI input source that can seek to arbitrary positions in recorded data.
///
/// Refines `MIDIInputProviding` for replay scenarios, adding seek capability
/// so consumers can jump to specific points in a recorded practice session.
public protocol ReplayMIDISource: MIDIInputProviding {
    /// Seek the replay cursor to the given session-relative timestamp.
    ///
    /// Events before this timestamp are skipped; the next delivered event
    /// will be the first one at or after `timestamp`.
    ///
    /// - Parameter timestamp: Session-relative time in seconds.
    func seek(to timestamp: Double)
}
