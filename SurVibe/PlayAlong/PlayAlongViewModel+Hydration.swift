import Foundation
import SwiftData

// MARK: - Per-song preference hydration & persistence

extension PlayAlongViewModel {

    /// Hydrate VM state from a stored SongProgress row.
    ///
    /// First-launch policy: if the row was just created (all defaults),
    /// caller should pass `seedFromVM: true` and `persistSettings(to:)` will
    /// write the VM's current state INTO the row instead of overwriting VM.
    ///
    /// - Parameters:
    ///   - progress: The SongProgress row to hydrate from (or seed into).
    ///   - seedFromVM: If true, writes VM state into the progress row
    ///     instead of reading from it.
    func loadPersistedSettings(
        from progress: SongProgress,
        seedFromVM: Bool = false
    ) async {
        if seedFromVM {
            await persistSettings(to: progress, immediate: true)
            didInitialHydrate = true
            return
        }
        if let saHz = progress.preferredSaHz {
            tonicSaPitch = Self.midiPitch(forSaHz: saHz)
        }
        tempoScale = max(0.5, min(1.5, progress.preferredTempoScale))
        // Remaining field hydration wired in Wave 5 T5.4
        didInitialHydrate = true
    }

    /// Persist VM state to SongProgress (debounced 250 ms unless `immediate`).
    ///
    /// - Parameters:
    ///   - progress: The SongProgress row to persist into.
    ///   - immediate: If true, skips debounce and writes immediately.
    func persistSettings(
        to progress: SongProgress,
        immediate: Bool = false
    ) async {
        persistDebounceTask?.cancel()
        if immediate {
            applySettingsToRow(progress)
            return
        }
        persistDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            await MainActor.run { self.applySettingsToRow(progress) }
        }
    }

    /// Write current VM state into the given SongProgress row.
    func applySettingsToRow(_ progress: SongProgress) {
        progress.preferredSaHz = Self.saHz(forMIDIPitch: tonicSaPitch)
        progress.preferredTempoScale = tempoScale
        // Remaining field assignments — full wiring in Wave 5 T5.4
        try? progress.modelContext?.save()
    }

    // MARK: - MIDI ↔ Hz conversion

    /// Convert Sa frequency in Hz to nearest MIDI pitch number.
    nonisolated static func midiPitch(forSaHz hz: Double) -> UInt8 {
        let midi = 69.0 + 12.0 * log2(hz / 440.0)
        return UInt8(clamping: Int(midi.rounded()))
    }

    /// Convert MIDI pitch number to frequency in Hz.
    nonisolated static func saHz(forMIDIPitch midi: UInt8) -> Double {
        440.0 * pow(2.0, (Double(midi) - 69.0) / 12.0)
    }
}
