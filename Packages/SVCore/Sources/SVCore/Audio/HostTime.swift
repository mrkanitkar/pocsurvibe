import Darwin
import Foundation

/// Mach absolute-time value used as the canonical timing reference across
/// SVAudio, SVLearning, and the app target.
///
/// Wraps `mach_absolute_time()` ticks with type safety so timing values cannot
/// be confused with raw `UInt64` counts. Convert to seconds via `seconds(since:)`.
public struct HostTime: Hashable, Sendable {
    /// Raw mach tick count.
    public let rawTicks: UInt64

    /// Creates a `HostTime` from a raw mach tick value.
    ///
    /// - Parameter rawTicks: The mach absolute time tick count.
    public init(rawTicks: UInt64) {
        self.rawTicks = rawTicks
    }

    /// Captures the current host time. Sub-microsecond precision on Apple silicon.
    ///
    /// - Returns: The current host time.
    public static func now() -> HostTime {
        HostTime(rawTicks: mach_absolute_time())
    }

    /// Seconds elapsed since `other`. Negative when `other` is later than `self`.
    ///
    /// Uses `mach_timebase_info` for tick-to-nanosecond conversion.
    ///
    /// - Parameter other: The reference time to measure from.
    /// - Returns: Seconds between this time and `other`.
    public func seconds(since other: HostTime) -> Double {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let deltaTicks = Int64(rawTicks) - Int64(other.rawTicks)
        let nanos = Double(deltaTicks) * Double(info.numer) / Double(info.denom)
        return nanos / 1_000_000_000.0
    }
}
