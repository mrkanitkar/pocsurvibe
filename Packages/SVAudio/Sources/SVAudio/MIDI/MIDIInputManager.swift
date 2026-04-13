import CoreMIDI
import Foundation
import Synchronization
import os

/// Thread-safe box holding an `AsyncStream` continuation of any type.
///
/// Generic over the element type so it can be reused for both note-on events
/// and connection-state booleans.
///
/// AUD-033: Uses `OSAllocatedUnfairLock` instead of `NSLock`.
/// `os_unfair_lock` is a mutex with adaptive spinning, lower overhead than
/// the Objective-C `NSLock` wrapper, and FIFO unfair semantics that prevent
/// priority inversion on high-priority CoreMIDI threads.
final class ContinuationBox<Element: Sendable>: Sendable {
    // AUD-033: OSAllocatedUnfairLock is lower overhead than NSLock.
    private let lock = OSAllocatedUnfairLock<AsyncStream<Element>.Continuation?>(initialState: nil)

    func set(_ cont: AsyncStream<Element>.Continuation?) {
        lock.withLock { $0 = cont }
    }

    func yield(_ element: Element) {
        lock.withLock { $0?.yield(element) }
    }

    func finish() {
        lock.withLock {
            $0?.finish()
            $0 = nil
        }
    }
}

/// Thread-safe box for MIDI note-on events. Alias of the generic `ContinuationBox`.
typealias MIDIContinuationBox = ContinuationBox<MIDIInputEvent>

/// Thread-safe box for connection-state booleans. Alias of the generic `ContinuationBox`.
typealias ConnectionContinuationBox = ContinuationBox<Bool>

/// Thread-safe box holding a direct low-latency callback for MIDI events.
///
/// Separate from `ContinuationBox` because the callback type is not generic in
/// a way that composes cleanly.
///
/// AUD-033: Uses `OSAllocatedUnfairLock` — lower overhead than `NSLock` and
/// appropriate for the CoreMIDI high-priority thread that fires the callback.
final class NoteCallbackBox: Sendable {
    // AUD-033: OSAllocatedUnfairLock wrapping the callback state directly.
    private let lock = OSAllocatedUnfairLock<(@Sendable (MIDIInputEvent) -> Void)?>(initialState: nil)

    func get() -> (@Sendable (MIDIInputEvent) -> Void)? {
        lock.withLock { $0 }
    }

    func set(_ cb: (@Sendable (MIDIInputEvent) -> Void)?) {
        lock.withLock { $0 = cb }
    }

    func fire(_ event: MIDIInputEvent) {
        lock.withLock { $0?(event) }
    }
}

/// Thread-safe box holding a direct low-latency callback for MIDI Control Change events.
final class CCCallbackBox: Sendable {
    private let lock = OSAllocatedUnfairLock<(@Sendable (MIDIControlChangeEvent) -> Void)?>(
        initialState: nil
    )

    func get() -> (@Sendable (MIDIControlChangeEvent) -> Void)? {
        lock.withLock { $0 }
    }

    func set(_ cb: (@Sendable (MIDIControlChangeEvent) -> Void)?) {
        lock.withLock { $0 = cb }
    }

    func fire(_ event: MIDIControlChangeEvent) {
        lock.withLock { $0?(event) }
    }
}

/// Thread-safe box holding an optional `EventLogging` reference.
final class EventLoggerBox: Sendable {
    private let lock = OSAllocatedUnfairLock<(any EventLogging)?>(initialState: nil)

    func get() -> (any EventLogging)? {
        lock.withLock { $0 }
    }

    func set(_ logger: (any EventLogging)?) {
        lock.withLock { $0 = logger }
    }
}

