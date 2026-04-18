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
/// router.onNote { event in handleNote(event) }
/// router.onControlChange { event in handleCC(event) }
/// router.onPitchBend { event in handleBend(event) }
/// // In CoreMIDI callback:
/// router.routeNote(event)
/// router.routeCC(ccEvent)
/// router.routePitchBend(bendEvent)
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
        /// Pitch bend events (channel-wide and per-note).
        public static let pitchBend = EventFilter(rawValue: 1 << 2)
        /// Pressure events (poly aftertouch and channel aftertouch).
        public static let pressure = EventFilter(rawValue: 1 << 3)
        /// Program change events.
        public static let programChange = EventFilter(rawValue: 1 << 4)
        /// Per-note controller events (MIDI 2.0).
        public static let perNoteControl = EventFilter(rawValue: 1 << 5)
        /// Registered/assignable controller events (RPN/NRPN).
        public static let registeredControl = EventFilter(rawValue: 1 << 6)
        /// Per-note management events (MIDI 2.0 detach/reset).
        public static let perNoteManagement = EventFilter(rawValue: 1 << 7)
        /// All event types.
        public static let all: EventFilter = [
            .noteEvents, .controlChange, .pitchBend, .pressure,
            .programChange, .perNoteControl, .registeredControl, .perNoteManagement,
        ]
    }

    /// A registered consumer with its filter and callbacks.
    private struct Registration: Sendable {
        let filter: EventFilter
        let noteHandler: (@Sendable (MIDIInputEvent) -> Void)?
        let ccHandler: (@Sendable (MIDIControlChangeEvent) -> Void)?
        let pitchBendHandler: (@Sendable (MIDIPitchBendEvent) -> Void)?
        let pressureHandler: (@Sendable (MIDIPressureEvent) -> Void)?
        let programChangeHandler: (@Sendable (MIDIProgramChangeEvent) -> Void)?
        let perNoteControlHandler: (@Sendable (MIDIPerNoteControlEvent) -> Void)?
        let registeredControlHandler: (@Sendable (MIDIRegisteredControlEvent) -> Void)?
        let perNoteManagementHandler: (@Sendable (MIDIPerNoteManagementEvent) -> Void)?
    }

    private let registrations = OSAllocatedUnfairLock<[Registration]>(initialState: [])

    /// Create an empty MIDI router.
    public init() {}

    // MARK: - Registration

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
            regs.append(Registration(
                filter: filter, noteHandler: handler, ccHandler: nil,
                pitchBendHandler: nil, pressureHandler: nil, programChangeHandler: nil,
                perNoteControlHandler: nil, registeredControlHandler: nil, perNoteManagementHandler: nil
            ))
        }
    }

    /// Register a Control Change event consumer.
    ///
    /// - Parameter handler: Callback fired on CoreMIDI's thread.
    public func onControlChange(
        handler: @escaping @Sendable (MIDIControlChangeEvent) -> Void
    ) {
        registrations.withLock { regs in
            regs.append(Registration(
                filter: .controlChange, noteHandler: nil, ccHandler: handler,
                pitchBendHandler: nil, pressureHandler: nil, programChangeHandler: nil,
                perNoteControlHandler: nil, registeredControlHandler: nil, perNoteManagementHandler: nil
            ))
        }
    }

    /// Register a pitch bend event consumer.
    ///
    /// - Parameter handler: Callback fired on CoreMIDI's thread.
    public func onPitchBend(
        handler: @escaping @Sendable (MIDIPitchBendEvent) -> Void
    ) {
        registrations.withLock { regs in
            regs.append(Registration(
                filter: .pitchBend, noteHandler: nil, ccHandler: nil,
                pitchBendHandler: handler, pressureHandler: nil, programChangeHandler: nil,
                perNoteControlHandler: nil, registeredControlHandler: nil, perNoteManagementHandler: nil
            ))
        }
    }

    /// Register a pressure (aftertouch) event consumer.
    ///
    /// - Parameter handler: Callback fired on CoreMIDI's thread.
    public func onPressure(
        handler: @escaping @Sendable (MIDIPressureEvent) -> Void
    ) {
        registrations.withLock { regs in
            regs.append(Registration(
                filter: .pressure, noteHandler: nil, ccHandler: nil,
                pitchBendHandler: nil, pressureHandler: handler, programChangeHandler: nil,
                perNoteControlHandler: nil, registeredControlHandler: nil, perNoteManagementHandler: nil
            ))
        }
    }

    /// Register a program change event consumer.
    ///
    /// - Parameter handler: Callback fired on CoreMIDI's thread.
    public func onProgramChange(
        handler: @escaping @Sendable (MIDIProgramChangeEvent) -> Void
    ) {
        registrations.withLock { regs in
            regs.append(Registration(
                filter: .programChange, noteHandler: nil, ccHandler: nil,
                pitchBendHandler: nil, pressureHandler: nil, programChangeHandler: handler,
                perNoteControlHandler: nil, registeredControlHandler: nil, perNoteManagementHandler: nil
            ))
        }
    }

    /// Register a per-note controller event consumer.
    ///
    /// - Parameter handler: Callback fired on CoreMIDI's thread.
    public func onPerNoteControl(
        handler: @escaping @Sendable (MIDIPerNoteControlEvent) -> Void
    ) {
        registrations.withLock { regs in
            regs.append(Registration(
                filter: .perNoteControl, noteHandler: nil, ccHandler: nil,
                pitchBendHandler: nil, pressureHandler: nil, programChangeHandler: nil,
                perNoteControlHandler: handler, registeredControlHandler: nil, perNoteManagementHandler: nil
            ))
        }
    }

    /// Register a registered/assignable controller event consumer.
    ///
    /// - Parameter handler: Callback fired on CoreMIDI's thread.
    public func onRegisteredControl(
        handler: @escaping @Sendable (MIDIRegisteredControlEvent) -> Void
    ) {
        registrations.withLock { regs in
            regs.append(Registration(
                filter: .registeredControl, noteHandler: nil, ccHandler: nil,
                pitchBendHandler: nil, pressureHandler: nil, programChangeHandler: nil,
                perNoteControlHandler: nil, registeredControlHandler: handler, perNoteManagementHandler: nil
            ))
        }
    }

    /// Register a per-note management event consumer.
    ///
    /// - Parameter handler: Callback fired on CoreMIDI's thread.
    public func onPerNoteManagement(
        handler: @escaping @Sendable (MIDIPerNoteManagementEvent) -> Void
    ) {
        registrations.withLock { regs in
            regs.append(Registration(
                filter: .perNoteManagement, noteHandler: nil, ccHandler: nil,
                pitchBendHandler: nil, pressureHandler: nil, programChangeHandler: nil,
                perNoteControlHandler: nil, registeredControlHandler: nil, perNoteManagementHandler: handler
            ))
        }
    }

    // MARK: - Routing

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

    /// Route a pitch bend event to all registered consumers.
    ///
    /// - Parameter event: The pitch bend event to deliver.
    public func routePitchBend(_ event: MIDIPitchBendEvent) {
        let regs = registrations.withLock { $0 }
        for reg in regs where reg.filter.contains(.pitchBend) {
            reg.pitchBendHandler?(event)
        }
    }

    /// Route a pressure event to all registered consumers.
    ///
    /// - Parameter event: The pressure event to deliver.
    public func routePressure(_ event: MIDIPressureEvent) {
        let regs = registrations.withLock { $0 }
        for reg in regs where reg.filter.contains(.pressure) {
            reg.pressureHandler?(event)
        }
    }

    /// Route a program change event to all registered consumers.
    ///
    /// - Parameter event: The program change event to deliver.
    public func routeProgramChange(_ event: MIDIProgramChangeEvent) {
        let regs = registrations.withLock { $0 }
        for reg in regs where reg.filter.contains(.programChange) {
            reg.programChangeHandler?(event)
        }
    }

    /// Route a per-note controller event to all registered consumers.
    ///
    /// - Parameter event: The per-note controller event to deliver.
    public func routePerNoteControl(_ event: MIDIPerNoteControlEvent) {
        let regs = registrations.withLock { $0 }
        for reg in regs where reg.filter.contains(.perNoteControl) {
            reg.perNoteControlHandler?(event)
        }
    }

    /// Route a registered/assignable controller event to all registered consumers.
    ///
    /// - Parameter event: The registered control event to deliver.
    public func routeRegisteredControl(_ event: MIDIRegisteredControlEvent) {
        let regs = registrations.withLock { $0 }
        for reg in regs where reg.filter.contains(.registeredControl) {
            reg.registeredControlHandler?(event)
        }
    }

    /// Route a per-note management event to all registered consumers.
    ///
    /// - Parameter event: The per-note management event to deliver.
    public func routePerNoteManagement(_ event: MIDIPerNoteManagementEvent) {
        let regs = registrations.withLock { $0 }
        for reg in regs where reg.filter.contains(.perNoteManagement) {
            reg.perNoteManagementHandler?(event)
        }
    }

    /// Remove all registered consumers.
    public func removeAll() {
        registrations.withLock { $0.removeAll() }
    }
}
