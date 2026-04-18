import Foundation
import os

/// Thread-safe box holding a direct low-latency callback for pitch bend events.
///
/// **CoreMIDI real-time safety.** `fire(_:)` is invoked on the CoreMIDI
/// receive thread (a system-owned high-priority thread with a small stack).
/// The user-supplied closure must therefore NOT be executed while this box's
/// spin-lock is held — otherwise any Swift runtime metadata allocation,
/// `DispatchQueue.async`, or `Task { }` inside the closure can combine with
/// the lock to overflow the guard page (observed crashes #3/#4/#5).
/// Pattern: snapshot the closure under the lock, release the lock, then
/// invoke. The closure value itself is `@Sendable` and immutable once loaded.
public final class PitchBendCallbackBox: Sendable {
    private let lock = OSAllocatedUnfairLock<(@Sendable (MIDIPitchBendEvent) -> Void)?>(
        initialState: nil
    )

    /// Create an empty pitch bend callback box.
    public init() {}

    /// Retrieve the current callback.
    public func get() -> (@Sendable (MIDIPitchBendEvent) -> Void)? {
        lock.withLock { $0 }
    }

    /// Replace the current callback.
    public func set(_ cb: (@Sendable (MIDIPitchBendEvent) -> Void)?) {
        lock.withLock { $0 = cb }
    }

    /// Fire the callback with the given event.
    public func fire(_ event: MIDIPitchBendEvent) {
        let cb = lock.withLock { $0 }
        cb?(event)
    }
}

/// Thread-safe box holding a direct low-latency callback for pressure events.
///
/// Same lock-release-before-fire rule as `PitchBendCallbackBox`.
public final class PressureCallbackBox: Sendable {
    private let lock = OSAllocatedUnfairLock<(@Sendable (MIDIPressureEvent) -> Void)?>(
        initialState: nil
    )

    /// Create an empty pressure callback box.
    public init() {}

    /// Retrieve the current callback.
    public func get() -> (@Sendable (MIDIPressureEvent) -> Void)? {
        lock.withLock { $0 }
    }

    /// Replace the current callback.
    public func set(_ cb: (@Sendable (MIDIPressureEvent) -> Void)?) {
        lock.withLock { $0 = cb }
    }

    /// Fire the callback with the given event.
    public func fire(_ event: MIDIPressureEvent) {
        let cb = lock.withLock { $0 }
        cb?(event)
    }
}

/// Thread-safe box holding a direct low-latency callback for program change events.
///
/// Same lock-release-before-fire rule as `PitchBendCallbackBox`.
public final class ProgramChangeCallbackBox: Sendable {
    private let lock = OSAllocatedUnfairLock<(@Sendable (MIDIProgramChangeEvent) -> Void)?>(
        initialState: nil
    )

    /// Create an empty program change callback box.
    public init() {}

    /// Retrieve the current callback.
    public func get() -> (@Sendable (MIDIProgramChangeEvent) -> Void)? {
        lock.withLock { $0 }
    }

    /// Replace the current callback.
    public func set(_ cb: (@Sendable (MIDIProgramChangeEvent) -> Void)?) {
        lock.withLock { $0 = cb }
    }

    /// Fire the callback with the given event.
    public func fire(_ event: MIDIProgramChangeEvent) {
        let cb = lock.withLock { $0 }
        cb?(event)
    }
}

/// Bundle of all MIDI callback boxes passed to the parser.
///
/// Groups the individual callback boxes into a single `Sendable` value that
/// can be captured by the CoreMIDI read block closure. Each box holds an
/// `OSAllocatedUnfairLock`-protected optional callback.
///
/// Adding new event types only requires adding a new box here and in the
/// parser switch — no signature changes to `parseEventList`.
struct MIDICallbackSet: Sendable {
    /// Note-on/note-off callback box.
    let note: NoteCallbackBox
    /// Control Change callback box.
    let cc: CCCallbackBox
    /// Pitch bend callback box.
    let pitchBend: PitchBendCallbackBox
    /// Pressure (aftertouch) callback box.
    let pressure: PressureCallbackBox
    /// Program change callback box.
    let programChange: ProgramChangeCallbackBox

    /// Create a callback set with the given boxes.
    ///
    /// - Parameters:
    ///   - note: Note callback box.
    ///   - cc: Control Change callback box.
    ///   - pitchBend: Pitch bend callback box.
    ///   - pressure: Pressure callback box.
    ///   - programChange: Program change callback box.
    init(
        note: NoteCallbackBox,
        cc: CCCallbackBox,
        pitchBend: PitchBendCallbackBox = PitchBendCallbackBox(),
        pressure: PressureCallbackBox = PressureCallbackBox(),
        programChange: ProgramChangeCallbackBox = ProgramChangeCallbackBox()
    ) {
        self.note = note
        self.cc = cc
        self.pitchBend = pitchBend
        self.pressure = pressure
        self.programChange = programChange
    }
}
