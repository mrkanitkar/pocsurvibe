import Foundation
import os
import Synchronization

/// Module-level logger for AudioRingBuffer (Sendable type — cannot use static stored property).
private let ringBufferLogger = Logger.survibe(category: "RingBuffer")

/// Single-producer, single-consumer ring buffer for accumulating audio samples.
///
/// The audio thread writes 1024 samples per callback. The DSP queue reads
/// 2048/4096/8192 samples with overlap for FFT analysis.
///
/// Thread safety: Uses Mutex from Swift Synchronization module wrapping all mutable
/// state in a single `State` struct. This provides compiler-verified Sendable conformance.
/// Lock hold time is minimal (~4KB memcpy for writes, pointer arithmetic for reads).
public final class AudioRingBuffer: Sendable {
    // MARK: - Properties

    /// All mutable state protected by a single Mutex.
    private struct State: Sendable {
        var buffer: [Float]
        var writeIndex: Int = 0
        var totalWritten: Int = 0
    }

    private let state: Mutex<State>
    private let capacity: Int

    // MARK: - Initialization

    /// Create a ring buffer with the specified capacity.
    ///
    /// - Parameter capacity: Maximum number of Float samples the buffer holds.
    ///   Recommended: 2x the largest read size to ensure reads never overlap with writes.
    public init(capacity: Int) {
        let cap = max(capacity, 1)
        self.capacity = cap
        self.state = Mutex(State(buffer: [Float](repeating: 0, count: cap)))
    }

    // MARK: - Public Methods

    /// Write samples into the ring buffer.
    ///
    /// Called from the audio render thread. The write is a fast memcpy
    /// protected by a Mutex with sub-microsecond hold time.
    ///
    /// - Parameter samples: Audio samples to append. Typically 1024 frames per tap callback.
    public func write(_ samples: [Float]) {
        let bufCapacity = self.capacity
        let sampleCount = samples.count
        state.withLock { s in
            let count = sampleCount
            if count >= bufCapacity {
                // If writing more than capacity, keep only the last `capacity` samples
                ringBufferLogger.debug(
                    """
                    RingBuffer wrap: \(sampleCount, privacy: .public) samples, \
                    cap \(bufCapacity, privacy: .public)
                    """
                )
                let start = count - bufCapacity
                s.buffer = Array(samples[start...])
                s.writeIndex = 0
                s.totalWritten += count
                return
            }

            let spaceToEnd = bufCapacity - s.writeIndex
            if count <= spaceToEnd {
                // Contiguous write
                s.buffer.replaceSubrange(s.writeIndex..<(s.writeIndex + count), with: samples)
            } else {
                // Wrap around
                s.buffer.replaceSubrange(s.writeIndex..<bufCapacity, with: samples[0..<spaceToEnd])
                let remaining = count - spaceToEnd
                s.buffer.replaceSubrange(0..<remaining, with: samples[spaceToEnd..<count])
            }
            s.writeIndex = (s.writeIndex + count) % bufCapacity
            s.totalWritten += count
        }
    }

    /// Read the most recent `count` samples for FFT analysis.
    ///
    /// Called from the DSP queue. Returns nil if not enough samples
    /// have been accumulated yet.
    ///
    /// - Parameter count: Number of samples to read. Must be <= capacity.
    /// - Returns: Array of the most recent `count` samples, or nil if insufficient data.
    public func read(count: Int) -> [Float]? {
        let bufCapacity = self.capacity
        return state.withLock { s in
            guard count <= bufCapacity, s.totalWritten >= count else {
                let written = s.totalWritten
                ringBufferLogger.debug(
                    """
                    RingBuffer read nil: requested \(count, privacy: .public), \
                    cap \(bufCapacity, privacy: .public), \
                    written \(written, privacy: .public)
                    """
                )
                return nil
            }

            var result = [Float](repeating: 0, count: count)
            let readStart = (s.writeIndex - count + bufCapacity) % bufCapacity
            let spaceToEnd = bufCapacity - readStart

            if count <= spaceToEnd {
                // Contiguous read
                result.replaceSubrange(0..<count, with: s.buffer[readStart..<(readStart + count)])
            } else {
                // Wrap around
                result.replaceSubrange(0..<spaceToEnd, with: s.buffer[readStart..<bufCapacity])
                let remaining = count - spaceToEnd
                result.replaceSubrange(spaceToEnd..<count, with: s.buffer[0..<remaining])
            }

            return result
        }
    }

    /// Total number of samples written since creation or last reset.
    ///
    /// Monotonically increasing. Used to determine when a new hop's worth
    /// of data has arrived (check if totalSamplesWritten increased by >= hopSize).
    public var totalSamplesWritten: Int {
        state.withLock { $0.totalWritten }
    }

    /// Reset the buffer state.
    ///
    /// Called when stopping detection or changing latency preset.
    /// Zeros the buffer and resets write index and total count.
    public func reset() {
        ringBufferLogger.info("RingBuffer reset")
        let bufCapacity = self.capacity
        state.withLock { s in
            s.buffer = [Float](repeating: 0, count: bufCapacity)
            s.writeIndex = 0
            s.totalWritten = 0
        }
    }
}
