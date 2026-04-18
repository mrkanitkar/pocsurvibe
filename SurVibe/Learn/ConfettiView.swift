import SwiftUI

/// A confetti animation that respects accessibility reduce-motion preferences.
///
/// When `accessibilityReduceMotion` is `true`, displays a static checkmark
/// instead of animated falling confetti particles. When motion is allowed,
/// generates 30 colored circular particles that fall from the top of the
/// view with rotation and fade-out over 2 seconds.
///
/// ## Usage
/// ```swift
/// ConfettiView(
///     isActive: $showConfetti,
///     celebrationColors: themeManager.resolved.celebrationColors,
///     successColor: themeManager.resolved.successColor
/// )
/// ```
struct ConfettiView: View {
    // MARK: - Properties

    /// Whether the confetti animation is active.
    @Binding var isActive: Bool

    /// Particle colors sourced from the active theme's `celebrationColors`.
    /// Pass `themeManager.resolved.celebrationColors` from the parent view.
    let celebrationColors: [Color]

    /// Success color for the reduce-motion static fallback (the checkmark seal).
    /// Pass `themeManager.resolved.successColor` from the parent view.
    let successColor: Color

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State private var particles: [ConfettiParticle] = []

    // MARK: - Body

    var body: some View {
        if reduceMotion {
            // Static fallback for reduce motion
            if isActive {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(successColor)
                    .accessibilityLabel(Text("Celebration"))
            }
        } else {
            GeometryReader { geometry in
                ZStack {
                    ForEach(particles) { particle in
                        Circle()
                            .fill(particle.color)
                            .frame(width: particle.size, height: particle.size)
                            .position(x: particle.x, y: particle.y)
                            .opacity(particle.opacity)
                            .rotationEffect(.degrees(particle.rotation))
                    }
                }
                .onChange(of: isActive) { _, newValue in
                    if newValue {
                        generateParticles(in: geometry.size)
                        animateParticles(in: geometry.size)
                    }
                }
                .onAppear {
                    if isActive {
                        generateParticles(in: geometry.size)
                        animateParticles(in: geometry.size)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Private Methods

    /// Generates confetti particles at the top of the view.
    ///
    /// Creates 30 particles with random horizontal positions, colors,
    /// sizes, and rotation angles. Particles start above the visible
    /// area (y between -50 and 0).
    ///
    /// - Parameter size: The available size of the parent container.
    private func generateParticles(in size: CGSize) {
        // Theme-driven palette. If the theme provides no celebration colors
        // (shouldn't happen post-Phase-1 but guard defensively), fall back
        // to a rainbow palette so the celebration still reads visually.
        let colors: [Color] = celebrationColors.isEmpty
            ? [.red, .blue, .green, .yellow, .orange, .purple, .pink]
            : celebrationColors
        particles = (0..<30).map { index in
            ConfettiParticle(
                id: index,
                x: Double.random(in: 0...size.width),
                y: Double.random(in: -50...0),
                color: colors[index % colors.count],
                size: Double.random(in: 6...12),
                rotation: Double.random(in: 0...360),
                opacity: 1.0
            )
        }
    }

    /// Animates particles falling down with an ease-in animation.
    ///
    /// Moves each particle below the visible area, adds random rotation,
    /// and fades opacity to zero over 2 seconds. After 2.5 seconds the
    /// particle array is cleared to free resources.
    ///
    /// - Parameter size: The available size of the parent container.
    private func animateParticles(in size: CGSize) {
        withAnimation(.easeIn(duration: 2.0)) {
            for index in particles.indices {
                particles[index].y = size.height + 50
                particles[index].rotation += Double.random(in: 180...720)
                particles[index].opacity = 0.0
            }
        }

        // Clean up after animation
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            particles = []
        }
    }
}

// MARK: - ConfettiParticle

/// A single confetti particle with position, color, size, rotation, and opacity.
///
/// Used internally by `ConfettiView` to represent each falling piece of confetti.
/// Properties are mutable to allow SwiftUI animation of position and opacity changes.
struct ConfettiParticle: Identifiable {
    /// Unique identifier for the particle.
    let id: Int

    /// Horizontal position in the parent coordinate space.
    var x: Double

    /// Vertical position in the parent coordinate space.
    var y: Double

    /// Fill color of the particle circle.
    let color: Color

    /// Diameter of the particle circle.
    let size: Double

    /// Rotation angle in degrees.
    var rotation: Double

    /// Opacity from 0.0 (transparent) to 1.0 (opaque).
    var opacity: Double
}
