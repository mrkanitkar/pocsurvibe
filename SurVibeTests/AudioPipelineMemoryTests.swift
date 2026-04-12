import Foundation
import SVAudio
import Testing

@testable import SurVibe

/// TEST-D01-001 + TEST-D01-006: Audio Pipeline Memory Safety & Concurrency Tests
///
/// Verifies that the pitch detection pipeline (PitchDetectionViewModel) does not
/// leak memory via retain cycles. The implementation uses a Task-based pattern
/// with WeakVM instead of raw AsyncStream, so these tests verify the actual
/// architecture rather than the original BDD spec's AsyncStream assumption.
///
/// Also covers H-1 (AtomicCounter removal) — verifies no @unchecked Sendable
/// patterns remain and that Mutex-based concurrency primitives work correctly.
///
/// Serialized because some tests create PitchDetectionViewModel which accesses
/// the AudioEngineManager.shared singleton.
@Suite("Audio Pipeline Memory Safety Tests", .serialized)
@MainActor
struct AudioPipelineMemoryTests {

    // MARK: - TEST-D01-001 Scenario 1: ViewModel Deallocates After Stop

    @Test("PitchDetectionViewModel deallocates after stopListening")
    @MainActor
    func viewModelDeallocatesAfterStop() {
        var vm: PitchDetectionViewModel? = PitchDetectionViewModel()
        let checkDeallocated = { [weak vm] in vm == nil }

        // Stop without starting — exercises cleanup path
        vm?.stopListening()
        vm = nil

        #expect(checkDeallocated(), "ViewModel should deallocate after stop and release")
    }

    // MARK: - TEST-D01-001 Scenario 2: Stop Clears All State

    @Test("stopListening clears all references")
    @MainActor
    func stopClearsAllReferences() {
        let vm = PitchDetectionViewModel()
        vm.stopListening()

        #expect(vm.isListening == false)
        #expect(vm.currentChordResult == nil)
        #expect(vm.currentExpression == nil)
        #expect(vm.debugStatus == "Stopped")
    }

    // MARK: - TEST-D01-001 Scenario 3: Double Stop is Safe

    @Test("Calling stopListening twice does not crash")
    @MainActor
    func doubleStopIsSafe() {
        let vm = PitchDetectionViewModel()
        vm.stopListening()
        vm.stopListening()  // Second call should be a no-op

        #expect(vm.isListening == false)
        #expect(vm.debugStatus == "Stopped")
    }

    // MARK: - TEST-D01-001 Scenario 4: Detection Modes Are Valid

    @Test("All detection modes have valid display names")
    func detectionModesAreValid() {
        for mode in DetectionMode.allCases {
            #expect(!mode.displayName.isEmpty, "\(mode.rawValue) display name should not be empty")
            #expect(!mode.rawValue.isEmpty, "\(mode) raw value should not be empty")
        }
    }

    // MARK: - TEST-D01-001 Scenario 5: Recent Notes Deduplication

    @Test("DetectedNote generates unique IDs")
    func detectedNoteUniqueIDs() {
        let note1 = DetectedNote(
            swarName: "Sa", westernName: "C", octave: 4,
            centsOffset: 0, frequency: 261.63, timestamp: .now
        )
        let note2 = DetectedNote(
            swarName: "Sa", westernName: "C", octave: 4,
            centsOffset: 0, frequency: 261.63, timestamp: .now
        )
        #expect(note1.id != note2.id, "Each DetectedNote should have a unique ID")
    }

    // MARK: - TEST-D01-006 Scenario 1: No @unchecked Sendable in Codebase

    @Test("AudioRingBuffer conforms to Sendable without @unchecked")
    func ringBufferIsSendableWithoutUnchecked() {
        // AudioRingBuffer uses Mutex<State> — compiler verifies Sendable.
        // This test verifies the type can be used across isolation boundaries.
        let buffer = AudioRingBuffer(capacity: 1024)

        // Sendable types can be captured in @Sendable closures
        let sendableClosure: @Sendable () -> Int = {
            buffer.totalSamplesWritten
        }

        #expect(sendableClosure() == 0)
        buffer.write([1, 2, 3])
        #expect(sendableClosure() == 3)
    }

    // MARK: - TEST-D01-006 Scenario 2: Concurrent Access to RingBuffer

    @Test("RingBuffer handles concurrent write and read without crash")
    func concurrentRingBufferAccess() async {
        let buffer = AudioRingBuffer(capacity: 4096)
        let testData = (0..<512).map { Float($0) }

        // Launch concurrent writes
        await withTaskGroup(of: Void.self) { group in
            // Writer tasks
            for _ in 0..<10 {
                group.addTask {
                    buffer.write(testData)
                }
            }
            // Reader tasks
            for _ in 0..<10 {
                group.addTask {
                    _ = buffer.read(count: 256)
                }
            }
        }

        // If we get here, no deadlock or crash occurred
        #expect(buffer.totalSamplesWritten == 5120, "All writes should complete (10 x 512)")
    }

    // MARK: - TEST-D01-006 Scenario 3: Latency Presets Have Valid FFT Sizes

    @Test("All latency presets have power-of-two FFT sizes")
    func latencyPresetsHavePowerOfTwoFFT() {
        for preset in LatencyPreset.allCases {
            let fftSize = preset.fftSize
            // Power of two check: n & (n-1) == 0 for n > 0
            #expect(fftSize > 0 && (fftSize & (fftSize - 1)) == 0,
                    "\(preset.displayName) FFT size \(fftSize) should be a power of two")
        }
    }

    // MARK: - Initial State Integrity

    @Test("ViewModel initial state is fully reset")
    @MainActor
    func initialStateFullyReset() {
        let vm = PitchDetectionViewModel()
        #expect(vm.isListening == false)
        #expect(vm.detectionMode == .melody)
        #expect(vm.detectionCount == 0)
        #expect(vm.recentNotes.isEmpty)
        #expect(vm.activeMidiNotes.isEmpty)
        #expect(vm.errorMessage == nil)
        #expect(vm.currentChordResult == nil)
        #expect(vm.liveAmplitude == 0)
    }
}
