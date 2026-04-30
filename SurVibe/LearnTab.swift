import SVCore
import SwiftData
import SwiftUI

/// Learn tab — browse curricula and study lessons.
///
/// Single-column `NavigationStack` on all sizes. Was previously a
/// `NavigationSplitView` with sidebar — removed to match the rest of
/// the app (user does not want sidebar on iPad) and to avoid the
/// detail-column reflow that broke Play Along on Songs tab.
struct LearnTab: View {
    // MARK: - Properties

    @Environment(\.modelContext)
    private var modelContext
    @Environment(AppThemeManager.self)
    private var themeManager
    @Environment(AppRouter.self)
    private var router

    @State
    private var progressManager: LessonProgressManager?
    @State
    private var viewModel: LessonLibraryViewModel?

    // MARK: - Body

    var body: some View {
        @Bindable
        var router = router

        NavigationStack(path: router.pathForTab(.learn)) {
            Group {
                if let progressManager {
                    CurriculumBrowserView()
                        .environment(progressManager)
                        .navigationTitle("Learn")
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationDestination(for: AppDestination.self) { destination in
                switch destination {
                case .lessonDetail(let lesson):
                    LessonDetailView(lesson: lesson)
                default:
                    EmptyView()
                }
            }
            .navigationDestination(for: Curriculum.self) { curriculum in
                if let progressManager {
                    CurriculumDetailView(curriculum: curriculum)
                        .environment(progressManager)
                }
            }
            .navigationDestination(for: Lesson.self) { lesson in
                LessonDetailView(lesson: lesson)
            }
        }
        .background(
            LinearGradient(
                colors: themeManager.resolved.backgroundGradient,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .accessibilityLabel(AccessibilityHelper.tabLabel(for: "Learn"))
        .onAppear {
            if progressManager == nil {
                progressManager = LessonProgressManager(modelContext: modelContext)
            }
            if viewModel == nil {
                viewModel = LessonLibraryViewModel(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Lesson Detail Resolver

/// Fetches a `Lesson` by ID from SwiftData and hands off to `LessonDetailView`.
///
/// Avoids requiring every NavigationSplitView call-site to hold a full
/// `Lesson` object. Falls back to `ContentUnavailableView` if the lesson
/// has been deleted between selection and render.
private struct LessonDetailViewResolver: View {
    // MARK: - Properties

    let lessonID: Lesson.ID

    @Query
    private var lessons: [Lesson]

    // MARK: - Initialization

    /// Creates a resolver filtered to the given lesson ID.
    ///
    /// - Parameter lessonID: The `UUID` of the lesson to display.
    init(lessonID: Lesson.ID) {
        self.lessonID = lessonID
        _lessons = Query(filter: #Predicate<Lesson> { $0.id == lessonID })
    }

    // MARK: - Body

    var body: some View {
        if let lesson = lessons.first {
            LessonDetailView(lesson: lesson)
        } else {
            ContentUnavailableView(
                "Lesson Not Found",
                systemImage: "book.closed",
                description: Text("The selected lesson is no longer available.")
            )
        }
    }
}

// MARK: - Preview

#Preview {
    LearnTab()
        .modelContainer(for: [Lesson.self, Curriculum.self, LessonProgress.self], inMemory: true)
        .environment(AppThemeManager())
        .environment(AppRouter())
}
