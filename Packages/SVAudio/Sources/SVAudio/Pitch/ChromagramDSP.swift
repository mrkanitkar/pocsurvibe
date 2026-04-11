import Accelerate
import Foundation
import os
import Synchronization

// MARK: - Latency Preset

/// Latency preset for chord detection.
///
/// Controls the tradeoff between response time and frequency resolution.
/// The real sample count determines how much audio is analyzed per FFT window.
/// Zero-padding to 2× the real sample count interpolates the frequency spectrum
/// for better peak localization without adding real latency.
public enum LatencyPreset: String, Sendable, CaseIterable {
    /// ~23ms latency, 1024 real samples, 2048 FFT. Fastest response, lower frequency resolution.
    case ultraFast

    /// ~46ms latency, 2048 real samples, 4096 FFT. Good for C3 and above.
    case fast

    /// ~93ms latency, 4096 real samples, 8192 FFT. Full range, better accuracy.
    case balanced

    /// ~186ms latency, 8192 real samples, 16384 FFT. Low bass, complex chords.
    case precise

    /// Number of real audio samples to accumulate before performing FFT.
    public var realSamples: Int {
        switch self {
        case .ultraFast: 1024
        case .fast: 2048
        case .balanced: 4096
        case .precise: 8192
        }
    }

    /// FFT size (2× real samples for zero-padding interpolation).
    public var fftSize: Int {
        realSamples * 2
    }

    /// Approximate latency in milliseconds at 44100 Hz sample rate.
    public var latencyMs: Double {
        Double(realSamples) / 44100.0 * 1000.0
    }

    /// Human-readable description for UI display.
    public var displayName: String {
        switch self {
        case .ultraFast: String(localized: "Ultra Fast (~23ms)", bundle: .module)
        case .fast: String(localized: "Fast (~46ms)", bundle: .module)
        case .balanced: String(localized: "Balanced (~93ms)", bundle: .module)
        case .precise: String(localized: "Precise (~186ms)", bundle: .module)
        }
    }
}

// MARK: - Chromagram DSP

/// Pure-function FFT + chromagram + chord matching engine.
///
/// All methods are `nonisolated static` — safe to call from any thread
/// (audio thread, DSP queue, or MainActor). Uses only Apple's Accelerate
/// framework for SIMD-optimized DSP operations.
///
/// Pipeline: samples → Hann window → zero-pad → FFT → magnitude spectrum →
/// chromagram (12 bins) → peak detection → exact frequency extraction →
/// chord template matching.
public enum ChromagramDSP {
    // MARK: - Constants

    /// Minimum frequency for note detection (Hz). Below this, FFT bins are too noisy.
    private static let minFrequency: Double = 50.0

    /// Maximum frequency for note detection (Hz).
    private static let maxFrequency: Double = 4000.0

    /// Default chroma peak threshold (fraction of max bin value).
    public static let defaultChromaThreshold: Float = 0.3

    /// Minimum match score for chord template matching.
    private static let minChordMatchScore: Double = 0.6

    // MARK: - Caches (AUD-026, AUD-032)

    /// Cache for `vDSP_FFTSetup` objects keyed by log2(fftSize).
    ///
    /// AUD-026: Creating an FFT setup is expensive (~microseconds + allocation).
    /// SurVibe uses four fixed FFT sizes (2048, 4096, 8192, 16384 — one per
    /// LatencyPreset). After the first chord detection call per preset, the setup
    /// is reused for all subsequent calls.
    ///
    /// `OpaquePointer` is not `Sendable`, so we store raw `Int` (bit-cast) and
    /// access under a `Mutex` for compiler-verified thread safety.
    nonisolated(unsafe) private static let fftCache = Mutex<[vDSP_Length: Int]>([:])

    /// Cache for Hann window arrays keyed by sample count.
    ///
    /// AUD-032: At ultraFast (1024-sample window, 44Hz detection rate), recomputing
    /// the Hann window on every call allocates a 4KB array 44 times/second = 176KB/s.
    /// Cached once per preset size, reused for all subsequent calls.
    nonisolated(unsafe) private static let hannCache = Mutex<[Int: [Float]]>([:])

