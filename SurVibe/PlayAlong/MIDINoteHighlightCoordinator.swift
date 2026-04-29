import Foundation
import os
import QuartzCore
import SVAudio
import SVCore

/// Decouples MIDI key-highlight state from the SwiftUI render cycle.
///
/// ## Problem this solves
/// At 120–140 BPM, notes arrive every 107–125 ms. A note-on followed by a
/// note-off can both complete within a single 16 ms SwiftUI frame, so the key
/// never visually highlights. Additionally, dispatching every MIDI event through
/// `Task { @MainActor }` adds unpredictable delay when the main actor is busy
/// re-rendering the piano keyboard, falling-notes view, or scoring HUD.
///
/// ## Solution
/// - A 128-element note-state buffer protected by `OSAllocatedUnfairLock` is
///   written **directly on CoreMIDI's high-priority thread** — no actor hops,
///   no Task queuing.
/// - A `CADisplayLink` fires every display frame (~8–16 ms) on the main thread,
///   reads the buffer under the lock, and publishes `activeNotes: Set<Int>` only
///   when the set changes — preventing unnecessary SwiftUI re-renders.
/// - An **80 ms minimum visual hold** is enforced per note so fast staccato
///   playing (e.g. Sa-Sa-Sa at 140 BPM) always produces a visible flash,
///   matching the behaviour of Simply Piano and Yousician.
///
/// ## Thread safety
/// - `rawNoteState` is a fixed-size array of 128 `Bool` inside an
///   `OSAllocatedUnfairLock`. Reads and writes from any thread are serialised
///   by the lock (hold time is a single array subscript — nanoseconds).
/// - `noteOnTimes`, `pendingOff`, `activeNotes` are only accessed on the main
///   thread inside `displayLinkFired` — no additional locking needed.
@MainActor
final class MIDINoteHighlightCoordinator {

    // MARK: - Published State

    /// MIDI note numbers whose keys should be highlighted right now.
    ///
    /// Written on the main thread by the CADisplayLink at display-link cadence.
    /// Relay into an `@Observable` view-model stored property so SwiftUI
    /// re-renders the piano only when the set changes.
    private(set) var activeNotes: Set<Int> = []

    /// Called on the main thread whenever `activeNotes` changes.
    ///
    /// Assign this to write the new set into an `@Observable` stored property
    /// on the view model — that stored property is what SwiftUI observes.
    var onActiveNotesChanged: (@MainActor (Set<Int>) -> Void)?

    // MARK: - Sustain Pedal

    /// Sustain pedal state tracker shared with the MIDI input pipeline.
    ///
    /// When the sustain pedal (CC64) is held down and a note-off arrives,
    /// the note remains highlighted instead of being released. When the pedal
    /// is released, all held notes are released at once.
    let sustainPedalState = SustainPedalState()

    // MARK: - Configuration

    /// Minimum visible duration for each key highlight in seconds.
    ///
    /// 80 ms guarantees one rendered frame at 60 Hz and feels natural to
    /// the user (matches perceptual minimum for an intentional keypress flash).
    nonisolated let minimumHoldSeconds: TimeInterval = 0.080

    /// Counts dropped display frames for observability.
    let frameDropCounter = FrameDropCounter()

    // MARK: - Private: thread-safe note state

    /// Lock + 128-Bool buffer written on any thread (CoreMIDI), read on main.
    ///
    /// Using `OSAllocatedUnfairLock` (available iOS 16+) because it is lighter
    /// than `NSLock` and correct for this usage (no recursive locking needed).
    private let stateLock = OSAllocatedUnfairLock(initialState: [Bool](repeating: false, count: 128))

    // MARK: - Private: main-thread-only state

    /// Timestamp of the most recent note-on for each active MIDI note.
    /// Only touched inside `displayLinkFired` on the main thread.
    private var noteOnTimes: [Int: CFTimeInterval] = [:]

    private var displayLink: CADisplayLink?
    private var isRunning = false

    // MARK: - Lifecycle