/// Manages live MIDI input from USB or Bluetooth MIDI devices using CoreMIDI.
///
/// ## Architecture: nonisolated I/O manager
///
/// This class is **not** `@MainActor`. CoreMIDI is a hardware I/O framework
/// that invokes all of its callbacks on its own internal threads:
///
/// - `MIDIClientCreateWithBlock` notify block — "called on an **arbitrary thread**;
///   thread-safety is the block's responsibility." (Apple documentation)
/// - `MIDIInputPortCreateWithBlock` read block — "called on a **separate
///   high-priority thread** owned by CoreMIDI." (Apple documentation)
///
/// Making the class `@MainActor` would cause Swift 6 to insert
/// `dispatch_assert_queue(main_actor_queue)` checks at every `self?` access
/// site inside `@Sendable` closures. CoreMIDI fires those closures on its own
/// threads, so the assertion always fails → `_dispatch_assert_queue_fail` /
/// `brk #0x1` crash.
///
/// The correct architecture (per Apple docs and Swift 6 concurrency):
/// - The I/O manager itself is a plain `nonisolated Sendable` class.
/// - All mutable state is consolidated into a single `Mutex<MIDIState>` struct
///   (ARCH-003), replacing 6 individual `nonisolated(unsafe)` properties + NSLock.
/// - Observable UI state (`isConnected`, `connectedDeviceName`) is annotated
///   `@MainActor` so the compiler verifies they are only **read** on the main
///   actor and only **written** via `Task { @MainActor in }`.
/// - CoreMIDI callbacks capture `[weak self]` directly. Because `self` is not
///   actor-isolated, Swift 6 inserts **zero** actor-isolation checks —
///   no bridging, no relay, no crash.
///
/// ## USB Connection (Yamaha PSR-400 and other class-compliant keyboards)
/// iOS treats USB MIDI devices as standard CoreMIDI sources — no special
/// entitlements or drivers required. When the keyboard is connected, CoreMIDI
/// fires `.msgObjectAdded`; `refreshSources()` re-enumerates and connects the
/// new source.
public final class MIDIInputManager: MIDIInputProviding {
    // MARK: - Singleton

    /// Shared singleton for use across the app.
    public static let shared = MIDIInputManager()

    // MARK: - Observable UI State (main actor)

    /// Whether at least one physical MIDI source is currently connected and active.
    ///
    /// Written via `Task { @MainActor in }` from `refreshSources()`.
    /// Read on the main actor by `PlayAlongViewModel`.
    @MainActor public internal(set) var isConnected: Bool = false

    /// Human-readable name of the first connected physical MIDI source.
    ///
    /// Written via `Task { @MainActor in }` from `refreshSources()`.
    /// Read on the main actor by `PlayAlongViewModel`.
    @MainActor public internal(set) var connectedDeviceName: String?

    // MARK: - Note-On Stream

    /// Async stream that yields note-on events from all connected sources.
    ///
    /// Note-off events (velocity == 0) are filtered out — consumers only
    /// see new key presses, not key releases.
    public var noteOnStream: AsyncStream<MIDIInputEvent> {
        // Two-phase to avoid nested lock: Mutex holds state, continuationBox has its own lock.
        let result: (stream: AsyncStream<MIDIInputEvent>, newCont: AsyncStream<MIDIInputEvent>.Continuation?) =
            state.withLock { s in
                if let stream = s.noteOnStream { return (stream, nil) }
                let (stream, cont) = AsyncStream<MIDIInputEvent>.makeStream()
                s.noteOnStream = stream
                return (stream, cont)
            }
        if let cont = result.newCont {
            continuationBox.set(cont)
        }
        return result.stream
    }

    // MARK: - Connection State Stream

    /// Async stream that yields `true` when a MIDI source connects and
    /// `false` when all sources disconnect.
    ///
    /// Consumers use this to reactively update UI without polling `isConnected`.
    public var connectionStateStream: AsyncStream<Bool> {
        // Two-phase to avoid nested lock: Mutex holds state, connectionBox has its own lock.
        let result: (stream: AsyncStream<Bool>, newCont: AsyncStream<Bool>.Continuation?) =
            state.withLock { s in
                if let stream = s.connectionStateStream { return (stream, nil) }
                let (stream, cont) = AsyncStream<Bool>.makeStream()
                s.connectionStateStream = stream
                return (stream, cont)
            }
        if let cont = result.newCont {
            connectionBox.set(cont)
        }
        return result.stream
    }

    // MARK: - Direct Low-Latency Callback

    /// Direct `@Sendable` callback fired synchronously on CoreMIDI's high-priority thread.
    ///
    /// Set this before calling `start()` to receive MIDI events with minimum latency.
    /// The closure is called with no actor hop — it must dispatch UI work to `@MainActor`
    /// itself (e.g., `Task(priority: .userInteractive) { @MainActor in ... }`).
    ///
    /// The AsyncStream `noteOnStream` also receives every event, so both paths are active
    /// simultaneously. The direct callback path is approximately 5–20ms faster than the
    /// AsyncStream path under typical load.
    public var onNoteEvent: (@Sendable (MIDIInputEvent) -> Void)? {
        get { callbackBox.get() }
        set { callbackBox.set(newValue) }
    }

