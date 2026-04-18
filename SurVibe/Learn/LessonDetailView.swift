import SVCore
import SwiftData
import SwiftUI

/// Detail view for a single lesson showing metadata, step overview, and start button.
///
/// Shows the lesson title, description, difficulty, step count, estimated duration,
/// prerequisite status, a step list preview, and a "Start Lesson" button that
/// presents `LessonStepView` as a full-screen cover.
struct LessonDetailView: View {
    // MARK: - Properties

    /// The lesson to display.
    let lesson: Lesson

    @Environment(AppThemeManager.self)
    private var themeManager

    @Environment(\.modelContext)
    private var modelContext

    /// Whether the step view is presented.
    @State
    private var isStepViewPresented = false

    /// The progress record for this lesson (fetched on appear).
    @State
    private var progress: LessonProgress?

    /// Progress manager for lesson step tracking and completion.
    @State
    private var progressManager: LessonProgressManager?

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                headerSection

                Divider()

                // Description
                if !lesson.lessonDescription.isEmpty {
                    descriptionSection
                }

                // Steps overview
                if let steps = lesson.decodedSteps, !steps.isEmpty {
                    stepsSection(steps: steps)
                }

                // Associated songs
                if let slugs = lesson.decodedAssociatedSongSlugs, !slugs.isEmpty {
                    associatedSongsSection(slugs: slugs)
                }

                Spacer(minLength: 40)
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            startButton
                .padding()
                .background(.ultraThinMaterial)
        }
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.large)
        .fullScreenCover(isPresented: $isStepViewPresented) {
            if let manager = progressManager {
                LessonStepView(
                    lesson: lesson,
                    progressManager: manager,
                    onComplete: {
                        fetchProgress()
                    }
                )
            }
        }
        .task {
            progressManager = LessonProgressManager(modelContext: modelContext)
            fetchProgress()
        }
    }

    // MARK: - Subviews

    /// Header with title, badges, and progress indicator.
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                DifficultyBadge(difficulty: lesson.difficulty)

                if let steps = lesson.decodedSteps {
                    Label("\(steps.count) steps", systemImage: "list.bullet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let duration = estimatedDuration {
                    Label(duration, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Completion status
            if let progress {
                HStack(spacing: 6) {
                    if progress.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(themeManager.resolved.successColor)
                        Text("Completed")
                            .foregroundStyle(themeManager.resolved.successColor)
                    } else if progress.progressPercent > 0 {
                        Image(systemName: "chart.bar.fill")
                            .foregroundStyle(Color.accentColor)
                        Text("\(Int(progress.progressPercent * 100))% complete")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .font(.subheadline)
                .fontWeight(.medium)
            }

            // Free badge
            if lesson.isFree {
                Label("Free", systemImage: "gift")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(themeManager.resolved.badgeTextColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(themeManager.resolved.successColor)
                    )
            }
        }
    }

    /// Lesson description section.
    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("About This Lesson")
                .font(.headline)

            Text(verbatim: lesson.lessonDescription)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    /// Steps overview with numbered list.
    private func stepsSection(steps: [LessonStep]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Steps")
                .font(.headline)

            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    // Step number circle
                    Text(verbatim: "\(index + 1)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(themeManager.resolved.badgeTextColor)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(StepTypeColorSystem.color(forStepType: step.stepType)))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stepTypeLabel(step.stepType))
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Text(verbatim: step.content)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    Text("Step \(index + 1): \(stepTypeLabel(step.stepType))")
                )
            }
        }
    }

    /// Associated songs section.
    private func associatedSongsSection(slugs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Related Songs")
                .font(.headline)

            ForEach(slugs, id: \.self) { slug in
                Label(slug, systemImage: "music.note")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Start/Continue button at the bottom.
    private var startButton: some View {
        Button {
            isStepViewPresented = true
        } label: {
            Text(buttonLabel)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(themeManager.resolved.badgeTextColor)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.accentColor)
                )
        }
        .accessibilityLabel(Text(buttonLabel))
        .accessibilityHint(Text("Double tap to start the lesson"))
    }

    // MARK: - Computed Properties

    /// Human-readable estimated duration.
    private var estimatedDuration: String? {
        guard let steps = lesson.decodedSteps else { return nil }
        let totalSeconds = steps.compactMap(\.durationSeconds).reduce(0, +)
        guard totalSeconds > 0 else { return nil }
        let minutes = max(1, totalSeconds / 60)
        return "\(minutes) min"
    }

    /// Label for the start button based on progress.
    private var buttonLabel: String {
        if let progress {
            if progress.isCompleted {
                return "Review Lesson"
            } else if progress.progressPercent > 0 {
                return "Continue Lesson"
            }
        }
        return "Start Lesson"
    }

    // MARK: - Private Methods

    /// Fetches the progress record for this lesson.
    private func fetchProgress() {
        let lessonId = lesson.lessonId
        let descriptor = FetchDescriptor<LessonProgress>(
            predicate: #Predicate { $0.lessonId == lessonId }
        )
        progress = try? modelContext.fetch(descriptor).first
    }

    /// Marks the lesson as completed, creating a progress record if needed.
    private func markLessonCompleted() {
        if let existingProgress = progress {
            existingProgress.markCompleted()
        } else {
            let newProgress = LessonProgress(
                lessonId: lesson.lessonId,
                lessonTitle: lesson.title
            )
            newProgress.markCompleted()
            modelContext.insert(newProgress)
            progress = newProgress
        }
    }

    /// Human-readable label for a step type.
    ///
    /// - Parameter type: The step type string.
    /// - Returns: A display label.
    private func stepTypeLabel(_ type: String) -> String {
        switch type {
        case "intro": "Introduction"
        case "listen": "Listen"
        case "read": "Read"
        case "exercise": "Exercise"
        case "practice": "Practice"
        case "quiz": "Quiz"
        case "sing": "Sing Along"
        default: type.capitalized
        }
    }


}
