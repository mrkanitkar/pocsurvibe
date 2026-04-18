import Foundation
import Synchronization

/// Sendable reference-type box holding an `Atomic<Double>`.
///
/// `Atomic<Double>` (from Swift's Synchronization module) is non-copyable,
/// so it cannot be stored as a `let` property on one class and captured by
/// value into another closure that runs on a different thread. Wrapping it
/// in this small Sendable class gives us a stable reference that both the
/// audio render thread (producer, via `store`) and a DSP task (consumer,
/// via `load`) can share.
///
/// Both operations use `.relaxed` memory ordering — appropriate for a
/// sample-rate gauge where strict happens-before semantics are not
/// required; the consumer is fine reading any recent-ish value.
public final class AtomicDoubleBox: Sendable {
    private let atomic: Atomic<Double>

    public init(initial: Double) {
        self.atomic = Atomic<Double>(initial)
    }

    public func store(_ value: Double) {
        atomic.store(value, ordering: .relaxed)
    }

    public func load() -> Double {
        atomic.load(ordering: .relaxed)
    }
}
