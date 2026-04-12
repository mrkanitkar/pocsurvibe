import Foundation
import Testing

@testable import SVAudio

// MARK: - Test Helpers

/// Generate a sinusoidal signal at a given frequency.
private func sinusoid(
    frequency: Double,
    sampleRate: Double = 44100.0,
    duration: Int = 2048,
    amplitude: Float = 1.0
) -> [Float] {
    (0..<duration).map { i in
        amplitude * Float(sin(2.0 * .pi * frequency * Double(i) / sampleRate))
    }
}

/// Generate a chord (sum of sinusoids) and normalize.
private func chord(
    frequencies: [Double],
    sampleRate: Double = 44100.0,
    duration: Int = 2048
) -> [Float] {
    var samples = [Float](repeating: 0, count: duration)
    for freq in frequencies {
        let component = sinusoid(frequency: freq, sampleRate: sampleRate, duration: duration)
        for i in 0..<duration {
            samples[i] += component[i]
        }
    }
    // Normalize to prevent clipping
    let maxVal = samples.map(abs).max() ?? 1.0
    if maxVal > 0 {
        for i in 0..<duration { samples[i] /= maxVal }
    }
    return samples
}

// MARK: - Latency Preset Tests

@Suite("LatencyPreset")
@MainActor
struct LatencyPresetTests {
    @Test func ultraFastPresetValues() {
        let preset = LatencyPreset.ultraFast
        #expect(preset.realSamples == 1024)
        #expect(preset.fftSize == 2048)
        #expect(abs(preset.latencyMs - 23.2) < 1.0)
    }

    @Test func fastPresetValues() {
        let preset = LatencyPreset.fast
        #expect(preset.realSamples == 2048)
        #expect(preset.fftSize == 4096)
        #expect(abs(preset.latencyMs - 46.4) < 1.0)
    }

    @Test func balancedPresetValues() {
        let preset = LatencyPreset.balanced
        #expect(preset.realSamples == 4096)
        #expect(preset.fftSize == 8192)
        #expect(abs(preset.latencyMs - 92.9) < 1.0)
    }

    @Test func precisePresetValues() {
        let preset = LatencyPreset.precise
        #expect(preset.realSamples == 8192)
        #expect(preset.fftSize == 16384)
        #expect(abs(preset.latencyMs - 185.8) < 1.0)
    }

    @Test func allPresetsHavePowerOfTwoFFTSize() {
        for preset in LatencyPreset.allCases {
            let fftSize = preset.fftSize
            #expect(fftSize > 0 && (fftSize & (fftSize - 1)) == 0)
        }
    }
}

// MARK: - Hann Window Tests

@Suite("Hann Window")
@MainActor
struct HannWindowTests {
    @Test func outputHasCorrectLength() {
        let samples = [Float](repeating: 1.0, count: 512)
        let windowed = ChromagramDSP.applyHannWindow(samples)
        #expect(windowed.count == 512)
    }

    @Test func edgesAreNearZero() {
        let samples = [Float](repeating: 1.0, count: 256)
        let windowed = ChromagramDSP.applyHannWindow(samples)
        #expect(abs(windowed[0]) < 0.01)
        #expect(abs(windowed[255]) < 0.01)
    }

    @Test func centerHasMaximumValue() {
        let samples = [Float](repeating: 1.0, count: 256)
        let windowed = ChromagramDSP.applyHannWindow(samples)
        let maxVal = windowed.max() ?? 0
        let midVal = windowed[128]
        #expect(abs(midVal - maxVal) < 0.01)
    }

    @Test func emptyInputReturnsEmpty() {
        let windowed = ChromagramDSP.applyHannWindow([])
        #expect(windowed.isEmpty)
    }
}

// MARK: - FFT Tests

@Suite("FFT Magnitude Spectrum")
@MainActor
struct FFTMagnitudeTests {
    @Test func silenceProducesNearZeroMagnitudes() {
        let silence = [Float](repeating: 0, count: 1024)
        let magnitudes = ChromagramDSP.computeMagnitudeSpectrum(samples: silence, fftSize: 2048)
        #expect(magnitudes.count == 1024)
        let maxMag = magnitudes.max() ?? 0
        #expect(maxMag < 0.001)
    }

