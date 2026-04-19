import SVCore
import SwiftData
import SwiftUI

/// Learn tab — browse curricula and study lessons.
///
/// On iPad and Mac Catalyst (regular horizontal size class), renders a
/// `NavigationSplitView` with `LessonLibrarySidebar` in the sidebar column
/// showing all lessons in curriculum order, and `LessonDetailView` in the
/// detail column. On iPhone (compact), the sidebar collapses and behaves
/// like a `NavigationStack`.
///
/// Navigation flows:
/// - Sidebar selection: lesson ID → `LessonDetailView`
/// - Detail column stack: curricula → `CurriculumDetailView` → `LessonDetailView`
///
/// Injects `LessonProgressManager` and `LessonLibraryViewModel` into the
/// environment for all child views.
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

        NavigationSplitView {
            Group {
                if let progressManager {
                    LessonLibrarySidebar(selection: $router.selectedLessonID)
                        .environment(progressManager)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 420)
        } detail: {
            NavigationStack(path: router.pathForTab(.learn)) {
                detailContent(for: router.selectedLessonID)
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

    // MARK: - Private Methods

    /// Resolves the detail column content for the currently selected lesson ID.
    ///
    /// Shows `LessonDetailView` when a lesson is selected, or the
    /// `CurriculumBrowserView` as the default root when nothing is selected.
    ///
    /// - Parameter lessonID: The optional selected `Lesson.ID`.
    @ViewBuilder
    private func detailContent(for lessonID: Lesson.ID?) -> some View {
        if let lessonID {
            LessonDetailViewResolver(lessonID: lessonID)
        } else {
            if let progressManager {
                CurriculumBrowserView()
                    .environment(progressManager)
                    .navigationTitle("Learn")
            } else {
                ProgressView()
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
