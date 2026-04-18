import Foundation
import Synchronization
import os

/// A fixed-size **Plain-Old-Data** record describing one expression-carrying
/// MIDI event (pitch bend, channel aftertouch, or per-note aftertouch).
///
/// Designed for real-time safety — every field is a value type, no heap
/// references, no `Optional<String>`, no reference counts to mutate.
/// This lets the CoreMIDI receive thread push instances into a lock-free
/// ring buffer without touching the Swift runtime allocator.
///
/// The record is large enough to reconstruct either a `MIDIPitchBendEvent`
/// or a `MIDIPressureEvent` on the consumer side.
public struct MIDIExpressionEventRecord: Sendable {

    /// Event discriminator for the tagged union.
    public enum Kind: UInt8, Sendable {
        case pitchBend = 0
        case channelPressure = 1
        case perNotePressure = 2
    }

    /// Which kind of event this record carries.
    public let kind: Kind

    /// MIDI channel (0–15).
    public let channel: UInt8

    /// Note number for per-note pressure; `0xFF` when the event is channel-wide.
    public let noteNumber: UInt8

    /// Pitch-bend raw value (14-bit signed range stored in 32 bits), or 0 for
    /// pressure events. Range roughly ±8192 for MIDI 1.0, ±2^31 for MIDI 2.0.
    public let pitchBendValue: Int32

    /// Pressure raw value (full 32-bit MIDI-2 resolution), or 0 for pitch bend.
    public let pressureValue: UInt32

    /// `true` when the source was MIDI 2.0 (32-bit pitch bend); `false` for
    /// MIDI 1.0 (14-bit pitch bend). Ignored for pressure records.
    public let isMIDI2PitchBend: Bool

    /// Hardware mach timestamp (`MIDITimeStamp`). 0 if absent.
    public let midiTimestamp: UInt64

    /// Construct a pitch-bend record.
    public static func pitchBend(
        value: Int32,
        noteNumber: UInt8?,
        channel: UInt8,
        isMIDI2: Bool,
        timestamp: UInt64
    ) -> Self {
        MIDIExpressionEventRecord(
            kind: .pitchBend,
            channel: channel,
            noteNumber: noteNumber ?? 0xFF,
            pitchBendValue: value,
            pressureValue: 0,
            isMIDI2PitchBend: isMIDI2,
            midiTimestamp: timestamp
        )
    }

    /// Construct an aftertouch / pressure record.
    public static func pressure(
        value: UInt32,
        noteNumber: UInt8?,
        channel: UInt8,
        isPerNote: Bool,
        timestamp: UInt64
    ) -> Self {
        MIDIExpressionEventRecord(
            kind: isPerNote ? .perNotePressure : .channelPressure,
            channel: channel,
            noteNumber: noteNumber ?? 0xFF,
            pitchBendValue: 0,
            pressureValue: value,
            isMIDI2PitchBend: false,
            midiTimestamp: timestamp
        )
    }
}

/// Lock-free single-producer, single-consumer ring buffer of
/// `MIDIExpressionEventRecord` values.
///
/// Matches the contract used by `SPSCRingBuffer` on the audio side:
///
/// - **Producer** (CoreMIDI receive thread) calls `tryWrite(_:)` only.
/// - **Consumer** (dedicated `DispatchQueue`) calls `drain(into:)` only.
///
/// Storage is pre-allocated once; `tryWrite` never allocates. Capacity is
/// rounded up to a power of two so indexing uses a bitmask.
///
/// **Why this exists:** Apple's `MIDIReceiveBlock` runs on a system-owned,
/// small-stack, real-time thread. Calling `DispatchQueue.async { ... }` or
/// `Task { ... }` from that thread risks overflowing the guard page via
/// `swift_getGenericMetadata` — observed three times in production (crashes
/// #3, #4, #5 in the 2026-04-17 meend-test session). Using a ring buffer
/// means the receive thread only does pointer arithmetic + an atomic store
/// before returning. All the generic, allocating, locking work happens on
/// the consumer thread where the stack is large enough.
public final class MIDIExpressionRing: Sendable {

    // MARK: - Storage