    @Test func singleSinusoidProducesPeakAtCorrectBin() {
        let sampleRate = 44100.0
        let frequency = 440.0 // A4
        let samples = sinusoid(frequency: frequency, sampleRate: sampleRate, duration: 2048)
        let fftSize = 4096
        let windowed = ChromagramDSP.applyHannWindow(samples)
        let magnitudes = ChromagramDSP.computeMagnitudeSpectrum(
            samples: windowed, fftSize: fftSize)

        // Expected bin: frequency * fftSize / sampleRate
        let expectedBin = Int(round(frequency * Double(fftSize) / sampleRate))
        // Find the actual peak bin
        var peakBin = 0
        var peakVal: Float = 0
        for (bin, mag) in magnitudes.enumerated() where mag > peakVal {
            peakVal = mag
            peakBin = bin
        }
        // Allow ±2 bins due to windowing
        #expect(abs(peakBin - expectedBin) <= 2)
    }
}

// MARK: - Chromagram Tests

@Suite("Chromagram")
@MainActor
struct ChromagramTests {
    @Test func singleNoteActivatesOneChromaBin() {
        let sampleRate = 44100.0
        // A4 = 440 Hz, pitch class 9 (Dha)
        let samples = sinusoid(frequency: 440.0, sampleRate: sampleRate, duration: 2048)
        let fftSize = 4096
        let windowed = ChromagramDSP.applyHannWindow(samples)
        let magnitudes = ChromagramDSP.computeMagnitudeSpectrum(
            samples: windowed, fftSize: fftSize)
        let chromagram = ChromagramDSP.computeChromagram(
            magnitudes: magnitudes, fftSize: fftSize, sampleRate: sampleRate)

        #expect(chromagram.count == 12)
        // Pitch class 9 (A/Dha) should be dominant
        let maxBin = chromagram.enumerated().max(by: { $0.element < $1.element })
        #expect(maxBin?.offset == 9)
    }

    @Test func chromagramValuesAreBetweenZeroAndOne() {
        let samples = sinusoid(frequency: 261.63, sampleRate: 44100, duration: 2048)
        let fftSize = 4096
        let windowed = ChromagramDSP.applyHannWindow(samples)
        let magnitudes = ChromagramDSP.computeMagnitudeSpectrum(
            samples: windowed, fftSize: fftSize)
        let chromagram = ChromagramDSP.computeChromagram(
            magnitudes: magnitudes, fftSize: fftSize, sampleRate: 44100)

        for value in chromagram {
            #expect(value >= 0.0 && value <= 1.0)
        }
    }
}

// MARK: - Chord Template Matching Tests

@Suite("Chord Template Matching")
@MainActor
struct ChordMatchingTests {
    @Test func cMajorDetected() {
        // C Major = pitch classes {0, 4, 7}
        let result = ChromagramDSP.matchChord(pitchClasses: [0, 4, 7])
        #expect(result?.quality == .major)
        #expect(result?.rootPitchClass == 0)
        #expect(result?.displayName == "C Major")
    }

    @Test func aMinorDetected() {
        // A Minor = pitch classes {9, 0, 4} (root=9, intervals {0,3,7})
        let result = ChromagramDSP.matchChord(pitchClasses: [9, 0, 4])
        #expect(result?.quality == .minor)
        #expect(result?.rootPitchClass == 9)
    }

    @Test func gDominant7Detected() {
        // G7 = pitch classes {7, 11, 2, 5} (root=7, intervals {0,4,7,10})
        let result = ChromagramDSP.matchChord(pitchClasses: [7, 11, 2, 5])
        #expect(result?.quality == .dominant7)
        #expect(result?.rootPitchClass == 7)
    }

    @Test func singleNoteReturnsNil() {
        let result = ChromagramDSP.matchChord(pitchClasses: [0])
        #expect(result == nil)
    }

