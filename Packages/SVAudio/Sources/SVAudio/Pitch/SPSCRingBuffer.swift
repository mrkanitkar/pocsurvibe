import os
import Synchronization

/// Module-level logger for SPSCRingBuffer (Sendable type — cannot use static stored property).
private let spscLogger = Logger.survibe(category: "SPSCRingBuffer")

/// A lock-free, single-producer single-consumer ring buffer for audio samples.
///
/// Designed for the CoreAudio render thread safety contract: the audio callback
/// (producer) must never allocate memory or acquire locks. This implementation
/// uses `Atomic<Int>` indices for coordination — no `Mutex`, no `malloc`.
///
/// Memory is pre-allocated once in `init` via `UnsafeMutableBufferPointer`.
/// The `write()` method accepts an `UnsafeBufferPointer<Float>` so the
/// audio callback can pass `floatChannelData` directly without constructing
/// an `Array`.
///
/// Thread-safety contract:
/// - **Producer (audio render thread)**: calls `write()` only.
/// - **Consumer (DSP queue)**: calls `readLatest()` only.
/// - Only ONE producer and ONE consumer — SPSC guarantee.
public final class SPSCRingBuffer: Sendable {

    // MARK: - Storage

    /// Pre-allocated fixed-capacity storage. Allocated once in init, deallocated in deinit.
    ///
    /// `nonisolated(unsafe)` is required because `UnsafeMutableBufferPointer` does not
    /// conform to `Sendable`. Thread safety is guaranteed by the SPSC contract: the producer
    /// calls `write()` exclusively and the consumer calls `readLatest()` exclusively. The
    /// atomic `_writeIndex` (release/acquire ordering) ensures the consumer sees all writes
    /// before reading. No two threads ever access the same slot concurrently.
    nonisolated(unsafe) private let storage: UnsafeMutableBufferPointer<Float>

    /// Power-of-two capacity for fast modulo via bitmask.
    private let capacity: Int

    /// Bitmask for wrapping: `capacity - 1` (valid because capacity is power-of-two).
    private let mask: Int

    // MARK: - Atomic Indices

    /// Write position (producer-owned). Monotonically increasing, wraps via bitmask.
    private let _writeIndex: Atomic<Int>

    /// Total samples ever written. Used by consumer to detect buffer-full condition.
    private let _totalWritten: Atomic<Int>

    // MARK: - Initialization

    /// Creates a ring buffer with the given capacity.
    ///
    /// - Parameter capacity: Number of `Float` samples to hold. Will be rounded up
    ///   to the nearest power of two (minimum 256) for efficient modulo indexing.
    public init(capacity: Int) {
        // Round up to next power of two for bitmask trick
        var roundedCapacity = max(256, capacity)
        if !roundedCapacity.isPowerOfTwo {
            roundedCapacity = roundedCapacity.nextPowerOfTwo
        }
        self.capacity = roundedCapacity
        self.mask = roundedCapacity - 1
        self.storage = UnsafeMutableBufferPointer<Float>.allocate(capacity: roundedCapacity)
        self.storage.initialize(repeating: 0.0)
        self._writeIndex = Atomic<Int>(0)
        self._totalWritten = Atomic<Int>(0)
        spscLogger.info(
            "SPSCRingBuffer init: requested \(capacity, privacy: .public), actual \(roundedCapacity, privacy: .public)"
        )
    }

    deinit {
        spscLogger.debug("SPSCRingBuffer deallocated")
        storage.deallocate()
    }

    // MARK: - Producer API (audio render thread)

