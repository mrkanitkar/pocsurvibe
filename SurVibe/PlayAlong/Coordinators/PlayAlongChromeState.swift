// SurVibe/PlayAlong/Coordinators/PlayAlongChromeState.swift
import Foundation
import SVCore
import SwiftUI
import os

/// Owns the play-along UI presentation state: chrome visibility + auto-hide,
/// view/notation modes, and resolved theme color holders.
///
/// Extracted from `PlayAlongViewModel` in SP-3c. The facade
/// (`PlayAlongViewModel`) holds `let chrome = PlayAlongChromeState()` and
/// re-exposes every owned property as a delegating computed property so
/// existing views/tests continue to read `viewModel.chromeVisibility` etc.
/// unchanged (spec AD-1 facade).
///
/// ## Public surface (spec §5.3 + §12 plan-time deviations)
/// - `chromeVisibility` (read-only) + `summonChrome / hideChrome / resetAutoHide`
///   methods for the auto-hiding control surface.
/// - `viewMode`, `notationMode` (read+write) for the view-mode toggles.
/// - 7 resolved theme color properties (`@ObservationIgnored`, set by
///   `updateTheme`).
/// - `updateTheme(_ themeManager: AppThemeManager)` resolves all 7 colors
///   from the current theme — replaces inline view-side assignment.
///
/// ## Out of scope (per §12 deviations)
/// - `latencyPreset` stays on VM (D-SP3c-1; defers to SP-3d alongside NoteRouter)
/// - Theme colors stay as 7 individual `@ObservationIgnored` properties, not
///   bundled into a struct (D-SP3c-2; preserves "no behavior changes" mandate)
///
/// ## Threading
/// `@MainActor`-isolated. Auto-hide `Task` runs on `@MainActor`.
@Observable
@MainActor
final class PlayAlongChromeState {
    // MARK: - Constants

    /// Seconds of inactivity before chrome auto-hides. Replaces the magic
    /// `6.0` literal that lived on the VM (D-SP3c-4).
    static let autoHideDuration: TimeInterval = 6.0

    // MARK: - Auto-hide override

    /// Optional override for `autoHideDuration` (used by tests to shorten the
    /// timer). `nil` → uses the static constant.
    ///
    /// Closes D-SP3c-6: previously the VM owned this knob + a parallel timer
    /// so callers could override the duration at runtime. Now the coordinator
    /// is the single source of truth; the VM's `resetAutoHide()` delegates here.
    @ObservationIgnored
    var autoHideOverrideSeconds: TimeInterval?

    // MARK: - Chrome visibility

    /// Whether the PlayAlong toolbar/summoned chrome is visible.
    ///
    /// `.summoned`: toolbar slide-down is visible.
    /// `.hidden`: only persistent chrome (pause dot, mic pill, tanpura pill)
    /// is on screen — notation dominates the view.
    enum ChromeVisibility: Sendable {
        case hidden
        case summoned
    }

    /// Current chrome state. Starts `.summoned` so users see controls on
    /// first open; transitions to `.hidden` after `autoHideDuration` of
    /// inactivity.
    private(set) var chromeVisibility: ChromeVisibility = .summoned

    /// Outstanding auto-hide timer. Cancel when user interacts.
    @ObservationIgnored
    private var chromeAutoHideTask: Task<Void, Never>?

    // MARK: - View modes

    /// Visual display mode (falling notes vs scrolling sheet).
    var viewMode: PlayAlongViewMode = .fallingNotes

    /// Notation label display mode (Sargam, Western, dual, etc.).
    var notationMode: NotationDisplayMode = .sargam

    // MARK: - Resolved theme colors
    //
    // `@ObservationIgnored` per D-SP3c-2: views receive these as `let` parameters
    // at construction time; theme changes mid-play do not propagate (matches
    // pre-SP-3c VM behavior).

    @ObservationIgnored
    var rhColor: Color = .blue
    @ObservationIgnored
    var lhColor: Color = .red
    @ObservationIgnored
    var chordColor: Color = .purple
    @ObservationIgnored
    var notationLineColor: Color = .black
    @ObservationIgnored
    var notationSecondaryColor: Color = .gray
    @ObservationIgnored
    var cardBackgroundColor: Color = .white.opacity(0.9)
    @ObservationIgnored
    var karaokeBackgroundColor: Color = .black.opacity(0.55)

    private static let logger = Logger.survibe(category: "PlayAlongChromeState")

    // MARK: - Initialization

    /// Zero-dependency init (D-SP3c-5). Theme color resolution happens at
    /// `updateTheme(_:)` call time, not at construction.
    init() {}

    // MARK: - Chrome actions

    /// Show the chrome and start/restart the auto-hide countdown.
    func summonChrome() {
        chromeVisibility = .summoned
        resetAutoHide()
    }

    /// Reset the auto-hide countdown (user interaction with a control).
    ///
    /// Uses `autoHideOverrideSeconds` if set (tests), otherwise
    /// `autoHideDuration`. A duration of `0` disables auto-hide entirely.
    func resetAutoHide() {
        chromeAutoHideTask?.cancel()
        let duration = autoHideOverrideSeconds ?? Self.autoHideDuration
        guard duration > 0 else { return }
        chromeAutoHideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.chromeVisibility = .hidden
        }
    }

    /// Hide chrome immediately. Cancels any pending auto-hide timer.
    func hideChrome() {
        chromeVisibility = .hidden
        chromeAutoHideTask?.cancel()
        chromeAutoHideTask = nil
    }

    // MARK: - Theme

    /// Resolve all 7 theme colors from the current theme manager state.
    /// Replaces inline view-side assignment at `SongPlayAlongView.swift:219-225`
    /// (D-SP3c-3).
    ///
    /// Called from `SongPlayAlongView`'s `.task` blocks. Field mapping mirrors
    /// the VM's previous inline assignment exactly — no behavior change.
    func updateTheme(_ themeManager: AppThemeManager) {
        rhColor = themeManager.resolved.rightHandColor
        lhColor = themeManager.resolved.leftHandColor
        chordColor = themeManager.resolved.chordColor
        notationLineColor = themeManager.resolved.notationLineColor
        notationSecondaryColor = themeManager.resolved.notationSecondaryColor
        cardBackgroundColor = themeManager.resolved.cardBackgroundColor
        karaokeBackgroundColor = themeManager.resolved.karaokeBackgroundColor
    }
}