    @Test func twoNotesReturnNil() {
        let result = ChromagramDSP.matchChord(pitchClasses: [0, 4])
        #expect(result == nil)
    }

    @Test func emptyInputReturnsNil() {
        let result = ChromagramDSP.matchChord(pitchClasses: [])
        #expect(result == nil)
    }
}

// MARK: - Full Pipeline Tests

@Suite("Full Chord Analysis Pipeline")
@MainActor
struct FullPipelineTests {
    @Test func syntheticCMajorChordDetected() {
        let sampleRate = 44100.0
        // C4 + E4 + G4
        let samples = chord(
            frequencies: [261.63, 329.63, 392.00],
            sampleRate: sampleRate, duration: 4096)

        let result = ChromagramDSP.analyzeChord(
            samples: samples, sampleRate: sampleRate)

        #expect(result.detectedPitches.count >= 3)
        // Root should be C (pitch class 0)
        #expect(result.chordName?.rootPitchClass == 0)
        // Harmonics in synthetic signals can activate extra pitch classes,
        // so accept either Major or Major7 as valid matches.
        let quality = result.chordName?.quality
        #expect(quality == .major || quality == .major7)
        #expect(result.amplitude > 0)
    }

    @Test func emptyInputReturnsEmptyResult() {
        let result = ChromagramDSP.analyzeChord(
            samples: [], sampleRate: 44100.0)

        #expect(result.detectedPitches.isEmpty)
        #expect(result.chordName == nil)
        #expect(result.amplitude == 0)
    }

    @Test func silentInputReturnsNoNotes() {
        let silence = [Float](repeating: 0, count: 2048)
        let result = ChromagramDSP.analyzeChord(
            samples: silence, sampleRate: 44100.0)

        #expect(result.detectedPitches.isEmpty)
        #expect(result.chordName == nil)
    }

    @Test func singleNoteDetectedWithoutChordName() {
        let sampleRate = 44100.0
        let samples = sinusoid(frequency: 440.0, sampleRate: sampleRate, duration: 2048)
        let result = ChromagramDSP.analyzeChord(
            samples: samples, sampleRate: sampleRate)

        #expect(result.detectedPitches.count >= 1)
        // Single note should not match any chord template (needs 3+ pitch classes)
        #expect(result.chordName == nil)
    }
}

// MARK: - ChordResult Model Tests

@Suite("ChordResult Model")
@MainActor
struct ChordResultModelTests {
    @Test func activeMidiNotesComputedCorrectly() {
        let pitches = [
            DetectedPitch(
                frequency: 261.63, amplitude: 0.8, midiNote: 60,
                pitchClass: 0, noteName: "Sa", octave: 4,
                centsOffset: 0, confidence: 0.9),
            DetectedPitch(
                frequency: 329.63, amplitude: 0.7, midiNote: 64,
                pitchClass: 4, noteName: "Ga", octave: 4,
                centsOffset: 0, confidence: 0.8),
            DetectedPitch(
                frequency: 392.0, amplitude: 0.6, midiNote: 67,
                pitchClass: 7, noteName: "Pa", octave: 4,
                centsOffset: 0, confidence: 0.7),
        ]
        let result = ChordResult(
            detectedPitches: pitches, chordName: nil, amplitude: 0.5)

        #expect(result.activeMidiNotes == [60, 64, 67])
    }

    @Test func emptyPitchesGiveEmptyMidiNotes() {
        let result = ChordResult(
            detectedPitches: [], chordName: nil, amplitude: 0)
        #expect(result.activeMidiNotes.isEmpty)
    }

    @Test func chordQualityIntervalsAreCorrect() {
        #expect(ChordQuality.major.intervals == [0, 4, 7])
        #expect(ChordQuality.minor.intervals == [0, 3, 7])
        #expect(ChordQuality.diminished.intervals == [0, 3, 6])
        #expect(ChordQuality.augmented.intervals == [0, 4, 8])
        #expect(ChordQuality.dominant7.intervals == [0, 4, 7, 10])
    }
}
