import Accelerate
import Foundation

// MARK: - Chord Template Matching & Full Pipeline

extension ChromagramDSP {
    /// Match detected pitch classes against known chord templates.
    ///
    /// Tries all 12 possible root notes against all chord quality templates.
    /// Scores each combination by the fraction of template intervals that are
    /// present in the detected pitch classes. Returns the best match if it
    /// exceeds the minimum confidence threshold.
    ///
    /// - Parameters:
    ///   - pitchClasses: Set of detected pitch class indices (0-11).
    ///   - referencePitch: Reference pitch for generating display names.
    /// - Returns: The best-matching `ChordName`, or nil if no good match found.
    nonisolated public static func matchChord(
        pitchClasses: Set<Int>,
        referencePitch: Double = 440.0
    ) -> ChordName? {
        // Need at least 3 pitch classes for a triad
        guard pitchClasses.count >= 3 else { return nil }

        var bestMatch: ChordName?
        var bestScore: Double = 0

        for root in 0..<12 {
            for quality in ChordQuality.allCases {
                let templateIntervals = quality.intervals
                // Transpose template to this root
                let templatePitchClasses = Set(templateIntervals.map { ($0 + root) % 12 })

                // Score: how many template notes are present in detected notes
                let matchCount = templatePitchClasses.intersection(pitchClasses).count
                let score = Double(matchCount) / Double(templatePitchClasses.count)

                // Penalize if there are many extra detected notes (noise/harmonics)
                let extraNotes = pitchClasses.subtracting(templatePitchClasses).count
                let adjustedScore = score - Double(extraNotes) * 0.05

                if adjustedScore > bestScore && adjustedScore >= minChordMatchScore {
                    bestScore = adjustedScore

                    let westernRoot = westernNames[root]
                    let swarRoot = root < swarNames.count ? swarNames[root] : "?"

                    bestMatch = ChordName(
                        rootPitchClass: root,
                        quality: quality,
                        displayName: "\(westernRoot) \(quality.rawValue)",
                        sargamDisplayName: "\(swarRoot) \(quality.rawValue)",
                        matchConfidence: adjustedScore
                    )
                }
            }
        }

        return bestMatch
    }

    /// Analyze audio samples for polyphonic chord content.
    ///
    /// Top-level entry point that chains: Hann window -> FFT -> chromagram ->
    /// peak detection -> exact frequency extraction -> chord template matching.
    /// All computation is pure (no side effects) and thread-safe.
    ///
    /// - Parameters:
    ///   - samples: Raw audio samples (typically 2048-8192 from ring buffer).
    ///   - sampleRate: Audio sample rate in Hz (typically 44100).
    ///   - referencePitch: Reference pitch for A4 (default 440 Hz).
    ///   - chromaThreshold: Peak detection threshold (fraction of max, default 0.3).
    /// - Returns: Complete `ChordResult` with detected pitches and chord name.
    nonisolated public static func analyzeChord(
        samples: [Float],
        sampleRate: Double,
        referencePitch: Double = 440.0,
        chromaThreshold: Float = defaultChromaThreshold
    ) -> ChordResult {
        guard !samples.isEmpty else {
            return ChordResult(detectedPitches: [], chordName: nil, amplitude: 0)
        }

        // RMS amplitude
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        let amplitude = Double(rms)

        // Pipeline
        let fftSize = samples.count * 2 // Zero-pad to 2x for interpolation
        let windowed = applyHannWindow(samples)
        let magnitudes = computeMagnitudeSpectrum(samples: windowed, fftSize: fftSize)
        let chromagram = computeChromagram(
            magnitudes: magnitudes, fftSize: fftSize,
            sampleRate: sampleRate, referencePitch: referencePitch)
        let peaks = detectPeaks(chromagram: chromagram, threshold: chromaThreshold)
        let pitches = findExactFrequencies(
            magnitudes: magnitudes, pitchClasses: peaks,
            fftSize: fftSize, sampleRate: sampleRate,
            referencePitch: referencePitch)

        // Chord matching
        let pitchClassSet = Set(peaks)
        let chordName = matchChord(pitchClasses: pitchClassSet, referencePitch: referencePitch)

        return ChordResult(
            detectedPitches: pitches,
            chordName: chordName,
            amplitude: amplitude
        )
    }
}