    /// Start the CADisplayLink highlight loop. Safe to call multiple times.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        let target = DisplayLinkTarget(coordinator: self)
        let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Stop the loop and clear all highlight state.
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        isRunning = false
        sustainPedalState.reset()
        stateLock.withLock { state in
            for i in 0..<128 { state[i] = false }
        }
        noteOnTimes.removeAll()
        if !activeNotes.isEmpty {
            activeNotes = []
            onActiveNotesChanged?([])
        }
    }

    // MARK: - MIDI Event API — called from ANY thread (CoreMIDI)

    /// Mark a note as physically pressed. May be called from any thread.
    nonisolated func noteOn(_ midiNote: Int) {
        guard midiNote >= 0, midiNote < 128 else { return }
        stateLock.withLock { $0[midiNote] = true }
    }

    /// Mark a note as physically released. May be called from any thread.
    ///
    /// If the sustain pedal is currently held down for the given channel,
    /// the note is captured by `sustainPedalState` and remains highlighted
    /// until the pedal is released.
    nonisolated func noteOff(_ midiNote: Int, channel: UInt8 = 0) {
        guard midiNote >= 0, midiNote < 128 else { return }
        if sustainPedalState.holdNote(note: midiNote, channel: channel) {
            return
        }
        stateLock.withLock { $0[midiNote] = false }
    }

    /// Handle sustain pedal down event. May be called from any thread.
    ///
    /// - Parameter channel: MIDI channel (0-15).
    nonisolated func sustainDown(channel: UInt8 = 0) {
        sustainPedalState.pedalDown(channel: channel)
    }

    /// Handle sustain pedal up event. May be called from any thread.
    ///
    /// Releases all notes that were held during the sustain period
    /// by clearing them in the lock-protected state buffer.
    ///
    /// - Parameter channel: MIDI channel (0-15).
    nonisolated func sustainUp(channel: UInt8 = 0) {
        let releasedNotes = sustainPedalState.pedalUp(channel: channel)
        if !releasedNotes.isEmpty {
            stateLock.withLock { state in
                for note in releasedNotes where note >= 0 && note < 128 {
                    state[note] = false
                }
            }
        }
    }

    // MARK: - Latency Probe

    /// Stamps t3 (frame presented) and records the completed probe token.
    ///
    /// Call from the scoring result handler after the display link processes
    /// the note-on. The token already has t0 (input), t1 (DSP), t2 (match).
    func recordProbe(_ token: ProbeToken?) {
        guard var token else { return }
        token.stamp(.framePresented)
        LatencyProbe.shared.record(token)
    }

    // MARK: - Display Link Callback — main thread only

    /// Called by `CADisplayLink` every frame. Reads the lock-protected buffer,
    /// applies minimum-hold, and publishes `activeNotes` when changed.
    fileprivate func displayLinkFired(timestamp: CFTimeInterval, targetTimestamp: CFTimeInterval) {
        frameDropCounter.recordFrame(timestamp: timestamp, targetTimestamp: targetTimestamp)
        // Snapshot current physical key states under lock (hold time: ~128 ns)
        let snapshot = stateLock.withLock { $0 }

        var newActive = activeNotes
        var changed = false
        let now = timestamp

        for note in 0..<128 {
            if snapshot[note] {
                // Key is physically down.
                // Always (re)set noteOnTimes to now.
                // - First press: noteOnTimes[note] is nil → fresh onset, insert into set.
                // - Same-key repeat re-pressed while still in minimum hold:
                //   noteOnTimes[note] already set → reset timer to now so the
                //   minimum hold starts fresh from this second press.
                let wasAlreadyActive = noteOnTimes[note] != nil
                noteOnTimes[note] = now
                if !wasAlreadyActive {
                    if newActive.insert(note).inserted { changed = true }
                }
            } else {
                // Key is physically up — enforce minimum hold before removing.
                if let onTime = noteOnTimes[note] {
                    if now - onTime >= minimumHoldSeconds {
                        noteOnTimes.removeValue(forKey: note)
                        if newActive.remove(note) != nil { changed = true }
                    }
                    // else: still within minimum hold — keep highlighted
                }
            }
        }

        if changed {
            activeNotes = newActive
            onActiveNotesChanged?(newActive)
        }
    }
}

// MARK: - CADisplayLink target shim

/// Breaks the CADisplayLink → coordinator retain cycle.
///
/// CADisplayLink strongly retains its target. A weak-reference shim prevents
/// the coordinator from being kept alive by the display link after `stop()`.
private final class DisplayLinkTarget: NSObject {
    private weak var coordinator: MIDINoteHighlightCoordinator?

    init(coordinator: MIDINoteHighlightCoordinator) {
        self.coordinator = coordinator
    }

    @MainActor @objc func tick(_ link: CADisplayLink) {
        coordinator?.displayLinkFired(
            timestamp: link.timestamp,
            targetTimestamp: link.targetTimestamp
        )
    }
}

// MARK: - HighlightSink conformance

/// Conformance to the SVCore `HighlightSink` protocol so `TakePlaybackEngine`
/// can drive the existing key-highlight pipeline without importing the app
/// target. The four required methods (`noteOn(_:)`, `noteOff(_:channel:)`,
/// `sustainDown(channel:)`, `sustainUp(channel:)`) are already declared above
/// with matching signatures (and `channel: UInt8 = 0` defaults).
extension MIDINoteHighlightCoordinator: HighlightSink {}
