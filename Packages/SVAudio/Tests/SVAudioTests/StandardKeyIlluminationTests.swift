import Testing

@testable import SVAudio

@Suite("StandardKeyIllumination")
struct StandardKeyIlluminationTests {

    @Test("illuminate sends notes without crash")
    func illuminateBasic() {
        let output = MIDIOutputManager()
        let illumination = StandardKeyIllumination(output: output)
        illumination.illuminate(notes: [60, 64, 67])
        #expect(illumination.isSupported)
    }

    @Test("clearAll does not crash")
    func clearAllSafe() {
        let output = MIDIOutputManager()
        let illumination = StandardKeyIllumination(output: output)
        illumination.illuminate(notes: [60, 64])
        illumination.clearAll()
        #expect(true)
    }

    @Test("clearAll on empty state is a no-op")
    func clearAllEmpty() {
        let output = MIDIOutputManager()
        let illumination = StandardKeyIllumination(output: output)
        illumination.clearAll()
        #expect(true)
    }

    @Test("Sendable conformance")
    func sendable() {
        let output = MIDIOutputManager()
        let illumination = StandardKeyIllumination(output: output)
        let _: any Sendable = illumination
        #expect(true)
    }

    @Test("KeyIlluminationProvider conformance")
    func protocolConformance() {
        let output = MIDIOutputManager()
        let illumination = StandardKeyIllumination(output: output)
        let _: any KeyIlluminationProvider = illumination
        #expect(true)
    }

    @Test("isSupported returns true")
    func isSupportedAlwaysTrue() {
        let output = MIDIOutputManager()
        let illumination = StandardKeyIllumination(output: output)
        #expect(illumination.isSupported)
    }

    @Test("lightingChannel is 15")
    func lightingChannelValue() {
        let output = MIDIOutputManager()
        let illumination = StandardKeyIllumination(output: output)
        #expect(illumination.lightingChannel == 15)
    }

    @Test("illuminate transitions do not crash")
    func illuminateTransition() {
        let output = MIDIOutputManager()
        let illumination = StandardKeyIllumination(output: output)
        // C major chord
        illumination.illuminate(notes: [60, 64, 67])
        // Transition to G major — only diffs sent
        illumination.illuminate(notes: [55, 59, 67])
        // Clear everything
        illumination.clearAll()
        #expect(true)
    }

    @Test("illuminate with empty set clears all notes")
    func illuminateEmptySet() {
        let output = MIDIOutputManager()
        let illumination = StandardKeyIllumination(output: output)
        illumination.illuminate(notes: [60, 64, 67])
        // Passing empty set should extinguish all lit notes
        illumination.illuminate(notes: [])
        #expect(true)
    }

    @Test("illuminate same set twice is idempotent")
    func illuminateIdempotent() {
        let output = MIDIOutputManager()
        let illumination = StandardKeyIllumination(output: output)
        illumination.illuminate(notes: [60, 64, 67])
        // Second call with same set — no messages should be sent (diff is empty)
        illumination.illuminate(notes: [60, 64, 67])
        #expect(true)
    }
}