    /// Fixed-capacity storage. Pre-allocated in init, deallocated in deinit.
    ///
    /// `nonisolated(unsafe)` is justified by the SPSC contract: only the
    /// producer touches its slot (via `writeIndex & mask`) and only the
    /// consumer touches its slot (via `readIndex & mask`); atomic indices
    /// with release/acquire ordering guarantee visibility. No two threads
    /// ever read/write the same slot concurrently.
    nonisolated(unsafe) private let storage: UnsafeMutableBufferPointer<MIDIExpressionEventRecord>

    /// Power-of-two capacity, equal to the size of `storage`.
    private let capacity: Int

    /// `capacity - 1`; used for fast modular indexing.
    private let mask: Int

    // MARK: - Atomic indices

    /// Producer write cursor (monotonically increasing; wrap via `& mask`).
    private let writeIndex: Atomic<Int>

    /// Consumer read cursor.
    private let readIndex: Atomic<Int>

    /// Count of records dropped because the ring was full when the producer
    /// tried to write. Useful for diagnostics — a non-zero value means the
    /// consumer is falling behind.
    private let droppedCount: Atomic<Int>

    // MARK: - Init / deinit

    /// Create a ring buffer with at least `capacity` slots (rounded up to the
    /// next power of two, minimum 256).
    public init(capacity: Int = 1024) {
        var rounded = max(256, capacity)
        if rounded & (rounded - 1) != 0 {
            var v = rounded - 1
            v |= v >> 1; v |= v >> 2; v |= v >> 4; v |= v >> 8; v |= v >> 16; v |= v >> 32
            rounded = v + 1
        }
        self.capacity = rounded
        self.mask = rounded - 1
        self.storage = UnsafeMutableBufferPointer<MIDIExpressionEventRecord>
            .allocate(capacity: rounded)
        // Note: storage starts uninitialised; we only read slots we've written.
        self.writeIndex = Atomic<Int>(0)
        self.readIndex = Atomic<Int>(0)
        self.droppedCount = Atomic<Int>(0)
    }

    deinit {
        storage.deallocate()
    }

    // MARK: - Producer

    /// Push one event record into the ring. Returns `true` on success, `false`
    /// if the ring is full (the record is then dropped and `droppedCount` is
    /// incremented).
    ///
    /// **Real-time safe.** No locks, no allocation, no Swift runtime metadata
    /// paths that hit contended caches.
    @discardableResult
    public func tryWrite(_ record: MIDIExpressionEventRecord) -> Bool {
        let w = writeIndex.load(ordering: .relaxed)
        let r = readIndex.load(ordering: .acquiring)
        // Full when the producer is exactly `capacity` ahead of the consumer.
        if w &- r >= capacity {
            _ = droppedCount.wrappingAdd(1, ordering: .relaxed)
            return false
        }
        storage[w & mask] = record
        writeIndex.store(w &+ 1, ordering: .releasing)
        return true
    }

    // MARK: - Consumer

    /// Drain every available record into `out` and return the number consumed.
    ///
    /// The destination is a caller-provided, pre-allocated buffer. No
    /// allocation inside this method.
    @discardableResult
    public func drain(
        into out: UnsafeMutableBufferPointer<MIDIExpressionEventRecord>
    ) -> Int {
        let w = writeIndex.load(ordering: .acquiring)
        let r = readIndex.load(ordering: .relaxed)
        let available = w &- r
        guard available > 0, let outBase = out.baseAddress else { return 0 }
        let take = min(available, out.count)
        for i in 0..<take {
            outBase[i] = storage[(r &+ i) & mask]
        }
        readIndex.store(r &+ take, ordering: .releasing)
        return take
    }

    // MARK: - Diagnostics

    /// Number of records the producer has dropped because the ring was full
    /// since construction. Monotonically increasing.
    public var droppedEventCount: Int {
        droppedCount.load(ordering: .relaxed)
    }

    /// Approximate current queue depth. Can be observed from any thread.
    public var pendingCount: Int {
        let w = writeIndex.load(ordering: .relaxed)
        let r = readIndex.load(ordering: .relaxed)
        return max(0, w &- r)
    }
}
