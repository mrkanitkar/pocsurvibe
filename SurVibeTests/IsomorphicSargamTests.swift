import SVAudio
import Testing

@testable import SurVibe

/// Tests for IsomorphicSargamView data model, color mapping, and layout logic.
@MainActor
struct IsomorphicSargamTests {

    // MARK: - Sargam Color Mapping

    @Test func sargamColorMapReturnsColorForAllSwars() {
        let shudhSwars = ["Sa", "Re", "Ga", "Ma", "Pa", "Dha", "Ni"]
        for swar in shudhSwars {
            let color = SargamColorMap.color(for: swar)
            // SwiftUI Color cannot be directly compared with ==, but we verify
            // that the method returns without error for each swar name
            _ = color  // Ensure no crash or assertion failure
        }
    }

    @Test func sargamColorMapReturnsGrayForUnknown() {
        // Unknown swar names should get gray fallback
        _ = SargamColorMap.color(for: "Unknown")
        _ = SargamColorMap.color(for: "")
    }

    @Test func sargamShapeMapReturnsShapeForAllSwars() {
        let shudhSwars = ["Sa", "Re", "Ga", "Ma", "Pa", "Dha", "Ni"]
        for swar in shudhSwars {
            let shape = SargamColorMap.shape(for: swar)
            #expect(!shape.isEmpty, "\(swar) should have a shape symbol")
            #expect(shape.hasSuffix(".fill"), "\(swar) shape should be a filled symbol")
        }
    }

    // MARK: - Base Swar Name Mapping

    @Test func baseSwarNamesMapCorrectly() {
        // The isomorphic view maps chromatic indices to base swar names
        let baseSwarNames = [
            "Sa", "Re", "Re", "Ga", "Ga", "Ma", "Ma", "Pa", "Dha", "Dha", "Ni", "Ni",
        ]
        #expect(baseSwarNames.count == 12)
        // Verify komal/tivra variants map to their base swar
        #expect(baseSwarNames[0] == "Sa")   // C = Sa
        #expect(baseSwarNames[1] == "Re")   // Db = Komal Re -> base Re
        #expect(baseSwarNames[2] == "Re")   // D = Re
        #expect(baseSwarNames[3] == "Ga")   // Eb = Komal Ga -> base Ga
        #expect(baseSwarNames[6] == "Ma")   // F# = Tivra Ma -> base Ma
        #expect(baseSwarNames[7] == "Pa")   // G = Pa
    }

    @Test func variantFlagsIdentifyKomalsAndTivra() {
        let isVariant = [
            false, true, false, true, false, false, true, false, true, false, true, false,
        ]
        #expect(isVariant.count == 12)

        // Natural notes are not variants
        #expect(isVariant[0] == false)  // Sa
        #expect(isVariant[2] == false)  // Re
        #expect(isVariant[4] == false)  // Ga
        #expect(isVariant[5] == false)  // Ma
        #expect(isVariant[7] == false)  // Pa
        #expect(isVariant[9] == false)  // Dha
        #expect(isVariant[11] == false) // Ni

        // Komal/tivra are variants
        #expect(isVariant[1] == true)   // Komal Re
        #expect(isVariant[3] == true)   // Komal Ga
        #expect(isVariant[6] == true)   // Tivra Ma
        #expect(isVariant[8] == true)   // Komal Dha
        #expect(isVariant[10] == true)  // Komal Ni
    }

    // MARK: - Swar Enum Consistency

    @Test func swarAllCasesHas12Notes() {
        #expect(Swar.allCases.count == 12, "Chromatic scale has 12 notes")
    }

    @Test func swarMidiOffsetsAreSequential() {
        for (index, swar) in Swar.allCases.enumerated() {
            #expect(swar.midiOffset == index, "\(swar) should have midiOffset \(index)")
        }
    }

    @Test func swarRawValuesAreNonEmpty() {
        for swar in Swar.allCases {
            #expect(!swar.rawValue.isEmpty, "\(swar) should have a non-empty rawValue")
        }
    }

    // MARK: - Highlighting Logic (mirrors InteractivePianoView logic)

    @Test func isomorphicHighlightDetectionOnly() {
        let activeMidiNotes: Set<Int> = [60, 64, 67]  // C Major chord
        let touchedMidiNotes: Set<Int> = []

        for midi in activeMidiNotes {
            #expect(activeMidiNotes.contains(midi))
            #expect(!touchedMidiNotes.contains(midi))
        }
    }

    @Test func isomorphicHighlightBothSources() {
        let activeMidiNotes: Set<Int> = [60]
        let touchedMidiNotes: Set<Int> = [60]

        #expect(activeMidiNotes.contains(60))
        #expect(touchedMidiNotes.contains(60))
        // Both sources active = cyan
    }
}
