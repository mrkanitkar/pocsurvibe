import Foundation
import SVAudio
import SVCore
import SVLearning

// MARK: - Pitch Monitoring & Scoring

extension PracticeSessionViewModel {
    /// Start the elapsed practice time tracker.
    ///
    /// Updates `elapsedPracticeTime` every second via `Task.sleep`.
    func startPracticeTimer() {
        practiceTimerTask?.cancel()
        practiceTimerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let startTime = self.practiceStartTime else {
                    return
                }
                self.elapsedPracticeTime = Date().timeIntervalSince(startTime)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// Start the pitch monitoring loop.
    ///
    /// Consumes pitch results from the audio processor's async stream,
    /// compares each detected note against the expected sargam note,
    /// and produces `NoteScore` values. Automatically completes the
    /// session when all notes have been played.
    func startPitchMonitoring() {
        pitchMonitoringTask?.cancel()
        pitchMonitoringTask = Task { [weak self] in
            guard let self else { return }
            for await pitch in self.audioProcessor.pitchStream {
                guard !Task.isCancelled, self.phase == .practiceAlong else { break }
                guard self.currentPracticeNoteIndex < self.sargamNotes.count else {
                    self.completePractice()
                    break
                }

                // Enrich with raga context when mapper is available
                let enrichedPitch = self.enrichPitchWithRagaContext(pitch)
                self.currentPitch = enrichedPitch

                guard enrichedPitch.amplitude >= PracticeConstants.silenceThreshold,
                      enrichedPitch.confidence >= PracticeConstants.confidenceThreshold
                else { continue }

                // Track first valid pitch for "First Note" achievement
                if !self.hasTrackedFirstPitch {
                    self.hasTrackedFirstPitch = true
                    self.gamificationService?.handleFirstPitchDetected()
                }

                if self.processDetectedPitch(enrichedPitch) { break }
            }
        }
    }

    /// Score a detected pitch against the current expected note.
    ///
    /// Compares the detected pitch against the expected sargam note at the
    /// current index. Updates live accuracy counters and advances the note
    /// index when the correct note is detected.
    ///
    /// - Parameter pitch: The enriched pitch result to score.
    /// - Returns: `true` if the session is now complete (all notes played).
    func processDetectedPitch(_ pitch: PitchResult) -> Bool {
        let expected = sargamNotes[currentPracticeNoteIndex]
        let expectedName = expected.modifier.map { "\($0.capitalized) \(expected.note)" } ?? expected.note

        // Use JI cents deviation when raga context is available, otherwise 12ET
        let centsDeviation: Double
        if let ragaCents = pitch.ragaCentsOffset {
            centsDeviation = abs(ragaCents)
        } else {
            centsDeviation = abs(pitch.centsOffset)
        }

        let score = NoteScoreCalculator.score(
            expectedNote: expectedName, detectedNote: pitch.noteName,
            pitchDeviationCents: centsDeviation,
            timingDeviationSeconds: 0.05, durationDeviation: 0.1,
            ragaPitchDeviationCents: pitch.ragaCentsOffset.map { abs($0) },
            ragaContext: ragaScoringContext
        )
        noteScores.append(score)
        // AUD-017: Maintain live counters incrementally -- O(1) per note.
        liveAccuracySum += score.accuracy
        liveStreak = score.grade == .miss ? 0 : liveStreak + 1
        if pitch.noteName == expectedName && pitch.octave == expected.octave {
            currentPracticeNoteIndex += 1
            if currentPracticeNoteIndex >= sargamNotes.count {
                completePractice()
                return true
            }
        }
        return false
    }
}