    /// Return a cached `FFTSetup` for the given log2(n), creating it if needed.
    ///
    /// - Parameter log2n: `log2(fftSize)` as a `vDSP_Length`.
    /// - Returns: A valid `OpaquePointer` to the FFT setup, or `nil` if creation fails.
    nonisolated private static func cachedFFTSetup(_ log2n: vDSP_Length) -> OpaquePointer? {
        fftCache.withLock { cache in
            if let existing = cache[log2n] {
                return OpaquePointer(bitPattern: existing)
            }
            guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
                return nil
            }
            cache[log2n] = Int(bitPattern: setup)
            return setup
        }
    }

    /// Return a cached Hann window for the given sample count, creating it if needed.
    nonisolated private static func cachedHannWindow(count: Int) -> [Float] {
        hannCache.withLock { cache in
            if let existing = cache[count] { return existing }
            var window = [Float](repeating: 0, count: count)
            vDSP_hann_window(&window, vDSP_Length(count), Int32(vDSP_HANN_NORM))
            cache[count] = window
            return window
        }
    }

    /// Western note names indexed by pitch class (0 = C).
    private static let westernNames = [
        "C", "Db", "D", "Eb", "E", "F",
        "F#", "G", "Ab", "A", "Bb", "B",
    ]

    /// Swar note names indexed by pitch class (0 = Sa).
    private static let swarNames: [String] = Swar.allCases.map(\.rawValue)

    // MARK: - Hann Window

    /// Apply a Hann window to the input samples to reduce spectral leakage.
    ///
    /// The Hann window smoothly tapers the signal edges to zero, preventing
    /// artificial high-frequency content from abrupt signal truncation.
    ///
    /// - Parameter samples: Raw audio samples.
    /// - Returns: Windowed samples of the same length.
    nonisolated public static func applyHannWindow(_ samples: [Float]) -> [Float] {
        let count = samples.count
        guard count > 0 else { return [] }
        // AUD-032: Use cached Hann window — no allocation after first call per size.
        let window = cachedHannWindow(count: count)
        var result = [Float](repeating: 0, count: count)
        vDSP_vmul(samples, 1, window, 1, &result, 1, vDSP_Length(count))
        return result
    }

    // MARK: - FFT Magnitude Spectrum

    /// Compute the magnitude spectrum of windowed samples using real-to-complex FFT.
    ///
    /// Zero-pads the input to `fftSize` for interpolated frequency resolution,
    /// then computes a forward FFT and extracts magnitudes.
    ///
    /// - Parameters:
    ///   - samples: Windowed audio samples (typically Hann-windowed).
    ///   - fftSize: FFT size (must be power of 2, typically 2× sample count).
    /// - Returns: Magnitude spectrum of length `fftSize/2`. Each bin represents
    ///   frequency `bin * sampleRate / fftSize` Hz.
    nonisolated public static func computeMagnitudeSpectrum(
        samples: [Float],
        fftSize: Int
    ) -> [Float] {
        let log2n = vDSP_Length(log2(Float(fftSize)))
        // AUD-026: Use cached FFT setup — no allocation after first call per fftSize.
        guard let fftSetup = cachedFFTSetup(log2n) else {
            assertionFailure("vDSP_create_fftsetup failed for log2n=\(log2n) — insufficient memory or invalid size")
            return [Float](repeating: 0, count: fftSize / 2)
        }
        // No defer { vDSP_destroy_fftsetup } — setup is kept alive in fftCache.

        let halfN = fftSize / 2

        // Zero-pad input to fftSize
        var paddedInput = [Float](repeating: 0, count: fftSize)
        let copyCount = min(samples.count, fftSize)
        paddedInput.replaceSubrange(0..<copyCount, with: samples[0..<copyCount])

        // Split complex format for vDSP
        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)

        // Pack interleaved real data into split complex
        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                guard let realBase = realBuf.baseAddress,
                      let imagBase = imagBuf.baseAddress else { return }
                var splitComplex = DSPSplitComplex(
                    realp: realBase,
                    imagp: imagBase)
                paddedInput.withUnsafeBufferPointer { inputBuf in
                    guard let inputBase = inputBuf.baseAddress else { return }
                    inputBase.withMemoryRebound(
                        to: DSPComplex.self, capacity: halfN
                    ) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                    }
                }

                // Forward FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }

        // Compute magnitudes: sqrt(real² + imag²)
        var magnitudes = [Float](repeating: 0, count: halfN)
        realPart.withUnsafeBufferPointer { realBuf in
            imagPart.withUnsafeBufferPointer { imagBuf in
                guard let realBase = realBuf.baseAddress,
                      let imagBase = imagBuf.baseAddress else { return }
                var splitComplex = DSPSplitComplex(
                    realp: UnsafeMutablePointer(mutating: realBase),
                    imagp: UnsafeMutablePointer(mutating: imagBase))
                vDSP_zvabs(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }

        return magnitudes
    }

    // MARK: - Chromagram

    /// Build a 12-bin chromagram from the FFT magnitude spectrum.
    ///
    /// Maps each FFT bin to one of 12 pitch classes (Sa through Ni)
    /// by computing its frequency, converting to the nearest semitone,
    /// and summing magnitudes across all octaves for that pitch class.
    /// The result is normalized to [0, 1].
    ///
    /// - Parameters:
    ///   - magnitudes: FFT magnitude spectrum from `computeMagnitudeSpectrum`.
    ///   - fftSize: FFT size used to compute the magnitudes.
    ///   - sampleRate: Audio sample rate in Hz (typically 44100).
    ///   - referencePitch: Reference pitch for A4 (default 440 Hz).
    /// - Returns: Array of 12 Float values, one per pitch class, normalized to [0, 1].
    nonisolated public static func computeChromagram(
        magnitudes: [Float],
        fftSize: Int,
        sampleRate: Double,
        referencePitch: Double = 440.0
    ) -> [Float] {
        var chroma = [Float](repeating: 0, count: 12)
        let binResolution = sampleRate / Double(fftSize)

        for bin in 1..<magnitudes.count {
            let frequency = Double(bin) * binResolution
            guard frequency >= minFrequency, frequency <= maxFrequency else { continue }

            // Convert frequency to pitch class (0-11)
            let midiNote = 69.0 + 12.0 * log2(frequency / referencePitch)
            let roundedMidi = Int(round(midiNote))
            let pitchClass = ((roundedMidi - 60) % 12 + 12) % 12

            chroma[pitchClass] += magnitudes[bin]
        }

        // Normalize by max value
        var maxVal: Float = 0
        vDSP_maxv(chroma, 1, &maxVal, vDSP_Length(12))
        if maxVal > 0 {
            var scale = 1.0 / maxVal
            vDSP_vsmul(chroma, 1, &scale, &chroma, 1, vDSP_Length(12))
        }

        return chroma
    }

    // MARK: - Peak Detection

    /// Find pitch classes with significant energy in the chromagram.
    ///
    /// - Parameters:
    ///   - chromagram: 12-bin normalized chromagram from `computeChromagram`.
    ///   - threshold: Fraction of max bin value above which a pitch class is considered active.
    /// - Returns: Array of active pitch class indices (0–11).
    nonisolated public static func detectPeaks(
        chromagram: [Float],
        threshold: Float = defaultChromaThreshold
    ) -> [Int] {
        guard chromagram.count == 12 else { return [] }

        var maxVal: Float = 0
        vDSP_maxv(chromagram, 1, &maxVal, vDSP_Length(12))
        guard maxVal > 0 else { return [] }

        let absoluteThreshold = threshold * maxVal
        var peaks: [Int] = []
        for index in 0..<12 where chromagram[index] >= absoluteThreshold {
            peaks.append(index)
        }
        return peaks
    }

    // MARK: - Exact Frequency Extraction

    /// Find the exact frequency, MIDI note, and octave for each detected pitch class.
    ///
    /// For each active pitch class, searches the magnitude spectrum for the strongest
    /// FFT bin belonging to that pitch class, applies parabolic interpolation for
    /// sub-bin frequency accuracy, then computes MIDI note, octave, and cents offset.
    ///
    /// - Parameters:
    ///   - magnitudes: FFT magnitude spectrum.
    ///   - pitchClasses: Active pitch class indices from `detectPeaks`.
    ///   - fftSize: FFT size.
    ///   - sampleRate: Audio sample rate in Hz.
    ///   - referencePitch: Reference pitch for A4 (default 440 Hz).
    /// - Returns: Array of `DetectedPitch` for each active pitch class, sorted by frequency.
    nonisolated public static func findExactFrequencies(
        magnitudes: [Float],
        pitchClasses: [Int],
        fftSize: Int,
        sampleRate: Double,
        referencePitch: Double = 440.0
    ) -> [DetectedPitch] {
        let binResolution = sampleRate / Double(fftSize)
        var maxMagnitude: Float = 0
        vDSP_maxv(magnitudes, 1, &maxMagnitude, vDSP_Length(magnitudes.count))
        guard maxMagnitude > 0 else { return [] }

        let bestBins = findBestBinsPerPitchClass(
            magnitudes: magnitudes, pitchClasses: pitchClasses,
            binResolution: binResolution, referencePitch: referencePitch
        )

        var results: [DetectedPitch] = []
        for pitchClass in pitchClasses {
            guard let best = bestBins[pitchClass],
                  best.bin > 0, best.bin < magnitudes.count - 1
            else { continue }

            let refinedFreq = interpolateFrequency(
                magnitudes: magnitudes, bin: best.bin,
                binResolution: binResolution
            )
            guard let freq = refinedFreq else { continue }

            if let pitch = buildDetectedPitch(
                frequency: freq, mag: best.mag, pitchClass: pitchClass,
                maxMagnitude: maxMagnitude, referencePitch: referencePitch
            ) {
                results.append(pitch)
            }
        }

        return results.sorted { $0.frequency < $1.frequency }
    }

    /// Find the strongest FFT bin for each active pitch class.
    nonisolated private static func findBestBinsPerPitchClass(
        magnitudes: [Float],
        pitchClasses: [Int],
        binResolution: Double,
        referencePitch: Double
    ) -> [Int: (bin: Int, mag: Float)] {
        let activePitchClasses = Set(pitchClasses)
        var bestBins = [Int: (bin: Int, mag: Float)](minimumCapacity: 12)

        for bin in 1..<magnitudes.count {
            let frequency = Double(bin) * binResolution
            guard frequency >= minFrequency, frequency <= maxFrequency else { continue }

            let midiNote = 69.0 + 12.0 * log2(frequency / referencePitch)
            let roundedMidi = Int(round(midiNote))
            let binPitchClass = ((roundedMidi - 60) % 12 + 12) % 12

            guard activePitchClasses.contains(binPitchClass) else { continue }

            if magnitudes[bin] > (bestBins[binPitchClass]?.mag ?? 0) {
                bestBins[binPitchClass] = (bin, magnitudes[bin])
            }
        }
        return bestBins
    }

    /// Parabolic interpolation to refine frequency from an FFT bin.
    nonisolated private static func interpolateFrequency(
        magnitudes: [Float], bin: Int, binResolution: Double
    ) -> Double? {
        let s0 = magnitudes[bin - 1]
        let s1 = magnitudes[bin]
        let s2 = magnitudes[bin + 1]
        let denominator = 2.0 * s1 - s0 - s2
        let refinedBin = denominator > 0
            ? Double(bin) + Double(s2 - s0) / Double(2.0 * denominator)
            : Double(bin)
        let frequency = refinedBin * binResolution
        guard frequency >= minFrequency, frequency <= maxFrequency else { return nil }
        return frequency
    }

    /// Build a DetectedPitch from a refined frequency.
    nonisolated private static func buildDetectedPitch(
        frequency: Double, mag: Float, pitchClass: Int,
        maxMagnitude: Float, referencePitch: Double
    ) -> DetectedPitch? {
        let midiNoteExact = 69.0 + 12.0 * log2(frequency / referencePitch)
        let roundedMidi = Int(round(midiNoteExact))
        let centsOffset = (midiNoteExact - Double(roundedMidi)) * 100.0
        let octave = Int(floor(Double(roundedMidi - 60) / 12.0)) + 4
        let swarIndex = ((roundedMidi - 60) % 12 + 12) % 12
        let noteName = swarIndex < swarNames.count ? swarNames[swarIndex] : "?"
        let confidence = Double(mag / maxMagnitude)

        return DetectedPitch(
            frequency: frequency, amplitude: confidence,
            midiNote: roundedMidi, pitchClass: pitchClass,
            noteName: noteName, octave: octave,
            centsOffset: centsOffset, confidence: confidence
        )
    }

    // MARK: - Chord Template Matching

    /// Match detected pitch classes against known chord templates.
    ///
    /// Tries all 12 possible root notes against all chord quality templates.
    /// Scores each combination by the fraction of template intervals that are
    /// present in the detected pitch classes. Returns the best match if it
    /// exceeds the minimum confidence threshold.
    ///
    /// - Parameters:
    ///   - pitchClasses: Set of detected pitch class indices (0–11).
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

    // MARK: - Full Pipeline

    /// Analyze audio samples for polyphonic chord content.
    ///
    /// Top-level entry point that chains: Hann window → FFT → chromagram →
    /// peak detection → exact frequency extraction → chord template matching.
    /// All computation is pure (no side effects) and thread-safe.
    ///
    /// - Parameters:
    ///   - samples: Raw audio samples (typically 2048–8192 from ring buffer).
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
        let fftSize = samples.count * 2 // Zero-pad to 2× for interpolation
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
