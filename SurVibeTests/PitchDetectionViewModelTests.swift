import Foundation
import SVCore
import Testing

@testable import SVAudio
@testable import SurVibe

@Suite("PitchDetectionViewModel Tests")
@MainActor
struct PitchDetectionViewModelTests {
    // MARK: - Initial State

    @Test("Initial state is not listening")
    func initialStateNotListening() {
        let vm = PitchDetectionViewModel(
            permissions: MockPermissionProvider(),
            audioEngine: MockAudioEngineProvider()
        )
        #expect(vm.isListening == false)
    }

    @Test("Initial detection mode is melody")
    func initialDetectionModeIsMelody() {
        let vm = PitchDetectionViewModel(
            permissions: MockPermissionProvider(),
            audioEngine: MockAudioEngineProvider()
        )
        #expect(vm.detectionMode == .melody)
    }

    @Test("Initial debug status is 'Not started'")
    func initialDebugStatus() {
        let vm = PitchDetectionViewModel(
            permissions: MockPermissionProvider(),
            audioEngine: MockAudioEngineProvider()
        )
        #expect(vm.debugStatus == "Not started")
    }

    @Test("Initial recent notes is empty")
    func initialRecentNotesEmpty() {
        let vm = PitchDetectionViewModel(
            permissions: MockPermissionProvider(),
            audioEngine: MockAudioEngineProvider()
        )
        #expect(vm.recentNotes.isEmpty)
    }

    @Test("Initial detection count is zero")
    func initialDetectionCountZero() {
        let vm = PitchDetectionViewModel(
            permissions: MockPermissionProvider(),
            audioEngine: MockAudioEngineProvider()
        )
        #expect(vm.detectionCount == 0)
    }

    @Test("Initial active MIDI notes is empty")
    func initialActiveMidiNotesEmpty() {
        let vm = PitchDetectionViewModel(
            permissions: MockPermissionProvider(),
            audioEngine: MockAudioEngineProvider()
        )
        #expect(vm.activeMidiNotes.isEmpty)
    }

    @Test("Initial error message is nil")
    func initialErrorMessageNil() {
        let vm = PitchDetectionViewModel(
            permissions: MockPermissionProvider(),
            audioEngine: MockAudioEngineProvider()
        )
        #expect(vm.errorMessage == nil)
    }

    @Test("Initial chord result is nil")
    func initialChordResultNil() {
        let vm = PitchDetectionViewModel(
            permissions: MockPermissionProvider(),
            audioEngine: MockAudioEngineProvider()
        )
        #expect(vm.currentChordResult == nil)
    }

    @Test("Initial live amplitude is zero")
    func initialLiveAmplitudeZero() {
        let vm = PitchDetectionViewModel(
            permissions: MockPermissionProvider(),
            audioEngine: MockAudioEngineProvider()
        )
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

    // MARK: - stopListening (with DI)

    @Test("stopListening resets state and calls engine stop/removeMicTap")
    func stopListeningResetsState() {
        let engine = MockAudioEngineProvider()
        let vm = PitchDetectionViewModel(
            permissions: MockPermissionProvider(),
            audioEngine: engine
        )
        vm.stopListening()
        #expect(vm.isListening == false)
        #expect(vm.debugStatus == "Stopped")
        #expect(vm.currentChordResult == nil)
        #expect(vm.currentExpression == nil)
        #expect(engine.stopCallCount == 1)
    }

    // MARK: - DI: micStatus reflects injected provider

    @Test("micStatus reflects injected permission provider status")
    func micStatusReflectsPermissionProvider() {
        let mock = MockPermissionProvider()
        mock.microphoneStatus = .denied
        let vm = PitchDetectionViewModel(
            permissions: mock,
            audioEngine: MockAudioEngineProvider()
        )
        #expect(vm.micStatus == .denied)
    }

    @Test("micStatus returns authorized when provider says authorized")
    func micStatusAuthorized() {
        let mock = MockPermissionProvider()
        mock.microphoneStatus = .authorized
        let vm = PitchDetectionViewModel(
            permissions: mock,
            audioEngine: MockAudioEngineProvider()
        )
        #expect(vm.micStatus == .authorized)
    }

    @Test("settingsURL reflects injected permission provider URL")
    func settingsURLReflectsProvider() {
        let mock = MockPermissionProvider()
        mock.settingsURL = URL(string: "test://settings")
        let vm = PitchDetectionViewModel(
            permissions: mock,
            audioEngine: MockAudioEngineProvider()
        )
        #expect(vm.settingsURL == URL(string: "test://settings"))
    }

    @Test("settingsURL returns nil when provider returns nil")
    func settingsURLNil() {
        let mock = MockPermissionProvider()
        mock.settingsURL = nil
        let vm = PitchDetectionViewModel(
            permissions: mock,
            audioEngine: MockAudioEngineProvider()
        )
        #expect(vm.settingsURL == nil)
    }

    // MARK: - DI: startListening uses injected dependencies

    @Test("startListening sets error when permission denied")
    func startListeningPermissionDenied() async {
        let permMock = MockPermissionProvider()
        permMock.requestMicrophoneAccessResult = false
        let vm = PitchDetectionViewModel(
            permissions: permMock,
            audioEngine: MockAudioEngineProvider()
        )
        await vm.startListening()
        #expect(permMock.updateMicrophoneStatusCallCount >= 1)
        #expect(permMock.requestMicrophoneAccessCallCount == 1)
        #expect(vm.isListening == false)
        #expect(vm.errorMessage != nil)
    }

    @Test("startListening sets error when engine fails to start")
    func startListeningEngineFailure() async {
        let permMock = MockPermissionProvider()
        permMock.requestMicrophoneAccessResult = true
        permMock.microphoneStatus = .notDetermined
        let engineMock = MockAudioEngineProvider()
        engineMock.shouldThrowOnStart = true
        let vm = PitchDetectionViewModel(
            permissions: permMock,
            audioEngine: engineMock
        )
        await vm.startListening()
        #expect(engineMock.startCallCount == 1)
        #expect(vm.isListening == false)
        #expect(vm.errorMessage != nil)
    }

    @Test("startListening transitions to listening state when permission is granted")
    func startListeningSuccess() async {
        // Post-MIDI-2.0 wiring (PR #8): MicPitchDetector internally owns
        // AudioEngineManager.shared.start() and the mic tap install — the
        // injected mock engine is no longer touched on the start path. We
        // assert only the user-visible state transition; engine-level
        // interactions are covered by MicPitchDetector's own tests.
        let permMock = MockPermissionProvider()
        permMock.requestMicrophoneAccessResult = true
        permMock.microphoneStatus = .notDetermined
        let engineMock = MockAudioEngineProvider()
        let vm = PitchDetectionViewModel(
            permissions: permMock,
            audioEngine: engineMock
        )
        await vm.startListening()
        #expect(vm.isListening == true)
    }
}