    /// Writes audio samples from the render callback. Lock-free, zero heap allocation.
    ///
    /// Overwrites oldest samples when buffer is full (circular). This is intentional:
    /// the consumer always reads the latest N samples, not historical data.
    ///
    /// - Parameter samples: Pointer to audio samples from `AVAudioPCMBuffer.floatChannelData`.
    ///   The pointer is only valid for the duration of the audio callback — this method
    ///   copies the data before returning.
    public func write(_ samples: UnsafeBufferPointer<Float>) {
        // CRITICAL: ZERO logging here — this runs on the real-time audio thread.
        let count = min(samples.count, capacity)
        guard count > 0, let src = samples.baseAddress else { return }

        let wi = _writeIndex.load(ordering: .relaxed)
        let startSlot = wi & mask

        if startSlot + count <= capacity {
            // Contiguous write — single memcpy
            (storage.baseAddress! + startSlot).initialize(from: src, count: count)
        } else {
            // Wrap-around — two memcpy segments
            let firstCount = capacity - startSlot
            (storage.baseAddress! + startSlot).initialize(from: src, count: firstCount)
            (storage.baseAddress!).initialize(from: src + firstCount, count: count - firstCount)
        }

        // Publish the new write index and total with release ordering so the
        // consumer sees fully-written data when it loads with acquire ordering.
        _writeIndex.store(wi &+ count, ordering: .releasing)
        _ = _totalWritten.wrappingAdd(count, ordering: .relaxed)
    }

    // MARK: - Consumer API (DSP queue)

    /// Reads the latest `count` samples into a caller-provided buffer. Lock-free.
    ///
    /// The destination buffer must be pre-allocated by the caller — no heap allocation
    /// occurs inside this method.
    ///
    /// - Parameters:
    ///   - count: Number of samples to read. Must be <= capacity.
    ///   - dest: Pre-allocated destination. Must have room for at least `count` elements.
    /// - Returns: `true` if enough samples were available; `false` if the buffer
    ///   has received fewer than `count` samples total (ring is not yet full enough).
    @discardableResult
    public func readLatest(count: Int, into dest: UnsafeMutableBufferPointer<Float>) -> Bool {
        // CRITICAL: ZERO logging here — this runs on the real-time audio thread.
        guard count > 0, count <= capacity, let dst = dest.baseAddress else { return false }

        // Acquire load: see all writes that happened before the store(releasing) in write().
        let wi = _writeIndex.load(ordering: .acquiring)
        let written = _totalWritten.load(ordering: .relaxed)

        guard written >= count else { return false }

        // Read the `count` samples ending at the current write position.
        let startSlot = (wi - count) & mask
        let endSlot = wi & mask

        if startSlot < endSlot {
            // Contiguous region
            dst.initialize(from: storage.baseAddress! + startSlot, count: count)
        } else {
            // Wrap-around — two segments
            let firstCount = capacity - startSlot
            dst.initialize(from: storage.baseAddress! + startSlot, count: firstCount)
            (dst + firstCount).initialize(from: storage.baseAddress!, count: count - firstCount)
        }

        return true
    }

    // MARK: - Diagnostics

    /// Total number of samples ever written to this buffer (monotonically increasing).
    ///
    /// Useful for diagnostics — compare two readings to measure throughput.
    public var totalSamplesWritten: Int {
        _totalWritten.load(ordering: .relaxed)
    }

    /// Current fill level as a fraction of capacity (0.0–1.0).
    ///
    /// Readable from any thread without locking (atomic load).
    /// Values near 1.0 indicate the consumer is falling behind the producer.
    /// Exposed for ``LatencySummary`` diagnostics and queue depth monitoring.
    public var fillLevel: Double {
        let written = _totalWritten.load(ordering: .relaxed)
        let level = min(written, capacity)
        return Double(level) / Double(capacity)
    }
}

// MARK: - Int Helpers (file-private)

private extension Int {
    var isPowerOfTwo: Bool { self > 0 && (self & (self - 1)) == 0 }

    var nextPowerOfTwo: Int {
        guard self > 0 else { return 1 }
        var v = self - 1
        v |= v >> 1; v |= v >> 2; v |= v >> 4; v |= v >> 8; v |= v >> 16; v |= v >> 32
        return v + 1
    }
}
