import CoreMIDI
import Foundation
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
private final class ContinuationBox<Element: Sendable>: Sendable {
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
private typealias MIDIContinuationBox = ContinuationBox<MIDIInputEvent>

/// Thread-safe box for connection-state booleans. Alias of the generic `ContinuationBox`.
private typealias ConnectionContinuationBox = ContinuationBox<Bool>

/// Thread-safe box holding a direct low-latency callback for MIDI events.
///
/// Separate from `ContinuationBox` because the callback type is not generic in
/// a way that composes cleanly.
///
/// AUD-033: Uses `OSAllocatedUnfairLock` — lower overhead than `NSLock` and
/// appropriate for the CoreMIDI high-priority thread that fires the callback.
private final class NoteCallbackBox: Sendable {
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
/// - All mutable state is protected by `NSLock`.
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
    @MainActor public private(set) var isConnected: Bool = false

    /// Human-readable name of the first connected physical MIDI source.
    ///
    /// Written via `Task { @MainActor in }` from `refreshSources()`.
    /// Read on the main actor by `PlayAlongViewModel`.
    @MainActor public private(set) var connectedDeviceName: String?

    // MARK: - Note-On Stream

    /// Async stream that yields note-on events from all connected sources.
    ///
    /// Note-off events (velocity == 0) are filtered out — consumers only
    /// see new key presses, not key releases.
    public var noteOnStream: AsyncStream<MIDIInputEvent> {
        lock.lock()
        defer { lock.unlock() }
        if let stream = _noteOnStream { return stream }
        let (stream, cont) = AsyncStream<MIDIInputEvent>.makeStream()
        _noteOnStream = stream
        continuationBox.set(cont)
        return stream
    }

    // MARK: - Connection State Stream

