import Testing

@testable import SVAudio

struct GMProgramNameTests {
    @Test
    func returnsAcousticGrandPianoForProgramZero() {
        #expect(GMProgramName.label(for: 0) == "Acoustic Grand Piano")
    }

    @Test
    func returnsChurchOrganForProgram19() {
        #expect(GMProgramName.label(for: 19) == "Church Organ")
    }

    @Test
    func returnsViolinForProgram40() {
        #expect(GMProgramName.label(for: 40) == "Violin")
    }

    @Test
    func clampsAboveProgramRange() {
        #expect(GMProgramName.label(for: 200) == "Acoustic Grand Piano")
    }

    @Test
    func has128NonEmptyEntries() {
        for p: UInt8 in 0..<128 {
            #expect(!GMProgramName.label(for: p).isEmpty)
        }
    }
}
