import Foundation
import Synchronization

/// Sendable reference-type box holding an `Atomic<Bool>`.
///
/// `Atomic<Bool>` (from Swift's Synchronization module) is non-copyable,
/// so it cannot be stored as a `let` property on one class and captured
/// by value into a `@Sendable` closure that runs on another thread.
/// Wrapping it in this small Sendable class gives us a stable reference
/// both the producer (audio render thread) and consumer (DSP task) can
/// share.
///
/// Used as an RT-safe signal to wake the DSP task: the mic tap stores
/// `true` after writing each buffer; the DSP task `exchange(false)` to
/// detect pending work. `Atomic<Bool>.store/exchange` are documented
/// lock-free and allocation-free, so this replaces the old
/// `AsyncStream<Void>` signal which is not contractually RT-safe.
/// See micissues.md I6.
final class AtomicBoolBox: Sendable {
    private let atomic: Atomic<Bool>

    init(initial: Bool = false) {
        self.atomic = Atomic<Bool>(initial)
    }

    /// Sets the flag to `value`. Used from the audio render thread.
    func store(_ value: Bool) {
        atomic.store(value, ordering: .releasing)
    }

    /// Non-destructive read of the current flag value.
    func load() -> Bool {
        atomic.load(ordering: .acquiring)
    }

    /// Atomically swaps the flag to `newValue` and returns the previous
    /// value. Used by the DSP task to consume the signal:
    /// `if tapSignal.exchange(false) { processBuffer() }`.
    @discardableResult
    func exchange(_ newValue: Bool) -> Bool {
        atomic.exchange(newValue, ordering: .acquiring)
    }
}
