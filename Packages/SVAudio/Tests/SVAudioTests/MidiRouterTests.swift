import Foundation
import Synchronization
import Testing

@testable import SVAudio

@Suite("MidiRouter Tests")
struct MidiRouterTests {

    @Test("Note event routes to registered handler")
    func noteRouting() {
        let router = MidiRouter()
        let received = Mutex<MIDIInputEvent?>(nil)
        router.onNote { event in received.withLock { $0 = event } }

        let event = MIDIInputEvent(noteNumber: 60, velocity: 100)
        router.routeNote(event)
        #expect(received.withLock { $0?.noteNumber } == 60)
    }

    @Test("CC event routes to registered handler")
    func ccRouting() {
        let router = MidiRouter()
        let received = Mutex<MIDIControlChangeEvent?>(nil)
        router.onControlChange { event in received.withLock { $0 = event } }

        let event = MIDIControlChangeEvent(controller: 64, value: 127)
        router.routeCC(event)
        #expect(received.withLock { $0?.controller } == 64)
    }

    @Test("Pitch bend event routes to registered handler")
    func pitchBendRouting() {
        let router = MidiRouter()
        let received = Mutex<MIDIPitchBendEvent?>(nil)
        router.onPitchBend { event in received.withLock { $0 = event } }

        let event = MIDIPitchBendEvent(value: 1000, channel: 1)
        router.routePitchBend(event)
        #expect(received.withLock { $0?.value } == 1000)
    }

    @Test("Pressure event routes to registered handler")
    func pressureRouting() {
        let router = MidiRouter()
        let received = Mutex<MIDIPressureEvent?>(nil)
        router.onPressure { event in received.withLock { $0 = event } }

        let event = MIDIPressureEvent(noteNumber: 64, pressure: 5000)
        router.routePressure(event)
        #expect(received.withLock { $0?.noteNumber } == 64)
    }

    @Test("Program change event routes to registered handler")
    func programChangeRouting() {
        let router = MidiRouter()
        let received = Mutex<MIDIProgramChangeEvent?>(nil)
        router.onProgramChange { event in received.withLock { $0 = event } }

        let event = MIDIProgramChangeEvent(program: 42)
        router.routeProgramChange(event)
        #expect(received.withLock { $0?.program } == 42)
    }

    @Test("Per-note control event routes to registered handler")
    func perNoteControlRouting() {
        let router = MidiRouter()
        let received = Mutex<MIDIPerNoteControlEvent?>(nil)
        router.onPerNoteControl { event in received.withLock { $0 = event } }

        let event = MIDIPerNoteControlEvent(noteNumber: 60, index: 7, value: 1000)
        router.routePerNoteControl(event)
        #expect(received.withLock { $0?.noteNumber } == 60)
    }

    @Test("Registered control event routes to registered handler")
    func registeredControlRouting() {
        let router = MidiRouter()
        let received = Mutex<MIDIRegisteredControlEvent?>(nil)
        router.onRegisteredControl { event in received.withLock { $0 = event } }

        let event = MIDIRegisteredControlEvent(bank: 0, index: 0, value: 100)
        router.routeRegisteredControl(event)
        #expect(received.withLock { $0?.bank } == 0)
    }

    @Test("Per-note management event routes to registered handler")
    func perNoteManagementRouting() {
        let router = MidiRouter()
        let received = Mutex<MIDIPerNoteManagementEvent?>(nil)
        router.onPerNoteManagement { event in received.withLock { $0 = event } }

        let event = MIDIPerNoteManagementEvent(noteNumber: 60, detach: true, reset: false)
        router.routePerNoteManagement(event)
        #expect(received.withLock { $0?.detach } == true)
    }

    @Test("removeAll clears all registrations")
    func removeAllClearsRegistrations() {
        let router = MidiRouter()
        let noteCount = Mutex(0)
        let bendCount = Mutex(0)
        router.onNote { _ in noteCount.withLock { $0 += 1 } }
        router.onPitchBend { _ in bendCount.withLock { $0 += 1 } }

        router.removeAll()

        router.routeNote(MIDIInputEvent(noteNumber: 60, velocity: 100))
        router.routePitchBend(MIDIPitchBendEvent(value: 100))
        #expect(noteCount.withLock { $0 } == 0)
        #expect(bendCount.withLock { $0 } == 0)
    }

    @Test("EventFilter.all includes all new types")
    func eventFilterAll() {
        let all = MidiRouter.EventFilter.all
        #expect(all.contains(.noteEvents))
        #expect(all.contains(.controlChange))
        #expect(all.contains(.pitchBend))
        #expect(all.contains(.pressure))
        #expect(all.contains(.programChange))
        #expect(all.contains(.perNoteControl))
        #expect(all.contains(.registeredControl))
        #expect(all.contains(.perNoteManagement))
    }
}
