import Testing
@testable import SVCore

struct MusicalDurationTests {
    @Test func quarterIsOneBeat() {
        #expect(MusicalDuration.quarter.beats == 1.0)
    }

    @Test func eighthIsHalfBeat() {
        #expect(MusicalDuration.eighth.beats == 0.5)
    }

    @Test func dottedQuarterIsOnePointFive() {
        #expect(MusicalDuration.dottedQuarter.beats == 1.5)
    }

    @Test func sixteenthIsQuarterBeat() {
        #expect(MusicalDuration.sixteenth.beats == 0.25)
    }

    @Test func tripletEighthIsThirdBeat() {
        #expect(abs(MusicalDuration.tripletEighth.beats - (1.0 / 3.0)) < 1e-9)
    }
}
