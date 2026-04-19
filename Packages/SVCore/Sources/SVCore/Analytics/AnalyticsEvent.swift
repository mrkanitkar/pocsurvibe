import Foundation

/// Analytics events for SurVibe pipeline and feature tracking.
public enum AnalyticsEvent: String, Sendable, CaseIterable {
    // Sprint 0 verification events
    case appScaffoldingLoaded = "app_scaffolding_loaded"
    case audioPocPitchDetected = "audio_poc_pitch_detected"
    case cloudKitSyncCompleted = "cloudkit_sync_completed"

    // Navigation events
    case tabSelected = "tab_selected"
    case sessionStarted = "session_started"
    case sessionEnded = "session_ended"

    // Settings events
    case languageChanged = "language_changed"

    // Day 4 events
    case doorTapped = "door_tapped"
    case songPlaybackStarted = "song_playback_started"
    case songPlaybackPaused = "song_playback_paused"
    case songPlaybackCompleted = "song_playback_completed"

    // Day 6 — Onboarding events
    case onboardingScreenViewed = "onboarding_screen_viewed"
    case onboardingSkipped = "onboarding_skipped"
    case onboardingCompleted = "onboarding_completed"

    // Day 7 — Auth events
    case signInStarted = "sign_in_started"
    case signInCompleted = "sign_in_completed"
    case signInFailed = "sign_in_failed"
    case signInCancelled = "sign_in_cancelled"
    case signOutCompleted = "sign_out_completed"
    case credentialRevoked = "credential_revoked"

    // Day 8 — Song Library events
    case songFavoriteToggled = "song_favorite_toggled"
    case songFilterApplied = "song_filter_applied"
    case songSearchPerformed = "song_search_performed"
    case songLibraryViewed = "song_library_viewed"

    // Day 9 — Practice Mode events
    case practiceSessionStarted = "practice_session_started"
    case practiceSessionCompleted = "practice_session_completed"
    case practiceSessionRestarted = "practice_session_restarted"

    // Day 10 — Wait Mode events
    case waitModeToggled = "wait_mode_toggled"
    case waitModeNoteAttempted = "wait_mode_note_attempted"
    case waitModeCompleted = "wait_mode_completed"

    // Play-Along session events — DEPRECATED: ViewModel fires songPlaybackStarted/Completed instead.
    // Cases kept to avoid breaking existing PostHog dashboard queries.
    // Do not fire these from new code; use songPlaybackStarted/songPlaybackCompleted.
    @available(*, deprecated, renamed: "songPlaybackStarted",
               message: "Use songPlaybackStarted with enriched properties instead.")
    case playAlongStarted = "play_along_started"
    @available(*, deprecated, renamed: "songPlaybackCompleted",
               message: "Use songPlaybackCompleted with enriched properties instead.")
    case playAlongCompleted = "play_along_completed"
    @available(*, deprecated,
               message: "Not fired — retained for PostHog dashboard compatibility only.")
    case playAlongAbandoned = "play_along_abandoned"

    // Play-Along toolbar interaction events
    case playAlongTempoChanged = "play_along_tempo_changed"
    case playAlongViewModeChanged = "play_along_view_mode_changed"
    case playAlongNotationToggled = "play_along_notation_toggled"
    case playAlongSoundToggled = "play_along_sound_toggled"
    case playAlongRestarted = "play_along_restarted"
    case themeChanged = "theme_changed"

    // Play-Along tanpura events
    case tanpuraToggled = "play_along_tanpura_toggled"
    case tanpuraSaChanged = "play_along_tanpura_sa_changed"
    case tanpuraResetToDefault = "play_along_tanpura_reset_to_default"
    case tanpuraSheetOpened = "play_along_tanpura_sheet_opened"

    // Song Import events
    case songImportStarted = "song_import_started"
    case songImportCompleted = "song_import_completed"
    case songImportFailed = "song_import_failed"
    case importMidiPlaybackStarted = "import_midi_playback_started"
    case songImportSynced = "song_import_synced"
    case songImportWarningDisplayed = "song_import_warning_displayed"

    // Song CRUD events (user-imported songs)
    case songEdited = "song_edited"
    case songDeleted = "song_deleted"

    // Diagnostics events
    case latencySnapshot = "latency_snapshot"

    // MARK: - SP-0 additions

    /// Consumer: SP-1 (iPad shell) — user activated a sidebar destination.
    case sidebarUsed = "sidebar_used"
    /// Consumer: SP-1 (iPad shell) — user invoked a keyboard shortcut.
    case shortcutInvoked = "shortcut_invoked"
    /// Consumer: SP-0 (foundation) — developer toggled a feature flag.
    case featureFlagToggled = "feature_flag_toggled"
    /// Consumer: SP-0 (foundation) / SP-4 (polish) — Settings view opened.
    case settingsOpened = "settings_opened"
    /// Consumer: SP-5 (AI harness) — on-device AI consent prompt presented.
    case aiConsentShown = "ai_consent_shown"
    /// Consumer: SP-5 (AI harness) — user granted on-device AI consent.
    case aiConsentGranted = "ai_consent_granted"
    /// Consumer: SP-5 (AI harness) — user revoked on-device AI consent.
    case aiConsentRevoked = "ai_consent_revoked"
    /// Consumer: SP-6 (Mac) — a Mac window was opened.
    case macWindowOpened = "mac_window_opened"

    // MARK: - CaseIterable (manual — required because deprecated cases have @available attributes)

    /// All analytics event cases, including deprecated ones retained for PostHog dashboard compatibility.
    ///
    /// Swift cannot synthesize `allCases` when any case carries an `@available` attribute (SE-0192).
    /// This manual implementation ensures test coverage for uniqueness and snake_case across the full vocabulary.
    public static var allCases: [AnalyticsEvent] {
        [
            .appScaffoldingLoaded, .audioPocPitchDetected, .cloudKitSyncCompleted,
            .tabSelected, .sessionStarted, .sessionEnded,
            .languageChanged,
            .doorTapped, .songPlaybackStarted, .songPlaybackPaused, .songPlaybackCompleted,
            .onboardingScreenViewed, .onboardingSkipped, .onboardingCompleted,
            .signInStarted, .signInCompleted, .signInFailed, .signInCancelled,
            .signOutCompleted, .credentialRevoked,
            .songFavoriteToggled, .songFilterApplied, .songSearchPerformed, .songLibraryViewed,
            .practiceSessionStarted, .practiceSessionCompleted, .practiceSessionRestarted,
            .waitModeToggled, .waitModeNoteAttempted, .waitModeCompleted,
            .playAlongStarted, .playAlongCompleted, .playAlongAbandoned,
            .playAlongTempoChanged, .playAlongViewModeChanged, .playAlongNotationToggled,
            .playAlongSoundToggled, .playAlongRestarted, .themeChanged,
            .tanpuraToggled, .tanpuraSaChanged, .tanpuraResetToDefault, .tanpuraSheetOpened,
            .songImportStarted, .songImportCompleted, .songImportFailed,
            .importMidiPlaybackStarted, .songImportSynced, .songImportWarningDisplayed,
            .songEdited, .songDeleted,
            .latencySnapshot,
            .sidebarUsed, .shortcutInvoked, .featureFlagToggled, .settingsOpened,
            .aiConsentShown, .aiConsentGranted, .aiConsentRevoked,
            .macWindowOpened,
        ]
    }
}
