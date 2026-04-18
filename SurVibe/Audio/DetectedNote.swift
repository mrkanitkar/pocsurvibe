import Foundation

/// A detected note for display in the recent-pitch history list.
///
/// Produced by `PitchDetectionViewModel` when a microphone-detected pitch
/// crosses confidence and amplitude thresholds. Carries both the Sargam
/// (`Sa`, `Re`, ...) and Western (`C`, `D`, ...) names plus tuning offset
/// in cents so the UI can show how far the player is from equal-temperament.
struct DetectedNote: Identifiable {
    /// Stable identifier so SwiftUI lists can diff entries efficiently.
    let id = UUID()
    /// Sargam name (e.g. `"Sa"`, `"Komal Ga"`).
    let swarName: String
    /// Western pitch class name (e.g. `"C"`, `"D#"`).
    let westernName: String
    /// Octave number using middle-C = 4 convention.
    let octave: Int
    /// Tuning offset from equal-temperament in cents (-50 to +50).
    let centsOffset: Double
    /// Detected fundamental frequency in Hz.
    let frequency: Double
    /// Wall-clock timestamp at the moment the note was detected.
    let timestamp: Date
}
