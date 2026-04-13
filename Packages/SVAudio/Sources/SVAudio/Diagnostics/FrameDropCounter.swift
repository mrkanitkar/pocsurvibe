import Synchronization

/// Counts dropped display frames by comparing consecutive CADisplayLink timestamps.
///
/// A frame is considered "dropped" when the delta between the target timestamp
/// and the actual timestamp exceeds 1.5x the expected frame interval. For 120 Hz
/// ProMotion displays the expected interval is ~8.33 ms, so drops are detected
/// when the delta exceeds ~12.5 ms.
///
/// Thread-safe via `Synchronization.Atomic<Int>`. The counter can be read and
/// reset from any thread without locking.
public final class FrameDropCounter: Sendable {

    // MARK: - Properties

    /// Expected duration of a single frame in seconds.
    ///
    /// Defaults to `1.0 / 120.0` (~8.33 ms) for ProMotion displays.
    public let expectedInterval: Double

    /// Multiplier applied to `expectedInterval` to determine the drop threshold.
    ///
    /// A frame is counted as dropped when the delta between `targetTimestamp`
    /// and `timestamp` exceeds `expectedInterval * thresholdMultiplier`.
    /// Default is 1.5.
    public let thresholdMultiplier: Double

    /// Atomic counter incremented on each detected dropped frame.
    private let _count = Atomic<Int>(0)

    // MARK: - Initialization

    /// Create a frame drop counter with a configurable frame interval and threshold.
    ///
    /// - Parameters:
    ///   - expectedInterval: Duration of one frame in seconds. Default `1.0 / 120.0`
    ///     for 120 Hz ProMotion displays.
    ///   - thresholdMultiplier: How many multiples of the expected interval constitute
    ///     a drop. Default 1.5.
    public init(expectedInterval: Double = 1.0 / 120.0, thresholdMultiplier: Double = 1.5) {
        self.expectedInterval = expectedInterval
        self.thresholdMultiplier = thresholdMultiplier
    }

    // MARK: - Public Methods

    /// Number of dropped frames recorded since the last reset.
    ///
    /// Readable from any thread without locking (atomic load).
    public var count: Int {
        _count.load(ordering: .relaxed)
    }

    /// Record a display-link frame and detect whether it was dropped.
    ///
    /// Call this from the CADisplayLink callback, passing the link's `timestamp`
    /// and `targetTimestamp`. If the gap between target and actual exceeds the
    /// configured threshold the internal counter is incremented.
    ///
    /// - Parameters:
    ///   - timestamp: The `CADisplayLink.timestamp` of the current frame (when
    ///     the previous frame was displayed).
    ///   - targetTimestamp: The `CADisplayLink.targetTimestamp` (when the next
    ///     frame is expected to be displayed).
    public func recordFrame(timestamp: Double, targetTimestamp: Double) {
        let delta = targetTimestamp - timestamp
        let threshold = expectedInterval * thresholdMultiplier
        if delta > threshold {
            _count.wrappingAdd(1, ordering: .relaxed)
        }
    }

    /// Reset the dropped-frame counter to zero.
    ///
    /// Call at the start of a new practice session so per-session metrics are
    /// accurate.
    public func reset() {
        _count.store(0, ordering: .relaxed)
    }
}
