import Testing

@testable import SVAudio

@Suite("MIDIOutputManager")
struct MIDIOutputManagerTests {

    @Test("start and stop lifecycle does not crash")
    func startStopLifecycle() throws {
        let manager = MIDIOutputManager()
        try manager.start()
        manager.stop()
    }

    @Test("stop is safe to call without start")
    func stopWithoutStart() {
        let manager = MIDIOutputManager()
        manager.stop()
    }

    @Test("double stop does not crash")
    func doubleStop() throws {
        let manager = MIDIOutputManager()
        try manager.start()
        manager.stop()
        manager.stop()
    }

    @Test("double start is idempotent")
    func doubleStart() throws {
        let manager = MIDIOutputManager()
        try manager.start()
        try manager.start()
        manager.stop()
    }

    @Test("Sendable conformance")
    func sendableConformance() {
        let manager = MIDIOutputManager()
        let _: any Sendable = manager
        #expect(true)
    }

    @Test("send methods are no-ops when not started")
    func sendWithoutStart() {
        let manager = MIDIOutputManager()
        // These should be no-ops (guard on isStarted), not crashes
        manager.noteOn(note: 60, velocity: 100, channel: 0)
        manager.noteOff(note: 60, channel: 0)
        manager.controlChange(controller: 64, value: 127, channel: 0)
        manager.pitchBend(value: 0x8000_0000, channel: 0)
        manager.programChange(program: 0, channel: 0)
        #expect(true)
    }

    @Test("send methods do not crash when started")
    func sendWhenStarted() throws {
        let manager = MIDIOutputManager()
        try manager.start()
        manager.noteOn(note: 60, velocity: 100, channel: 0)
        manager.noteOff(note: 60, channel: 0)
        manager.controlChange(controller: 64, value: 127, channel: 0)
        manager.pitchBend(value: 0x8000_0000, channel: 0)
        manager.programChange(program: 0, channel: 0)
        manager.stop()
    }

    @Test("selectDestination out of range is a no-op")
    func selectDestinationOutOfRange() {
        let manager = MIDIOutputManager()
        // No crash expected even with invalid index
        manager.selectDestination(at: -1)
        manager.selectDestination(at: 999)
        #expect(true)
    }
}
