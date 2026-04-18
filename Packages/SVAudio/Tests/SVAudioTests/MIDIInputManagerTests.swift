import Foundation
import Synchronization
import Testing

@testable import SVAudio

// MARK: - MIDIInputManager Tests

/// Tests verifying the ARCH-003 Mutex<MIDIState> consolidation.
///
/// MIDIInputManager.init() is private (singleton pattern), so we test
/// through the public API of the shared instance. CoreMIDI operations
/// may fail in CI/test environments without MIDI hardware, but the
/// state management logic is exercised regardless.
@Suite("MIDIInputManager Tests")
struct MIDIInputManagerTests {

    // MARK: - Singleton

    @Test("Shared instance is non-nil and is the same object")
    func sharedInstanceIdentity() {
        let a = MIDIInputManager.shared
        let b = MIDIInputManager.shared
        #expect(a === b)
    }

    // MARK: - Stream Lazy Creation

    @Test("noteOnStream returns a valid stream (lazy creation via Mutex)")
    func noteOnStreamCreation() {
        // Mutex.withLock creates the stream on first access.
        // If the Mutex pattern is broken, this would crash or deadlock.
        let _: AsyncStream<MIDIInputEvent> = MIDIInputManager.shared.noteOnStream
    }

    @Test("connectionStateStream returns a valid stream (lazy creation via Mutex)")
    func connectionStateStreamCreation() {
        // Mutex.withLock creates the stream on first access.
        let _: AsyncStream<Bool> = MIDIInputManager.shared.connectionStateStream
    }

    @Test("noteOnStream can be accessed repeatedly without deadlock")
    func noteOnStreamIdempotent() {
        // Both calls go through Mutex.withLock with the guard-and-cache pattern.
        // A deadlock in the Mutex would hang here.
        let _: AsyncStream<MIDIInputEvent> = MIDIInputManager.shared.noteOnStream
        let _: AsyncStream<MIDIInputEvent> = MIDIInputManager.shared.noteOnStream
    }

    // MARK: - Start Idempotency

    @Test("start() can be called multiple times without crashing")
    func startIdempotent() {
        // start() guards on isStarted inside Mutex.withLock.
        // Second call should return immediately without error.
        MIDIInputManager.shared.start()
        MIDIInputManager.shared.start()
        // No crash = pass. The underlying CoreMIDI setup may fail in
        // test environments, but the Mutex-protected early return works.
    }

    // MARK: - Protocol Conformance

    @Test("MIDIInputManager conforms to MIDIInputProviding")
    func conformsToProtocol() {
        // Assigning to a protocol-typed variable verifies conformance at compile time.
        // If conformance breaks (e.g., missing method after refactor), this won't compile.
        let provider: any MIDIInputProviding = MIDIInputManager.shared
        #expect(provider === MIDIInputManager.shared)
    }

    // MARK: - Direct Callback

    @Test("onNoteEvent getter returns nil by default")
    func defaultCallbackIsNil() {
        // Fresh state: no callback registered.
        // Note: other tests may have set a callback, so we set then clear.
        MIDIInputManager.shared.onNoteEvent = nil
        #expect(MIDIInputManager.shared.onNoteEvent == nil)
    }

    @Test("onNoteEvent can be set and cleared")
    func setAndClearCallback() {
        let callback: @Sendable (MIDIInputEvent) -> Void = { _ in }
        MIDIInputManager.shared.onNoteEvent = callback
        #expect(MIDIInputManager.shared.onNoteEvent != nil)
        MIDIInputManager.shared.onNoteEvent = nil
        #expect(MIDIInputManager.shared.onNoteEvent == nil)
    }

    // MARK: - Control Change Callback

    @Test("onControlChangeEvent getter returns nil by default")
    func defaultCCCallbackIsNil() {
        MIDIInputManager.shared.onControlChangeEvent = nil
        #expect(MIDIInputManager.shared.onControlChangeEvent == nil)
    }

    @Test("onControlChangeEvent can be set and cleared")
    func setAndClearCCCallback() {
        let callback: @Sendable (MIDIControlChangeEvent) -> Void = { _ in }
        MIDIInputManager.shared.onControlChangeEvent = callback
        #expect(MIDIInputManager.shared.onControlChangeEvent != nil)
        MIDIInputManager.shared.onControlChangeEvent = nil
        #expect(MIDIInputManager.shared.onControlChangeEvent == nil)
    }
}

// MARK: - MIDIInputEvent Concurrency Tests

/// Stress tests verifying MIDIInputEvent is safely Sendable across threads.
@Suite("MIDIInputEvent Concurrency Tests")
struct MIDIInputEventConcurrencyTests {

