import Foundation
import Testing

@testable import SVAudio
@testable import SVCore

// MARK: - SVCore Localization

@Suite("SVCore Localization Validation")
@MainActor
struct SVCoreLocalizationTests {
    @Test func allProficiencyLabelsNonEmpty() {
        for level in RangLevel.allCases {
            let label = level.proficiencyLabel
            #expect(!label.isEmpty, "proficiencyLabel for \(level.displayName) should not be empty")
        }
    }

    @Test func allSwarLabelsNonEmpty() {
        let swarNames = [
            "Sa", "Komal Re", "Re", "Komal Ga", "Ga", "Ma",
            "Tivra Ma", "Pa", "Komal Dha", "Dha", "Komal Ni", "Ni",
        ]
        for name in swarNames {
            let label = AccessibilityHelper.swarLabel(for: name)
            #expect(label.count > name.count, "swarLabel for \(name) should be longer than the note name alone")
        }
    }

    @Test func unknownSwarNameReturnsSelf() {
        let label = AccessibilityHelper.swarLabel(for: "UnknownNote")
        #expect(label == "UnknownNote")
    }

    @Test func pitchAccuracyLabelsNonEmpty() {
        let inTune = AccessibilityHelper.pitchAccuracyLabel(centsOffset: 0)
        #expect(!inTune.isEmpty)

        let sharp = AccessibilityHelper.pitchAccuracyLabel(centsOffset: 15)
        #expect(!sharp.isEmpty)

        let flat = AccessibilityHelper.pitchAccuracyLabel(centsOffset: -20)
        #expect(!flat.isEmpty)
    }
}

// MARK: - SVAudio Localization

@Suite("SVAudio Localization Validation")
@MainActor
struct SVAudioLocalizationTests {
    @Test func allLatencyPresetDisplayNamesNonEmpty() {
        for preset in LatencyPreset.allCases {
            let name = preset.displayName
            #expect(!name.isEmpty, "displayName for \(preset.rawValue) should not be empty")
        }
    }

    @Test func allExpressionTypeDisplayNamesNonEmpty() {
        let types: [ExpressionType] = [.stable, .vibrato, .meend, .gamaka, .indeterminate]
        for type in types {
            let name = type.displayName
            #expect(!name.isEmpty, "displayName for \(type.rawValue) should not be empty")
        }
    }
}