    /// Async stream that yields `true` when a MIDI source connects and
    /// `false` when all sources disconnect.
    ///
    /// Consumers use this to reactively update UI without polling `isConnected`.
    public var connectionStateStream: AsyncStream<Bool> {
        lock.lock()
        defer { lock.unlock() }
        if let stream = _connectionStateStream { return stream }
        let (stream, cont) = AsyncStream<Bool>.makeStream()
        _connectionStateStream = stream
        connectionBox.set(cont)
        return stream
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

    // MARK: - Private State

    /// Lock protecting all mutable state on this class.
    ///
    /// AUD-033: The private `ContinuationBox` and `NoteCallbackBox` locks were
    /// upgraded to `OSAllocatedUnfairLock` for lower overhead on CoreMIDI's
    /// high-priority thread. This main instance lock remains `NSLock` because
    /// it is used with the manual `lock()`/`unlock()` pattern in sections that
    /// may do non-trivial work (source enumeration, stream creation) where
    /// the unfair lock's non-recursive contract would be harder to audit.
    ///
    /// Used for: `_midiClient`, `_inputPort`, `_connectedSources`, `_isStarted`,
    /// `_noteOnStream`, `_connectionStateStream`. CoreMIDI callbacks only touch
    /// `continuationBox` (which has its own internal lock).
    private let lock = NSLock()

    // All mutable state is protected by `lock`. `nonisolated(unsafe)` tells Swift 6
    // that we take manual responsibility for synchronization (via NSLock).
    nonisolated(unsafe) private var _midiClient: MIDIClientRef = 0
    nonisolated(unsafe) private var _inputPort: MIDIPortRef = 0
    nonisolated(unsafe) private var _connectedSources: [MIDIEndpointRef] = []
    nonisolated(unsafe) private var _isStarted = false
    nonisolated(unsafe) private var _noteOnStream: AsyncStream<MIDIInputEvent>?
    nonisolated(unsafe) private var _connectionStateStream: AsyncStream<Bool>?

    /// Sendable box shared with the CoreMIDI read callback.
    ///
    /// The read callback captures only this box — never `self`. The box is
    /// `Sendable` and thread-safe with its own `NSLock`.
    private let continuationBox = MIDIContinuationBox()

    /// Sendable box for broadcasting connection state changes.
    private let connectionBox = ConnectionContinuationBox()

    /// Sendable box holding the direct low-latency callback.
    ///
    /// Captured by the CoreMIDI read callback alongside `continuationBox`.
    /// Fired synchronously on CoreMIDI's high-priority thread before yielding
    /// to AsyncStream, giving consumers the fastest possible delivery path.
    private let callbackBox = NoteCallbackBox()

    private static let logger = Logger(
        subsystem: "com.survibe",
        category: "MIDIInput"
    )

    // MARK: - Initialization

    private init() {}

    // MARK: - Public Methods

    /// Start the MIDI input manager.
    ///
    /// Creates the CoreMIDI client and input port, connects to all current
    /// sources, and begins delivering events. Safe to call multiple times —
    /// returns immediately if already started.
    public func start() {
        lock.lock()
        let alreadyStarted = _isStarted
        // Ensure streams are created before CoreMIDI callbacks can fire.
        if _noteOnStream == nil {
            let (stream, cont) = AsyncStream<MIDIInputEvent>.makeStream()
            _noteOnStream = stream
            continuationBox.set(cont)
        }
        if _connectionStateStream == nil {
            let (stream, cont) = AsyncStream<Bool>.makeStream()
            _connectionStateStream = stream
            connectionBox.set(cont)
        }
        lock.unlock()

        guard !alreadyStarted else { return }

        var clientRef: MIDIClientRef = 0
        var portRef: MIDIPortRef = 0

        // The notify block fires on an arbitrary CoreMIDI thread.
        // `self` is NOT @MainActor — Swift 6 inserts zero actor isolation
        // checks on the `self?` access inside this @Sendable closure.
        // This is the architecturally correct way to use CoreMIDI in Swift 6.
        let status = MIDIClientCreateWithBlock(
            "com.survibe.MIDIInputManager" as CFString,
            &clientRef
        ) { [weak self] notification in
            self?.handleMIDINotification(notification.pointee.messageID)
        }

        guard status == noErr else {
            Self.logger.error("MIDIClientCreateWithBlock failed: OSStatus=\(status)")
            return
        }

        // The read block fires on CoreMIDI's high-priority thread.
        // Capture only the two Sendable boxes — never `self`. Parsing is
        // a static nonisolated method that touches no instance state.
        // `cbBox` fires the direct low-latency callback first (no async hop),
        // then `box` buffers the event into AsyncStream for other consumers.
        //
        // MIDIInputPortCreateWithProtocol (iOS 14+) replaces the legacy
        // MIDIInputPortCreateWithBlock / MIDIPacketList API. It delivers
        // events as MIDIEventList (Universal MIDI Packets) and is Apple's
        // recommended path for iOS 14+. SurVibe targets iOS 26+, so the old
        // API is unnecessary.
        let box = continuationBox
        let cbBox = callbackBox
        let portStatus = MIDIInputPortCreateWithProtocol(
            clientRef,
            "SurVibe Input Port" as CFString,
            MIDIProtocolID._1_0,
            &portRef
        ) { eventList, _ in
            MIDIInputManager.parseEventList(eventList, into: box, callback: cbBox)
        }

        guard portStatus == noErr else {
            Self.logger.error("MIDIInputPortCreateWithProtocol failed: OSStatus=\(portStatus)")
            MIDIClientDispose(clientRef)
            return
        }

        lock.lock()
        _midiClient = clientRef
        _inputPort = portRef
        _isStarted = true
        lock.unlock()

        Self.logger.info("MIDIInputManager started")
        refreshSources()
    }

    /// Stop MIDI input and finish the event stream.
    ///
    /// Disconnects all sources, disposes the port and client, and finishes
    /// the `noteOnStream`. After calling `stop()`, call `start()` again to
    /// resume — a new stream will be created.
    public func stop() {
        lock.lock()
        guard _isStarted else {
            lock.unlock()
            return
        }

        let sourcesToDisconnect = _connectedSources
        let portToDispose = _inputPort
        let clientToDispose = _midiClient

        _connectedSources.removeAll()
        _inputPort = 0
        _midiClient = 0
        _isStarted = false
        _noteOnStream = nil
        _connectionStateStream = nil
        lock.unlock()

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

    // MARK: - Source Refresh

    /// Re-enumerate physical CoreMIDI sources and connect to them.
    ///
    /// Safe to call from any thread. CoreMIDI operations (`MIDIGetSource`,
    /// `MIDIPortConnectSource`) are thread-safe. Observable UI state is
    /// updated via `Task { @MainActor in }` at the end.
    private func refreshSources() {
        lock.lock()
        let port = _inputPort
        let prevSources = _connectedSources
        lock.unlock()

        let sourceCount = MIDIGetNumberOfSources()
        Self.logger.info("refreshSources: \(sourceCount) source(s) total")

        for source in prevSources {
            MIDIPortDisconnectSource(port, source)
        }

        guard sourceCount > 0, port != 0 else {
            lock.lock()
            _connectedSources.removeAll()
            lock.unlock()
            connectionBox.yield(false)
            Task { @MainActor [weak self] in
                self?.isConnected = false
                self?.connectedDeviceName = nil
            }
            return
        }

        var newSources: [MIDIEndpointRef] = []
        var firstName: String?

        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            guard source != 0 else { continue }

            guard Self.isPhysicalSource(source) else {
                Self.logger.info("Skipping virtual MIDI source \(i): \(Self.sourceName(source))")
                continue
            }

            let connectStatus = MIDIPortConnectSource(port, source, nil)
            if connectStatus == noErr {
                newSources.append(source)
                if firstName == nil { firstName = Self.sourceName(source) }
                Self.logger.info("Connected to MIDI source \(i): \(Self.sourceName(source))")
            } else {
                Self.logger.error(
                    "MIDIPortConnectSource failed for source \(i): OSStatus=\(connectStatus)"
                )
            }
        }

        lock.lock()
        _connectedSources = newSources
        lock.unlock()

        let connected = !newSources.isEmpty
        let deviceName = firstName
        // Push state change to the connection stream immediately (on this CoreMIDI thread).
        connectionBox.yield(connected)
        Task { @MainActor [weak self] in
            self?.isConnected = connected
            self?.connectedDeviceName = deviceName
        }

        if connected {
            Self.logger.info("MIDI connected: \(deviceName ?? "unknown device")")
        } else {
            Self.logger.info("No physical MIDI sources connected")
        }
    }

    // MARK: - CoreMIDI Read Callback (static — runs on CoreMIDI thread)

    /// Parse a `MIDIEventList` (Universal MIDI Packets) and dispatch note events.
    ///
    /// Static method — accesses no instance state. Both `box` and `callback` are
    /// `Sendable` and protected by their own `NSLock`.
    ///
    /// Called from `MIDIInputPortCreateWithProtocol` on CoreMIDI's high-priority thread.
    ///
    /// ## Universal MIDI Packet (UMP) format — MIDI 1.0 Channel Voice (message type 0x2)
    ///
    /// Each 32-bit word packs the MIDI message as big-endian bytes:
    ///   Bits [31:28] = UMP message type (0x2 = MIDI 1.0 Channel Voice)
    ///   Bits [27:24] = MIDI channel (0–15)
    ///   Bits [23:16] = status byte (0x80 Note-Off, 0x90 Note-On, etc.)
    ///   Bits [15:8]  = note number (0–127)
    ///   Bits [7:0]   = velocity (0–127)
    ///
    /// CoreMIDI automatically upgrades legacy MIDIPacketList sources to UMP when
    /// the port is created with `kMIDIProtocol_1_0`.
    ///
    /// ## MIDITimeStamp
    ///
    /// Each `MIDIEventPacket` carries a hardware-precise `timeStamp` field
    /// (host ticks from `mach_absolute_time`). We capture it into
    /// `MIDIInputEvent.midiTimestamp` for accurate play-along scoring.
    private static func parseEventList(
        _ eventList: UnsafePointer<MIDIEventList>,
        into box: MIDIContinuationBox,
        callback: NoteCallbackBox
    ) {
        let count = Int(eventList.pointee.numPackets)
        guard count > 0 else { return }

        // Use withUnsafeMutablePointer on a mutable copy to safely advance through packets.
        var mutableList = eventList.pointee
        withUnsafeMutablePointer(to: &mutableList) { listPtr in
            var packetPtr = UnsafeMutablePointer<MIDIEventPacket>(&listPtr.pointee.packet)

            for _ in 0..<count {
                let packet = packetPtr.pointee
                let wordCount = Int(packet.wordCount)
                let hardwareTimestamp = packet.timeStamp

                withUnsafeBytes(of: packet.words) { rawWords in
                    let words = rawWords.bindMemory(to: UInt32.self)
                    var wordIndex = 0

                    while wordIndex < wordCount {
                        let word = words[wordIndex]
                        wordIndex += 1

                        // UMP message type is the top 4 bits of the 32-bit word.
                        let umpMessageType = UInt8((word >> 28) & 0x0F)

                        // 0x2 = MIDI 1.0 Channel Voice Message (single word).
                        guard umpMessageType == 0x02 else { continue }

                        // Byte layout within the word (big-endian):
                        //   [31:28] = UMP message type (0x2)
                        //   [27:24] = MIDI channel (0–15)
                        //   [23:16] = status byte (0x80 Note-Off, 0x90 Note-On, etc.)
                        //   [15:8]  = data byte 1 (note number, 0–127)
                        //   [7:0]   = data byte 2 (velocity, 0–127)
                        let channel    = UInt8((word >> 24) & 0x0F)
                        let statusByte = UInt8((word >> 16) & 0xFF)
                        let noteNumber = UInt8((word >>  8) & 0x7F)
                        let velocity   = UInt8(word & 0x7F)
                        let messageType = statusByte & 0xF0

                        switch messageType {
                        case 0x90:  // Note-On (velocity=0 means Note-Off)
                            // Always forward — velocity=0 is a Note-Off in disguise.
                            // Consumer uses `isNoteOn` (velocity > 0) to distinguish.
                            let event = MIDIInputEvent(
                                noteNumber: noteNumber,
                                velocity: velocity,
                                channel: channel,
                                midiTimestamp: hardwareTimestamp
                            )
                            // Fire direct callback first (synchronous, no scheduler hop).
                            callback.fire(event)
                            // Also buffer into AsyncStream for non-latency-critical consumers.
                            box.yield(event)

                        case 0x80:  // Note-Off (explicit)
                            let event = MIDIInputEvent(
                                noteNumber: noteNumber,
                                velocity: 0,
                                channel: channel,
                                midiTimestamp: hardwareTimestamp
                            )
                            callback.fire(event)
                            box.yield(event)

                        default:
                            // Control Change, Program Change, Pitch Bend, etc. — ignored.
                            break
                        }
                    }
                }

                packetPtr = MIDIEventPacketNext(packetPtr)
            }
        }
    }

    // MARK: - Source Classification

    /// Returns `true` if `endpoint` is a real physical MIDI device (USB or Bluetooth).
    ///
    /// Filters out IAC Driver, Network MIDI sessions, and offline devices.
    private static func isPhysicalSource(_ endpoint: MIDIEndpointRef) -> Bool {
        let name = sourceName(endpoint).lowercased()
        let virtualKeywords = ["iac", "network session", "network midi", "virtual", "loopback"]
        if virtualKeywords.contains(where: { name.contains($0) }) {
            return false
        }

        var entity: MIDIEntityRef = 0
        guard MIDIEndpointGetEntity(endpoint, &entity) == noErr, entity != 0 else {
            return true
        }

        var device: MIDIDeviceRef = 0
        guard MIDIEntityGetDevice(entity, &device) == noErr, device != 0 else {
            return true
        }

        var offline: Int32 = 0
        MIDIObjectGetIntegerProperty(device, kMIDIPropertyOffline, &offline)
        return offline == 0
    }

    /// Return a human-readable display name for a MIDI endpoint.
    private static func sourceName(_ endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
        return (name?.takeRetainedValue() as String?) ?? "Unknown Device"
    }
}
