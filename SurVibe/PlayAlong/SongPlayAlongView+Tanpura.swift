import SVAudio
import SVCore
import SVLearning
import SwiftData
import SwiftUI
import os.log

/// Tanpura-drone wiring for `SongPlayAlongView`.
///
/// Split out from the main view to keep the type body under the
/// SwiftLint `type_body_length` / `file_length` thresholds. All helpers
/// here touch `@State` properties declared on `SongPlayAlongView` itself;
/// the state stays on the struct because SwiftUI state must live on the
/// owning type, not in extensions.

/// Logger for tanpura persistence wiring in `SongPlayAlongView`.
private let tanpuraWiringLogger = Logger.survibe(category: "TanpuraWiring")

extension SongPlayAlongView {
    // MARK: - Tanpura sheet & pill

    /// Tanpura settings sheet body, extracted from the `.sheet` modifier in
    /// `body` so the top-level closure stays under the Swift type-checker's
    /// complexity budget.
    @ViewBuilder
    var tanpuraSettingsSheetContent: some View {
        TanpuraSettingsSheet(
            controller: tanpura,
            canResetToSongDefault: canResetToSongDefault,
            onResetToSongDefault: {
                resetPreferredSaHz()
                AnalyticsManager.shared.track(
                    .tanpuraResetToDefault,
                    properties: ["song_title": song.title]
                )
            },
            onToggleAnalytics: { enabled in
                AnalyticsManager.shared.track(
                    .tanpuraToggled,
                    properties: [
                        "enabled": enabled,
                        "song_title": song.title,
                        "source": "sheet"
                    ]
                )
            }
        )
    }

    /// Resolves the pill mode for the current theme preset, supplying localized
    /// fallbacks when `song.artist` is empty. Extracted into its own function so
    /// the `String(localized:)` calls don't inflate the containing closure past
    /// the Swift type-checker's complexity budget.
    func resolvedPillMode() -> TanpuraRagaPill.Mode {
        switch themeManager.currentPreset {
        case .popEra:
            let artist = song.artist.isEmpty ? String(localized: "Artist") : song.artist
            return .popSong(artist: artist, song: song.title)
        case .sargamGlass, .sargamGlassBars, .neonRhythm:
            let name = song.artist.isEmpty ? String(localized: "Raga") : song.artist
            return .raga(name: name)
        default:
            return .westernKey(key: "C major", bpm: song.tempo)
        }
    }

    /// Context-aware top-left pill derived from the current theme/song.
    @ViewBuilder
    var tanpuraRagaPill: some View {
        let mode: TanpuraRagaPill.Mode = resolvedPillMode()
        TanpuraRagaPill(
            mode: mode,
            saLabel: Self.saLabel(pitchClass: tanpura.saPitchClass, octave: tanpura.saOctave),
            backgroundColor: viewModel.cardBackgroundColor,
            foregroundColor: themeManager.resolved.primaryTextColor,
            onTap: {
                showTanpuraSheet = true
                AnalyticsManager.shared.track(
                    .tanpuraSheetOpened,
                    properties: ["song_title": song.title]
                )
            }
        )
    }

    /// Pretty-print a pitch class + octave as "C♯4".
    static func saLabel(pitchClass: Int, octave: Int) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        let pc = ((pitchClass % 12) + 12) % 12
        return "\(names[pc])\(octave)"
    }

    // MARK: - Tanpura persistence helpers

    /// True when the current `SongProgress` row has a non-nil `preferredSaHz`,
    /// gating the "Reset to song default" footer button in the sheet.
    var canResetToSongDefault: Bool {
        let slug = song.slugId
        guard let progress = try? modelContext.fetch(
            FetchDescriptor<SongProgress>(
                predicate: #Predicate { $0.songId == slug }
            )
        ).first else { return false }
        return progress.preferredSaHz != nil
    }

    /// Write the effective Sa Hz to the song's SongProgress row, creating it if needed.
    func persistPreferredSaHz(_ effectiveHz: Double) {
        let slug = song.slugId
        let existing = try? modelContext.fetch(
            FetchDescriptor<SongProgress>(
                predicate: #Predicate { $0.songId == slug }
            )
        ).first
        let target: SongProgress
        if let existing {
            target = existing
        } else {
            target = SongProgress(songId: slug, songTitle: song.title)
            modelContext.insert(target)
        }
        target.preferredSaHz = effectiveHz
        do {
            try modelContext.save()
        } catch {
            // Non-fatal: log and continue.
            tanpuraWiringLogger.error("Save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Clear the persisted override and reseed the controller from the song default.
    func resetPreferredSaHz() {
        let slug = song.slugId
        if let progress = try? modelContext.fetch(
            FetchDescriptor<SongProgress>(
                predicate: #Predicate { $0.songId == slug }
            )
        ).first {
            progress.preferredSaHz = nil
            try? modelContext.save()
        }
        // Suppress the observer for the re-seed mutation below — otherwise
        // the 1s debounce would write the song default right back into
        // preferredSaHz, defeating the reset.
        suppressNextPersistenceTick = true
        tanpura.seed(preferredSaHz: nil, songDefaultHz: song.defaultSaFrequencyHz)
    }
}
