import SVCore
import SwiftUI

/// Full-screen overlay displaying results after completing a play-along session.
///
/// Shows the song title, star rating, accuracy percentage, notes-hit progress,
/// longest streak, and XP earned. Includes "Play Again" and "Done" action buttons.
/// A celebration animation plays on appearance unless the user has Reduce Motion enabled.
///
/// ## Usage
/// ```swift
/// PlayAlongResultsOverlay(
///     songTitle: "Raag Yaman",
///     accuracy: 0.92,
///     notesHit: 46,
///     totalNotes: 50,
///     streak: 23,
///     starRating: 4,
///     xpEarned: 120,
///     onReplay: { engine.restart() },
///     onDone: { dismiss() }
/// )
/// ```
struct PlayAlongResultsOverlay: View {
    // MARK: - Properties

    /// Title of the completed song.
    let songTitle: String

    /// Final accuracy as a fraction (0.0 to 1.0).
    let accuracy: Double

    /// Number of notes the player hit correctly.
    let notesHit: Int

    /// Total number of notes in the song.
    let totalNotes: Int

    /// Longest consecutive correct-note streak achieved.
    let streak: Int

    /// Star rating earned (1 to 5).
    let starRating: Int

    /// Experience points awarded for this session.
    let xpEarned: Int

    /// Called when the user taps "Play Again".
    var onReplay: () -> Void

    /// Called when the user taps "Done".
    var onDone: () -> Void

    @Environment(AppThemeManager.self)
    private var themeManager

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State
    private var showCelebration = false

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .accessibilityHidden(true)

            VStack(spacing: 24) {
                headerSection
                starsSection
                statsSection
                xpSection
                actionsSection
            }
            .padding(32)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 24)
            .overlay { celebrationOverlay }
        }
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                    showCelebration = true
                }
            }
        }
    }

    // MARK: - Private Views

    /// Song title and completion message.
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Session Complete")
                .font(.headline)
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)

            Text(songTitle)
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .accessibilityLabel("Song: \(songTitle)")
        }
    }

    /// Star rating display (1 to 5 filled/empty stars).
    private var starsSection: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= starRating ? "star.fill" : "star")
                    .foregroundStyle(index <= starRating ? .yellow : .gray)
                    .font(.title2)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(starRating) out of 5 stars")
    }

    /// Accuracy, notes hit, and streak statistics.
    private var statsSection: some View {
        VStack(spacing: 16) {
            // Accuracy — prominent display
            VStack(spacing: 4) {
                Text(CompactScoringHUD.formatAccuracy(accuracy))
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .accessibilityLabel(
                        "Accuracy \(CompactScoringHUD.formatAccuracy(accuracy))"
                    )

                Text("Accuracy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            HStack(spacing: 32) {
                statItem(
                    value: "\(notesHit)/\(totalNotes)",
                    label: "Notes Hit",
                    accessibilityLabel: "\(notesHit) of \(totalNotes) notes hit"
                )
                statItem(
                    value: "\(streak)",
                    label: "Best Streak",
                    accessibilityLabel: "Best streak of \(streak) notes"
                )
            }
        }
    }

    /// A single stat item with a value and descriptive label.
    private func statItem(
        value: String,
        label: String,
        accessibilityLabel: String
    ) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    /// XP earned badge.
    private var xpSection: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)
            Text("+\(xpEarned) XP")
                .font(.headline)
                .fontWeight(.bold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.yellow.opacity(0.15))
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(xpEarned) experience points earned")
    }

    /// Play Again and Done buttons.
    private var actionsSection: some View {
        HStack(spacing: 16) {
            Button(action: onReplay) {
                Label("Play Again", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Play Again")
            .accessibilityHint("Restart this song from the beginning")

            Button(action: onDone) {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Done")
            .accessibilityHint("Return to the song library")
        }
    }

    /// Confetti-like celebration particles (when Reduce Motion is off).
    @ViewBuilder
    private var celebrationOverlay: some View {
        if showCelebration {
            celebrationParticles
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    /// Animated star particles for celebration effect.
    private var celebrationParticles: some View {
        GeometryReader { geometry in
            ForEach(0..<12, id: \.self) { index in
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(celebrationColor(for: index))
                    .accessibilityHidden(true)
                    .position(
                        x: celebrationX(index: index, width: geometry.size.width),
                        y: celebrationY(index: index, height: geometry.size.height)
                    )
                    .opacity(showCelebration ? 0.0 : 1.0)
                    .animation(
                        .easeOut(duration: 1.5).delay(Double(index) * 0.05),
                        value: showCelebration
                    )
            }
        }
    }

    // MARK: - Private Helpers

    /// Returns a color for a celebration particle at the given index.
    private func celebrationColor(for index: Int) -> Color {
        let colors = themeManager.resolved.celebrationColors
        guard !colors.isEmpty else { return .yellow }
        return colors[index % colors.count]
    }

    /// Horizontal position for a celebration particle.
    private func celebrationX(index: Int, width: CGFloat) -> CGFloat {
        let fraction = CGFloat(index) / 12.0
        return width * (0.1 + fraction * 0.8)
    }

    /// Vertical position for a celebration particle.
    private func celebrationY(index: Int, height: CGFloat) -> CGFloat {
        let offset = CGFloat(index % 3) * 0.1
        return showCelebration ? height * (-0.1 - offset) : height * 0.3
    }
}

// MARK: - Preview

#Preview("Results — 4 Stars") {
    PlayAlongResultsOverlay(
        songTitle: "Raag Yaman — Aaroha",
        accuracy: 0.92,
        notesHit: 46,
        totalNotes: 50,
        streak: 23,
        starRating: 4,
        xpEarned: 120,
        onReplay: {},
        onDone: {}
    )
    .environment(AppThemeManager())
}

#Preview("Results — 1 Star") {
    PlayAlongResultsOverlay(
        songTitle: "Twinkle Twinkle Little Star",
        accuracy: 0.32,
        notesHit: 8,
        totalNotes: 25,
        streak: 3,
        starRating: 1,
        xpEarned: 15,
        onReplay: {},
        onDone: {}
    )
    .environment(AppThemeManager())
}
