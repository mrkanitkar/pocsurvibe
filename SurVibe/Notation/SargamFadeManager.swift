import SwiftUI

/// Manages the label opacity of Sargam notes based on user accuracy.
///
/// As the user's accuracy improves, note labels fade away, forcing
/// the student to play by ear. This progressive fade encourages
/// memorisation and internalisation of the sargam patterns.
/// Thresholds follow the Rang level progression:
/// - accuracy < 0.6: full opacity (1.0) — beginner, needs all labels
/// - accuracy 0.6..<0.8: reduced opacity (0.6)
/// - accuracy 0.8..<0.95: low opacity (0.3)
/// - accuracy >= 0.95: invisible (0.0) — mastery, no labels needed
///
/// The behaviour can be disabled via the `autoHideSargamLabels` toggle
/// (persisted in UserDefaults), which locks opacity at 1.0.
///
/// Views consuming `labelOpacity` should apply `.animation()` to animate transitions.
@Observable
@MainActor
final class SargamFadeManager {
    // MARK: - Properties

    /// Current label opacity (0.0–1.0).
    private(set) var labelOpacity: Double = 1.0

    /// The most recent accuracy value that was applied.
    private(set) var currentAccuracy: Double = 0.0

    /// When false, labels stay at full opacity regardless of accuracy.
    ///
    /// Persisted via `@AppStorage` so the preference survives app restarts.
    /// Wrapped with `@ObservationIgnored` because `@AppStorage` already
    /// triggers SwiftUI updates through its own property-wrapper machinery.
    @ObservationIgnored
    @AppStorage("autoHideSargamLabels") var autoHideSargamLabels: Bool = true

    // MARK: - Public Methods

    /// Updates the label opacity based on the user's playing accuracy.
    ///
    /// Higher accuracy causes labels to fade, encouraging the student
    /// to play by ear once they have learned the piece. When the
    /// `autoHideSargamLabels` toggle is off, opacity is always 1.0.
    ///
    /// - Parameter accuracy: A value from 0.0 (no accuracy) to 1.0 (perfect).
    ///   Values outside this range are clamped.
    func updateOpacity(accuracy: Double) {
        let clampedAccuracy = min(1.0, max(0.0, accuracy))
        currentAccuracy = clampedAccuracy

        guard autoHideSargamLabels else {
            labelOpacity = 1.0
            return
        }

        let newOpacity: Double
        switch clampedAccuracy {
        case 0.95...1.0:
            newOpacity = 0.0
        case 0.8..<0.95:
            newOpacity = 0.3
        case 0.6..<0.8:
            newOpacity = 0.6
        default:
            newOpacity = 1.0
        }

        labelOpacity = newOpacity
    }

    /// Resets opacity to full (1.0) without animation.
    ///
    /// Called when starting a new practice session or switching songs
    /// to ensure the user sees all labels from the beginning.
    func reset() {
        labelOpacity = 1.0
        currentAccuracy = 0.0
    }
}
