import os
import Testing

@testable import SVAudio

// MARK: - OSSignposter Integration Tests

@Suite("OSSignposter Integration")
struct OSSignposterTests {
    @Test func signposterCreationDoesNotCrash() {
        let signposter = OSSignposter(subsystem: "com.survibe.test", category: "Test")
        let id = signposter.makeSignpostID()
        let state = signposter.beginInterval("TestInterval", id: id)
        signposter.endInterval("TestInterval", state)
    }

    @Test func chromagramDSPOutputUnchangedWithSignposter() {
        // Create a 440 Hz sine wave and verify FFT magnitudes are computed correctly.
        let sampleRate = 44100.0
        let samples: [Float] = (0..<1024).map {
            Float(sin(Double($0) * 2.0 * .pi * 440.0 / sampleRate))
        }
        let fftSize = 2048
        let magnitudes = ChromagramDSP.computeMagnitudeSpectrum(
            samples: samples, fftSize: fftSize
        )
        // fftSize/2 bins returned
        #expect(magnitudes.count == fftSize / 2)
        // A 440 Hz signal should produce non-zero magnitudes
        #expect(magnitudes.contains(where: { $0 > 0 }))
    }

    @Test func chordMatchingWorksWithSignposter() {
        // C Major triad — pitch classes {0, 4, 7}
        let result = ChromagramDSP.matchChord(pitchClasses: [0, 4, 7])
        #expect(result != nil)
        #expect(result?.quality == .major)
        #expect(result?.rootPitchClass == 0)
    }

    @Test func fullPipelineWithSignposterProducesValidResult() {
        // Verify the full analyzeChord pipeline (which exercises both
        // FFTComputation and ChordMatching signpost intervals) still
        // produces correct results.
        let sampleRate = 44100.0
        // C4 + E4 + G4 chord
        let frequencies = [261.63, 329.63, 392.00]
        var samples = [Float](repeating: 0, count: 4096)
        for freq in frequencies {
            for i in 0..<4096 {
                samples[i] += Float(sin(Double(i) * 2.0 * .pi * freq / sampleRate))
            }
        }
        // Normalize
        let maxVal = samples.map(abs).max() ?? 1.0
        if maxVal > 0 {
            for i in 0..<samples.count { samples[i] /= maxVal }
        }

        let result = ChromagramDSP.analyzeChord(
            samples: samples, sampleRate: sampleRate
        )
        #expect(result.amplitude > 0)
        #expect(result.detectedPitches.count >= 3)
    }
}