    /// Direct `@Sendable` callback for MIDI Control Change messages (CC).
    public var onControlChangeEvent: (@Sendable (MIDIControlChangeEvent) -> Void)? {
        get { ccCallbackBox.get() }
        set { ccCallbackBox.set(newValue) }
    }

    /// Optional event logger for persisting MIDI events to SwiftData.
    public var eventLogger: (any EventLogging)? {
        get { eventLoggerBox.get() }
        set { eventLoggerBox.set(newValue) }
    }

    // MARK: - Private State

    /// All mutable MIDI state consolidated into a single Mutex-protected struct.
    ///
    /// Replaces 6 individual `nonisolated(unsafe)` properties + manual NSLock
    /// (ARCH-003). `Mutex.withLock` provides scoped, deadlock-safe access per
    /// Apple's Synchronization framework (WWDC 2024).
    ///
    /// Thread safety: CoreMIDI callbacks access state via `withLock` closures.
    /// No property is accessed outside a lock scope.
    let state = Mutex(MIDIState())

    /// Consolidated mutable state for MIDIInputManager.
    ///
    /// All fields were previously individual `nonisolated(unsafe)` properties
    /// protected by a manual `NSLock`. Grouping them into a single struct
    /// inside `Mutex` eliminates all `nonisolated(unsafe)` annotations and
    /// ensures every access is scoped to a `withLock` closure.
    struct MIDIState: Sendable {
        var midiClient: MIDIClientRef = 0
        var inputPort: MIDIPortRef = 0
        var connectedSources: [MIDIEndpointRef] = []
        var isStarted = false
        var noteOnStream: AsyncStream<MIDIInputEvent>?
        var connectionStateStream: AsyncStream<Bool>?
    }

    /// Sendable box shared with the CoreMIDI read callback.
    ///
    /// The read callback captures only this box — never `self`. The box is
    /// `Sendable` and thread-safe with its own `NSLock`.
    let continuationBox = MIDIContinuationBox()

    /// Sendable box for broadcasting connection state changes.
    let connectionBox = ConnectionContinuationBox()

    /// De-jitter filter to suppress mechanical switch bounce on physical keyboards.
    ///
    /// Shared with the CoreMIDI read callback closure. Thread-safe via internal
    /// `Mutex<State>` -- safe to call from the high-priority CoreMIDI thread.
    let deJitterFilter = MIDIDeJitterFilter()

    /// Sendable box holding the direct low-latency callback.
    ///
    /// Captured by the CoreMIDI read callback alongside `continuationBox`.
    /// Fired synchronously on CoreMIDI's high-priority thread before yielding
    /// to AsyncStream, giving consumers the fastest possible delivery path.
    let callbackBox = NoteCallbackBox()

    /// Sendable box holding the direct low-latency Control Change callback.
    let ccCallbackBox = CCCallbackBox()

    /// Sendable box holding the optional event logger for persisting MIDI events.
    private let eventLoggerBox = EventLoggerBox()

    static let logger = Logger.survibe(category: "MIDIInput")

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Snapshot of stream state extracted inside `Mutex.withLock` for two-phase setup.
    private struct StartSnapshot: Sendable {
        var started: Bool = false
        var noteCont: AsyncStream<MIDIInputEvent>.Continuation?
        var connCont: AsyncStream<Bool>.Continuation?
    }

    /// Start the MIDI input manager.
    ///
    /// Creates the CoreMIDI client and input port, connects to all current
    /// sources, and begins delivering events. Safe to call multiple times —
    /// returns immediately if already started.
    public func start() {
        let snapshot = ensureStreamsCreated()
        guard !snapshot.started else { return }

        guard let (clientRef, portRef) = createMIDIClientAndPort() else { return }

        state.withLock { s in
            s.midiClient = clientRef
            s.inputPort = portRef
            s.isStarted = true
        }

        Self.logger.info("MIDIInputManager started")
        refreshSources()
    }

    /// Extract stream continuations inside Mutex, set them on boxes outside.
    private func ensureStreamsCreated() -> StartSnapshot {
        // Two-phase to avoid nested lock: extract continuations inside Mutex,
        // then set them on their boxes outside the Mutex scope.
        var snapshot = state.withLock { s -> StartSnapshot in
            var snap = StartSnapshot(started: s.isStarted)
            // Ensure streams are created before CoreMIDI callbacks can fire.
            if s.noteOnStream == nil {
                let (stream, cont) = AsyncStream<MIDIInputEvent>.makeStream()
                s.noteOnStream = stream
                snap.noteCont = cont
            }
            if s.connectionStateStream == nil {
                let (stream, cont) = AsyncStream<Bool>.makeStream()
                s.connectionStateStream = stream
                snap.connCont = cont
            }
            return snap
        }
        if let cont = snapshot.noteCont { continuationBox.set(cont) }
        if let cont = snapshot.connCont { connectionBox.set(cont) }
        return snapshot
    }

