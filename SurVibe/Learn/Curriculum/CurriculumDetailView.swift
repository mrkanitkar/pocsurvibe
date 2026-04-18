import SwiftData
import SwiftUI

/// Displays curriculum details with an ordered list of lessons.
///
/// Shows:
/// - Curriculum header with description and progress bar
/// - Completion banner when all lessons are done
/// - Ordered list of lessons via `LessonRowView`
/// - Locked lesson handling with prerequisite alert
/// - Navigation to `LessonDetailView` for unlocked lessons
struct CurriculumDetailView: View {
    // MARK: - Properties

    /// The curriculum to display.
    let curriculum: Curriculum

    @Query(sort: \Lesson.orderIndex)
    private var allLessons: [Lesson]

    @Environment(AppThemeManager.self)
    private var themeManager

    @Environment(LessonProgressManager.self)
    private var progressManager

    /// The locked lesson that triggered the prerequisite alert.
    @State private var lockedLessonAlert: Lesson?

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Header
                headerSection

                // Completion banner
                if progressManager.isCurriculumCompleted(curriculum: curriculum) {
                    completionBanner
                }

                // Lessons list
                ForEach(
                    Array(orderedLessons.enumerated()),
                    id: \.element.id
                ) { index, lesson in
                    let isUnlocked = progressManager.isLessonUnlocked(
                        lesson: lesson
                    )
                    let lessonProgress = progressManager.progress(
                        for: lesson.lessonId
                    )

                    if isUnlocked {
                        NavigationLink(value: lesson) {
                            LessonRowView(
                                lesson: lesson,
                                index: index + 1,
                                isCompleted: lessonProgress.isCompleted,
                                isLocked: false,
                                stepCount: lesson.decodedSteps?.count,
                                estimatedDuration: estimatedDuration(
                                    for: lesson
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            lockedLessonAlert = lesson
                        } label: {
                            LessonRowView(
                                lesson: lesson,
                                index: index + 1,
                                isCompleted: false,
                                isLocked: true,
                                stepCount: lesson.decodedSteps?.count,
                                estimatedDuration: estimatedDuration(
                                    for: lesson
                                )
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    if index < orderedLessons.count - 1 {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
        }
        .navigationTitle(curriculum.title)
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(for: Lesson.self) { lesson in
            LessonDetailView(lesson: lesson)
        }
        .alert(
            "Lesson Locked",
            isPresented: Binding(
                get: { lockedLessonAlert != nil },
                set: { if !$0 { lockedLessonAlert = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                lockedLessonAlert = nil
            }
        } message: {
            if let lesson = lockedLessonAlert {
                Text(prerequisiteMessage(for: lesson))
            }
        }
    }

    // MARK: - Subviews

    /// Header section with description and progress bar.
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !curriculum.curriculumDescription.isEmpty {
                Text(verbatim: curriculum.curriculumDescription)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            let prog = progressManager.curriculumProgress(
                curriculum: curriculum
            )
            let completed = progressManager.completedLessonCount(
                curriculum: curriculum
            )

            HStack {
                ProgressView(value: prog)
                    .tint(prog >= 1.0 ? .green : .accentColor)

                Text("\(completed)/\(orderedLessons.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                Text(
                    "\(completed) of \(orderedLessons.count) lessons completed"
                )
            )
        }
        .padding()
    }

    /// Banner shown when all lessons in the curriculum are completed.
    private var completionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .foregroundStyle(.yellow)
                .font(.title2)
                .accessibilityHidden(true)

            VStack(alignment: .leading) {
                Text("Curriculum Complete!")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(verbatim: curriculum.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(themeManager.resolved.successColor.opacity(0.1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text("Curriculum complete: \(curriculum.title)")
        )
    }

    // MARK: - Helpers

    /// Resolves ordered lessons from the curriculum's lesson IDs.
    private var orderedLessons: [Lesson] {
        guard let lessonIds = curriculum.decodedLessonIds else { return [] }
        let lessonMap = Dictionary(
            uniqueKeysWithValues: allLessons.map { ($0.lessonId, $0) }
        )
        return lessonIds.compactMap { lessonMap[$0] }
    }

    /// Calculates estimated duration for a lesson from its steps.
    ///
    /// - Parameter lesson: The lesson to estimate duration for.
    /// - Returns: A human-readable duration string, or `nil` if no step durations exist.
    private func estimatedDuration(for lesson: Lesson) -> String? {
        guard let steps = lesson.decodedSteps else { return nil }
        let totalSeconds = steps.compactMap(\.durationSeconds).reduce(0, +)
        guard totalSeconds > 0 else { return nil }
        let minutes = totalSeconds / 60
        return minutes > 0 ? "~\(minutes) min" : "~\(totalSeconds)s"
    }

    /// Builds a human-readable prerequisite message for a locked lesson.
    ///
    /// - Parameter lesson: The locked lesson whose prerequisites to describe.
    /// - Returns: A message naming the prerequisite lessons.
    private func prerequisiteMessage(for lesson: Lesson) -> String {
        guard let prereqs = lesson.decodedPrerequisites, !prereqs.isEmpty else {
            return "This lesson has prerequisites that must be completed first."
        }

        let prereqLessonMap = Dictionary(
            uniqueKeysWithValues: allLessons.map { ($0.lessonId, $0) }
        )

        let names = prereqs.compactMap { prereqLessonMap[$0]?.title }

        if names.isEmpty {
            return "Complete the prerequisite lessons to unlock this one."
        }
        return "Complete \(names.joined(separator: " and ")) first."
    }
}
