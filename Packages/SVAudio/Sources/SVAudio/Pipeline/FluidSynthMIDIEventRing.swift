import Foundation
import Synchronization

/// Lock-free, single-producer / single-consumer ring buffer of `RealtimeMIDIEvent`s.
///
/// Producer: CoreMIDI receive callback (parses `MIDIPacketList`, posts
/// `RealtimeMIDIEvent`s) — runs on a high-priority CoreMIDI thread.
/// Consumer: the FluidSynth render block — runs on the CoreAudio realtime
/// thread, drains pending events at the start of each render call before
/// calling `fluid_synth_write_float`.
///
/// **Thread-safety contract**: exactly ONE producer thread calling
/// `enqueue`, exactly ONE consumer thread calling `dequeue`. Acquire/release
/// atomic ordering on the indices ensures the consumer sees fully-written
/// `RealtimeMIDIEvent`s before the index update is visible.
///
/// Capacity must be a power of two (we mask with capacity-1 for fast modulo).
/// Storage is pre-allocated; `enqueue` and `dequeue` never allocate.
public final class FluidSynthMIDIEventRing: @unchecked Sendable {

    /// `nonisolated(unsafe)` is justified by the SPSC contract: the producer
    /// only writes slot `writeIndex & mask`, the consumer only reads slot
    /// `readIndex & mask`. The atomic indices (acquire/release) ensure no
    /// two threads ever access the same slot concurrently.
    nonisolated(unsafe) private let storage: UnsafeMutableBufferPointer<RealtimeMIDIEvent>

    private let capacity: Int
    private let mask: Int
    private let writeIndex = Atomic<Int>(0)
    private let readIndex = Atomic<Int>(0)

    /// Creates a ring with the given power-of-two capacity. The ring stores
    /// at most `capacity - 1` events at any one time (one slot reserved to
    /// distinguish empty from full).
    public init(capacity: Int) {
        precondition(capacity > 1 && (capacity & (capacity - 1)) == 0,
                     "capacity must be a power of two > 1")
        self.capacity = capacity
        self.mask = capacity - 1
        self.storage = UnsafeMutableBufferPointer.allocate(capacity: capacity)
    }

    deinit {
        storage.deallocate()
    }

    /// Producer call. Returns `false` if the ring is full (caller should drop
    /// or back off — never block on the audio path).
    public func enqueue(_ event: RealtimeMIDIEvent) -> Bool {
        let w = writeIndex.load(ordering: .relaxed)
        let r = readIndex.load(ordering: .acquiring)
        let nextW = w &+ 1
        // Reserve one slot to distinguish empty from full: max stored = capacity - 1.
        if nextW &- r >= capacity {
            return false  // full
        }
        storage[w & mask] = event
        writeIndex.store(nextW, ordering: .releasing)
        return true
    }

    /// Consumer call. Returns the next event or `nil` if the ring is empty.
    public func dequeue() -> RealtimeMIDIEvent? {
        let r = readIndex.load(ordering: .relaxed)
        let w = writeIndex.load(ordering: .acquiring)
        if r == w { return nil }
        let event = storage[r & mask]
        readIndex.store(r &+ 1, ordering: .releasing)
        return event
    }
}
