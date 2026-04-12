import Foundation
import Testing

@testable import SurVibe

@Suite("PitchDetectionViewModel Tests")
@MainActor
struct PitchDetectionViewModelTests {
    // MARK: - Initial State

    @Test("Initial state is not listening")
    @MainActor
    func initialStateNotListening() {
        let vm = PitchDetectionViewModel()
        #expect(vm.isListening == false)
    }

    @Test("Initial detection mode is melody")
    @MainActor
    func initialDetectionModeIsMelody() {
        let vm = PitchDetectionViewModel()
        #expect(vm.detectionMode == .melody)
    }

    @Test("Initial debug status is 'Not started'")
    @MainActor
    func initialDebugStatus() {
        let vm = PitchDetectionViewModel()
        #expect(vm.debugStatus == "Not started")
    }

    @Test("Initial recent notes is empty")
    @MainActor
    func initialRecentNotesEmpty() {
        let vm = PitchDetectionViewModel()
        #expect(vm.recentNotes.isEmpty)
    }

    @Test("Initial detection count is zero")
    @MainActor
    func initialDetectionCountZero() {
        let vm = PitchDetectionViewModel()
        #expect(vm.detectionCount == 0)
    }

    @Test("Initial active MIDI notes is empty")
    @MainActor
    func initialActiveMidiNotesEmpty() {
        let vm = PitchDetectionViewModel()
        #expect(vm.activeMidiNotes.isEmpty)
    }

    @Test("Initial error message is nil")
    @MainActor
    func initialErrorMessageNil() {
        let vm = PitchDetectionViewModel()
        #expect(vm.errorMessage == nil)
    }

    @Test("Initial chord result is nil")
    @MainActor
    func initialChordResultNil() {
        let vm = PitchDetectionViewModel()
        #expect(vm.currentChordResult == nil)
    }

    @Test("Initial live amplitude is zero")
    @MainActor
    func initialLiveAmplitudeZero() {
        let vm = PitchDetectionViewModel()
        #expect(vm.liveAmplitude == 0)
    }

    // MARK: - Detection Mode

    @Test("DetectionMode has three cases")
    func detectionModeHasThreeCases() {
        #expect(DetectionMode.allCases.count == 3)
    }

    @Test("DetectionMode raw values are stable strings")
    func detectionModeRawValues() {
        #expect(DetectionMode.melody.rawValue == "melody")
        #expect(DetectionMode.chord.rawValue == "chord")
        #expect(DetectionMode.both.rawValue == "both")
    }

    @Test("DetectionMode display names are non-empty")
    func detectionModeDisplayNames() {
        for mode in DetectionMode.allCases {
            #expect(!mode.displayName.isEmpty, "\(mode.rawValue) display name should not be empty")
        }
    }

    // MARK: - DetectedNote

    @Test("DetectedNote has unique IDs")
    func detectedNoteUniqueIDs() {
        let note1 = DetectedNote(
            swarName: "Sa", westernName: "C", octave: 4,
            centsOffset: 0, frequency: 261.63, timestamp: .now
        )
        let note2 = DetectedNote(
            swarName: "Sa", westernName: "C", octave: 4,
            centsOffset: 0, frequency: 261.63, timestamp: .now
        )
        #expect(note1.id != note2.id)
    }

    // MARK: - stopListening

    @Test("stopListening resets state without prior start")
    @MainActor
    func stopListeningResetsState() {
        let vm = PitchDetectionViewModel()
        // Should not crash even when called without prior start
        vm.stopListening()
        #expect(vm.isListening == false)
        #expect(vm.debugStatus == "Stopped")
        #expect(vm.currentChordResult == nil)
        #expect(vm.currentExpression == nil)
    }
}
