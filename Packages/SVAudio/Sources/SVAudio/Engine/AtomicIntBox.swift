import Foundation
import Synchronization

/// Sendable reference-type box holding an `Atomic<Int>`.
///
/// Parallel to `AtomicDoubleBox`. Used for lock-free diagnostic counters
/// (e.g. mic DSP buffer count) written from a DSP `Task` and read from
/// MainActor without requiring a MainActor hop on the hot path.
///
/// Both operations use `.relaxed` memory ordering — appropriate for a
/// monotonic counter where strict happens-before semantics are not required.
public final class AtomicIntBox: Sendable {
    private let atomic: Atomic<Int>

    public init(initial: Int) {
        self.atomic = Atomic<Int>(initial)
    }

    public func store(_ value: Int) {
        atomic.store(value, ordering: .relaxed)
    }

    public func load() -> Int {
        atomic.load(ordering: .relaxed)
    }

    @discardableResult
    public func increment() -> Int {
        atomic.wrappingAdd(1, ordering: .relaxed).newValue
    }
}
