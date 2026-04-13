import Foundation
import os

/// Routes MIDI events to multiple consumers with type-based filtering.
///
/// Abstracts the fan-out of MIDI events from a single source (CoreMIDI) to
/// multiple consumers (scoring, highlight coordinator, event logger, etc.).
/// Each consumer registers with a filter specifying which event types it
/// wants to receive.
///
/// ## Thread Safety
///
/// The router is `Sendable`. Registrations are stored in an
/// `OSAllocatedUnfairLock` for thread-safe access from CoreMIDI's
/// high-priority callback thread.
///
/// ## Usage
///
/// ```swift
/// let router = MidiRouter()
/// router.register(.noteEvents) { event in handleNote(event) }
/// router.register(.controlChange) { event in handleCC(event) }
/// // In CoreMIDI callback:
/// router.routeNote(event)
/// router.routeCC(ccEvent)
/// ```
public final class MidiRouter: Sendable {

    /// Filter for which event types a consumer wants to receive.
    public struct EventFilter: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        /// Note-on and note-off events.
        public static let noteEvents = EventFilter(rawValue: 1 << 0)
        /// Control Change messages (sustain pedal, mod wheel, etc.).
        public static let controlChange = EventFilter(rawValue: 1 << 1)
        /// All event types.
        public static let all: EventFilter = [.noteEvents, .controlChange]
    }

    /// A registered consumer with its filter and callback.
    private struct Registration: Sendable {
        let filter: EventFilter
        let noteHandler: (@Sendable (MIDIInputEvent) -> Void)?
        let ccHandler: (@Sendable (MIDIControlChangeEvent) -> Void)?
    }

    private let registrations = OSAllocatedUnfairLock<[Registration]>(initialState: [])

    /// Create an empty MIDI router.
    public init() {}

    /// Register a note event consumer.
    ///
    /// - Parameters:
    ///   - filter: Event types to receive (default: `.noteEvents`).
    ///   - handler: Callback fired on CoreMIDI's thread.
    public func onNote(
        filter: EventFilter = .noteEvents,
        handler: @escaping @Sendable (MIDIInputEvent) -> Void
    ) {
        registrations.withLock { regs in
            regs.append(Registration(filter: filter, noteHandler: handler, ccHandler: nil))
        }
    }

    /// Register a Control Change event consumer.
    ///
    /// - Parameter handler: Callback fired on CoreMIDI's thread.
    public func onControlChange(
        handler: @escaping @Sendable (MIDIControlChangeEvent) -> Void
    ) {
        registrations.withLock { regs in
            regs.append(Registration(filter: .controlChange, noteHandler: nil, ccHandler: handler))
        }
    }

    /// Route a note event to all registered consumers.
    ///
    /// - Parameter event: The MIDI note event to deliver.
    public func routeNote(_ event: MIDIInputEvent) {
        let regs = registrations.withLock { $0 }
        for reg in regs where reg.filter.contains(.noteEvents) {
            reg.noteHandler?(event)
        }
    }

    /// Route a Control Change event to all registered consumers.
    ///
    /// - Parameter event: The CC event to deliver.
    public func routeCC(_ event: MIDIControlChangeEvent) {
        let regs = registrations.withLock { $0 }
        for reg in regs where reg.filter.contains(.controlChange) {
            reg.ccHandler?(event)
        }
    }

    /// Remove all registered consumers.
    public func removeAll() {
        registrations.withLock { $0.removeAll() }
    }
}