    /// Create the CoreMIDI client and input port. Returns nil on failure.
    private func createMIDIClientAndPort() -> (MIDIClientRef, MIDIPortRef)? {
        var clientRef: MIDIClientRef = 0
        var portRef: MIDIPortRef = 0

        // The notify block fires on an arbitrary CoreMIDI thread.
        // `self` is NOT @MainActor — Swift 6 inserts zero actor isolation
        // checks on the `self?` access inside this @Sendable closure.
        let status = MIDIClientCreateWithBlock(
            "com.survibe.MIDIInputManager" as CFString,
            &clientRef
        ) { [weak self] notification in
            self?.handleMIDINotification(notification.pointee.messageID)
        }

        guard status == noErr else {
            Self.logger.error("MIDIClientCreateWithBlock failed: OSStatus=\(status)")
            return nil
        }

        // The read block fires on CoreMIDI's high-priority thread.
        // Capture only Sendable boxes and the de-jitter filter — never `self`.
        let box = continuationBox
        let cbBox = callbackBox
        let ccBox = ccCallbackBox
        let djFilter = deJitterFilter
        let portStatus = MIDIInputPortCreateWithProtocol(
            clientRef,
            "SurVibe Input Port" as CFString,
            MIDIProtocolID._2_0,
            &portRef
        ) { eventList, _ in
            MIDIInputManager.parseEventList(
                eventList, into: box, callback: cbBox,
                ccCallback: ccBox, deJitter: djFilter
            )
        }

        guard portStatus == noErr else {
            Self.logger.error("MIDIInputPortCreateWithProtocol failed: OSStatus=\(portStatus)")
            MIDIClientDispose(clientRef)
            return nil
        }

        return (clientRef, portRef)
    }

    /// Stop MIDI input and finish the event stream.
    ///
    /// Disconnects all sources, disposes the port and client, and finishes
    /// the `noteOnStream`. After calling `stop()`, call `start()` again to
    /// resume — a new stream will be created.
    public func stop() {
        /// Snapshot of MIDI state captured inside `Mutex.withLock` for teardown.
        struct StopSnapshot: Sendable {
            var sources: [MIDIEndpointRef] = []
            var port: MIDIPortRef = 0
            var client: MIDIClientRef = 0
        }

        let snapshot = state.withLock { s -> StopSnapshot in
            guard s.isStarted else { return StopSnapshot() }

            var snap = StopSnapshot()
            snap.sources = s.connectedSources
            snap.port = s.inputPort
            snap.client = s.midiClient

            s.connectedSources.removeAll()
            s.inputPort = 0
            s.midiClient = 0
            s.isStarted = false
            s.noteOnStream = nil
            s.connectionStateStream = nil

            return snap
        }

        // Early return if we were not started.
        guard snapshot.port != 0 || snapshot.client != 0 || !snapshot.sources.isEmpty else {
            return
        }

        let sourcesToDisconnect = snapshot.sources
        let portToDispose = snapshot.port
        let clientToDispose = snapshot.client

        for source in sourcesToDisconnect {
            MIDIPortDisconnectSource(portToDispose, source)
        }
        if portToDispose != 0 { MIDIPortDispose(portToDispose) }
        if clientToDispose != 0 { MIDIClientDispose(clientToDispose) }

        // Finish both streams (thread-safe — each box has its own lock).
        continuationBox.finish()
        connectionBox.finish()

        // Update UI state on main actor.
        Task { @MainActor [weak self] in
            self?.isConnected = false
            self?.connectedDeviceName = nil
        }

        Self.logger.info("MIDIInputManager stopped")
    }

    // MARK: - CoreMIDI Notify Callback

    /// Handle a CoreMIDI hot-plug notification.
    ///
    /// Called directly on an arbitrary CoreMIDI thread.
    /// Because `self` is NOT `@MainActor`, Swift 6 inserts no actor checks here.
    private func handleMIDINotification(_ messageID: MIDINotificationMessageID) {
        switch messageID {
        case .msgObjectAdded, .msgObjectRemoved, .msgSetupChanged:
            Self.logger.info("MIDI notification: \(messageID.rawValue) — refreshing sources")
            refreshSources()
        default:
            break
        }
    }
}
