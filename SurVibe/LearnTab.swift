import SVCore
import SwiftData
import SwiftUI

/// Learn tab — browse curricula and study lessons.
///
/// The tab displays `CurriculumBrowserView` as the default content,
/// allowing learners to browse structured learning paths. Navigation
/// flows from curricula → curriculum detail → lesson detail → lesson player.
///
/// Creates and injects `LessonProgressManager` and `LessonLibraryViewModel`
/// into the environment for all child views.
struct LearnTab: View {
    // MARK: - Properties

    @Environment(\.modelContext)
    private var modelContext

    /// App-wide theme manager for background gradients and accent colors.
    @Environment(AppThemeManager.self) private var themeManager

    @State private var progressManager: LessonProgressManager?
    @State private var viewModel: LessonLibraryViewModel?

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if let progressManager {
                    CurriculumBrowserView()
                        .environment(progressManager)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Learn")
            .background(
                LinearGradient(
                    colors: themeManager.resolved.backgroundGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
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

// MARK: - Preview

#Preview {
    LearnTab()
        .modelContainer(for: [Lesson.self, Curriculum.self, LessonProgress.self], inMemory: true)
        .environment(AppThemeManager())
}
