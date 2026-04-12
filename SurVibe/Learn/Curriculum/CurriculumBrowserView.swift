import SwiftData
import SwiftUI

/// Displays all available curricula as a browsable list.
///
/// Queries curricula from SwiftData sorted by minimum difficulty level.
/// Each curriculum is shown as a `CurriculumCardView` with progress tracking.
/// Tapping a curriculum navigates to `CurriculumDetailView`.
///
/// If no curricula exist, shows an empty state encouraging the user to check back.
struct CurriculumBrowserView: View {
    // MARK: - Properties

    @Query(sort: \Curriculum.minDifficulty)
    private var curricula: [Curriculum]

    @Query(sort: \Lesson.orderIndex)
    private var allLessons: [Lesson]

    @Environment(LessonProgressManager.self)
    private var progressManager

    // MARK: - Body

    var body: some View {
        Group {
            if curricula.isEmpty {
                emptyState
            } else {
                curriculumList
            }
        }
    }

    // MARK: - Subviews

    /// Scrollable list of curriculum cards.
    private var curriculumList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(curricula) { curriculum in
                    NavigationLink(value: curriculum) {
                        CurriculumCardView(
                            curriculum: curriculum,
                            lessons: lessonsForCurriculum(curriculum),
                            progress: progressManager.curriculumProgress(
                                curriculum: curriculum
                            ),
                            completedCount: progressManager.completedLessonCount(
                                curriculum: curriculum
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(
                        Text("Double tap to view curriculum details")
                    )
                }
            }
            .padding()
        }
    }

    /// Empty state shown when no curricula are available.
    private var emptyState: some View {
        ContentUnavailableView(
            "No Curricula Available",
            systemImage: "book.closed",
            description: Text(
                "Structured learning paths will appear here. Check back soon!"
            )
        )
    }

    // MARK: - Helpers

    /// Resolves ordered lessons for a given curriculum from the full lesson list.
    ///
    /// Preserves the order defined by `curriculum.decodedLessonIds`.
    ///
    /// - Parameter curriculum: The curriculum whose lessons to resolve.
    /// - Returns: An ordered array of `Lesson` instances matching the curriculum's lesson IDs.
    private func lessonsForCurriculum(_ curriculum: Curriculum) -> [Lesson] {
        guard let lessonIds = curriculum.decodedLessonIds else { return [] }
        let lessonMap = Dictionary(
            allLessons.map { ($0.lessonId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return lessonIds.compactMap { lessonMap[$0] }
    }
}