    @Test("MIDIInputEvent can be created and read from multiple tasks")
    func concurrentEventCreation() async {
        // Verify Sendable conformance holds under concurrent access.
        await withTaskGroup(of: MIDIInputEvent.self) { group in
            for note: UInt8 in 0..<128 {
                group.addTask {
                    MIDIInputEvent(
                        noteNumber: note,
                        velocity: 100,
                        channel: 0
                    )
                }
            }

            var count = 0
            for await event in group {
                #expect(event.velocity == 100)
                count += 1
            }
            #expect(count == 128)
        }
    }

    @Test("MIDIInputEvent isNoteOn correctly distinguishes note-on from note-off")
    func noteOnDistinction() {
        let noteOn = MIDIInputEvent(noteNumber: 60, velocity: 100)
        let noteOff = MIDIInputEvent(noteNumber: 60, velocity: 0)
        #expect(noteOn.isNoteOn == true)
        #expect(noteOff.isNoteOn == false)
    }

    @Test("MIDIInputEvent equality checks all fields")
    func eventEquality() {
        let timestamp = Date()
        let event1 = MIDIInputEvent(
            noteNumber: 60,
            velocity: 100,
            channel: 1,
            midiTimestamp: 12345,
            timestamp: timestamp
        )
        let event2 = MIDIInputEvent(
            noteNumber: 60,
            velocity: 100,
            channel: 1,
            midiTimestamp: 12345,
            timestamp: timestamp
        )
        #expect(event1 == event2)
    }

    @Test("MIDIInputEvent inequality for different note numbers")
    func eventInequalityNote() {
        let timestamp = Date()
        let event1 = MIDIInputEvent(
            noteNumber: 60,
            velocity: 100,
            channel: 0,
            timestamp: timestamp
        )
        let event2 = MIDIInputEvent(
            noteNumber: 61,
            velocity: 100,
            channel: 0,
            timestamp: timestamp
        )
        #expect(event1 != event2)
    }

    // MARK: - MIDICallbackSet Tests

    @Test("MIDICallbackSet creates with default empty boxes")
    func callbackSetDefaults() {
        let noteBox = NoteCallbackBox()
        let ccBox = CCCallbackBox()
        let set = MIDICallbackSet(note: noteBox, cc: ccBox)

        // Default boxes should have nil callbacks
        #expect(set.pitchBend.get() == nil)
        #expect(set.pressure.get() == nil)
        #expect(set.programChange.get() == nil)
    }

    @Test("PitchBendCallbackBox fires callback")
    func pitchBendBoxFires() {
        let box = PitchBendCallbackBox()
        let received = Mutex<MIDIPitchBendEvent?>(nil)
        box.set { event in received.withLock { $0 = event } }

        let event = MIDIPitchBendEvent(value: 500, channel: 1)
        box.fire(event)
        #expect(received.withLock { $0?.value } == 500)
    }

    @Test("PressureCallbackBox fires callback")
    func pressureBoxFires() {
        let box = PressureCallbackBox()
        let received = Mutex<MIDIPressureEvent?>(nil)
        box.set { event in received.withLock { $0 = event } }

        let event = MIDIPressureEvent(noteNumber: 60, pressure: 1000)
        box.fire(event)
        #expect(received.withLock { $0?.noteNumber } == 60)
    }

    @Test("ProgramChangeCallbackBox fires callback")
    func programChangeBoxFires() {
        let box = ProgramChangeCallbackBox()
        let received = Mutex<MIDIProgramChangeEvent?>(nil)
        box.set { event in received.withLock { $0 = event } }

        let event = MIDIProgramChangeEvent(program: 42)
        box.fire(event)
        #expect(received.withLock { $0?.program } == 42)
    }

    @Test("Callback box set to nil does not crash on fire")
    func callbackBoxNilSafe() {
        let box = PitchBendCallbackBox()
        // No callback set — fire should be a no-op
        let event = MIDIPitchBendEvent(value: 0)
        box.fire(event)
        // No crash = pass
    }

    @Test("MIDIInputEvent velocity16Bit backward compatibility")
    func velocity16BitBackwardCompat() {
        // Existing call sites that do not pass velocity16Bit should compile and default to 0
        let event = MIDIInputEvent(noteNumber: 60, velocity: 100)
        #expect(event.velocity16Bit == 0)
    }

    @Test("MIDIInputEvent velocity16Bit stores value")
    func velocity16BitStored() {
        let event = MIDIInputEvent(
            noteNumber: 60, velocity: 100, velocity16Bit: 51200
        )
        #expect(event.velocity16Bit == 51200)
    }
}
