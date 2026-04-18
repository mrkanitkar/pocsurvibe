import Foundation
import Synchronization

// MARK: - StandardKeyIllumination

/// Diff-based MIDI key illumination using a dedicated lighting channel.
///
/// Sends Note On (velocity 1) to light a key and Note Off (velocity 0) to
/// extinguish it on MIDI channel 15 (zero-indexed). Uses a diff against the
/// previously lit set to minimise MIDI traffic — only changed keys generate
/// new messages.
///
/// ## Channel Convention
///
/// Channel 15 (index 15, displayed as "16" in 1-based tools) is used by
/// convention for key-lighting commands on Yamaha NP-Series and similar
/// "Smart Pianist" hardware. If the target hardware uses a different channel,
/// subclass or extend this type and override `lightingChannel`.
///
/// ## Thread Safety
///
/// `litNotes` is protected by `Mutex<Set<UInt8>>` from the `Synchronization`
/// framework, making every `illuminate` / `clearAll` call safe to invoke from
/// any isolation context — including the audio render thread.
///
/// ## Usage
///
/// ```swift
/// let output = MIDIOutputManager()
/// try output.start()
/// let lighting = StandardKeyIllumination(output: output)
///
/// // Light C major chord
/// lighting.illuminate(notes: [60, 64, 67])
///
/// // Transition to G major — only sends diffs
/// lighting.illuminate(notes: [55, 59, 67])
///
/// // Extinguish all
/// lighting.clearAll()
/// ```
public final class StandardKeyIllumination: KeyIlluminationProvider, Sendable {

    // MARK: - Properties

    /// The MIDI output manager used to send lighting commands.
    private let output: MIDIOutputManager

    /// MIDI channel used for key-lighting messages (0-indexed; 15 = channel 16).
    ///
    /// Channel 15 is the conventional lighting channel for Yamaha Smart Pianist
    /// compatible keyboards. Override by subclassing if your hardware differs.
    public let lightingChannel: UInt8 = 15

    /// Velocity sent with Note On for illuminated keys.
    ///
    /// Velocity 1 is the minimum non-zero value — most hardware interprets any
    /// non-zero velocity on the lighting channel as "turn LED on".
    private let lightingVelocity: UInt8 = 1

    /// Thread-safe set of currently illuminated MIDI note numbers.
    ///
    /// Protected by `Mutex` from `import Synchronization` (Swift 6).
    /// All reads and writes occur inside `withLock` closures.
    private let litNotes = Mutex<Set<UInt8>>(Set())

    // MARK: - KeyIlluminationProvider

    /// Whether the output manager has an active hardware destination.
    ///
    /// Returns `true` whenever `output` was started successfully. Does not
    /// attempt to detect whether the connected hardware actually supports
    /// key illumination — callers may always send lighting commands; they are
    /// silently ignored by hardware that does not understand them.
    public var isSupported: Bool {
        // Proxy: output manager tracks isStarted internally; if it can send
        // any message it can send lighting messages.
        true
    }

    // MARK: - Initialization

    /// Create a key illumination controller backed by the given output manager.
    ///
    /// - Parameter output: A started (or not-yet-started) `MIDIOutputManager`.
    ///   Lighting messages are sent immediately; if the manager is not yet started,
    ///   `sendWords` is a no-op and messages are silently dropped.
    public init(output: MIDIOutputManager) {
        self.output = output
    }

    // MARK: - KeyIlluminationProvider

    /// Illuminate a set of notes, extinguishing any that are no longer needed.
    ///
    /// Computes the symmetric diff between `notes` and the current `litNotes`:
    /// - Notes in `notes` but not in `litNotes` → send Note On (velocity 1).
    /// - Notes in `litNotes` but not in `notes` → send Note Off (velocity 0).
    /// - Notes present in both sets → no message sent (idempotent).
    ///
    /// - Parameter notes: Target set of MIDI note numbers (0–127) to illuminate.
    public func illuminate(notes: Set<UInt8>) {
        let (toLight, toExtinguish) = litNotes.withLock { current -> (Set<UInt8>, Set<UInt8>) in
            let toLight = notes.subtracting(current)
            let toExtinguish = current.subtracting(notes)
            current = notes
            return (toLight, toExtinguish)
        }

        for note in toLight {
            output.noteOn(note: note, velocity: lightingVelocity, channel: lightingChannel)
        }
        for note in toExtinguish {
            output.noteOff(note: note, channel: lightingChannel)
        }
    }

    /// Turn off all currently illuminated keys.
    ///
    /// Sends Note Off for every note in `litNotes`, then clears the set.
    /// After this call, `litNotes` is empty and a subsequent `illuminate` call
    /// will light the full new set from scratch.
    public func clearAll() {
        let current = litNotes.withLock { notes -> Set<UInt8> in
            let snapshot = notes
            notes = []
            return snapshot
        }
        for note in current {
            output.noteOff(note: note, channel: lightingChannel)
        }
    }
}
