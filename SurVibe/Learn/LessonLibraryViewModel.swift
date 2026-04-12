import Foundation
import SVCore
import SwiftData
import os.log

/// Completion state for a lesson based on progress and prerequisites.
enum LessonCompletionState: Equatable {
    /// Lesson has not been started.
    case notStarted
    /// Lesson is in progress with a given percentage (0.0–1.0).
    case inProgress(Double)
    /// Lesson is completed.
    case completed
    /// Lesson is locked because prerequisites are not met.
    case locked
}

/// Pairs a `Lesson` with its optional `LessonProgress` and computed state.
struct LessonWithProgress: Identifiable {
    /// The lesson model.
    let lesson: Lesson
    /// The progress record (nil if never accessed).
    let progress: LessonProgress?
    /// The computed completion state.
    let completionState: LessonCompletionState

    var id: UUID { lesson.id }
}

/// View model for the lesson library list view.
///
/// Manages lesson fetching, filtering by difficulty, searching,
/// and sorting. All state changes are observed by `LessonLibraryView`
/// via the `@Observable` macro.
///
/// Requires a `ModelContext` for SwiftData queries.
@MainActor
@Observable
final class LessonLibraryViewModel {
    // MARK: - Properties

    private static let logger = Logger.survibe(category: "LessonLibrary")

    /// All lessons fetched from SwiftData.
    private(set) var allLessons: [LessonWithProgress] = []

    /// Lessons after applying all active filters, search, and sort.
    private(set) var filteredLessons: [LessonWithProgress] = []

    /// Current search text entered by the user.
    var searchText: String = "" {
        didSet {
            scheduleSearchDebounce()
        }
    }

    /// Active difficulty filter (nil = no difficulty filter).
    var activeDifficultyFilter: Int?

    /// Current sort option.
    var sortOption: LessonSortOption = .orderIndex

    /// Whether the initial load is in progress.
    private(set) var isLoading: Bool = false

    /// The model context for SwiftData queries.
    private let modelContext: ModelContext

    /// Task handle for search debounce.
    private var searchDebounceTask: Task<Void, Never>?

    // MARK: - Computed Properties

    /// All unique difficulty levels from the loaded lessons.
    var availableDifficulties: [Int] {
        Array(Set(allLessons.map(\.lesson.difficulty))).sorted()
    }

    /// Whether any filter is currently active.
    var hasActiveFilters: Bool {
        activeDifficultyFilter != nil
    }

    // MARK: - Initialization

    /// Creates the view model with a SwiftData model context.
    ///
    /// - Parameter modelContext: The context used for lesson queries.
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public Methods

    /// Fetches all lessons and progress from SwiftData and applies current filters.
    func loadLessons() async {
        isLoading = true

        do {
            let lessonDescriptor = FetchDescriptor<Lesson>(
                sortBy: [SortDescriptor(\Lesson.orderIndex)]
            )
            let lessons = try modelContext.fetch(lessonDescriptor)

            let progressDescriptor = FetchDescriptor<LessonProgress>()
            let allProgress = try modelContext.fetch(progressDescriptor)
            let progressByLessonId = Dictionary(
                uniqueKeysWithValues: allProgress.map { ($0.lessonId, $0) }
            )

            // Build a set of completed lesson IDs for prerequisite checking
            let completedLessonIds = Set(
                allProgress.filter(\.isCompleted).map(\.lessonId)
            )

            allLessons = lessons.map { lesson in
                let progress = progressByLessonId[lesson.lessonId]
                let state = Self.computeCompletionState(
                    lesson: lesson,
                    progress: progress,
                    completedLessonIds: completedLessonIds
                )
                return LessonWithProgress(
                    lesson: lesson,
                    progress: progress,
                    completionState: state
                )
            }
        } catch {
            Self.logger.error("Failed to load lessons: \(error, privacy: .public)")
            allLessons = []
        }

        applyFilters()
        isLoading = false
    }

    /// Applies all active filters, search text, and sort option.
    func applyFilters() {
        var result = allLessons

        // Difficulty filter
        if let diff = activeDifficultyFilter {
            result = result.filter { $0.lesson.difficulty == diff }
        }

        // Search text
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            result = result.filter { item in
                item.lesson.title.localizedCaseInsensitiveContains(trimmed)
                    || item.lesson.lessonDescription.localizedCaseInsensitiveContains(trimmed)
            }
        }

        // Sort
        filteredLessons = sortOption.sorted(result)
    }

    /// Toggles the difficulty filter on/off.
    ///
    /// - Parameter difficulty: The difficulty level to toggle.
    func toggleDifficultyFilter(_ difficulty: Int) {
        if activeDifficultyFilter == difficulty {
            activeDifficultyFilter = nil
        } else {
            activeDifficultyFilter = difficulty
        }
        applyFilters()
    }

    /// Clears all active filters and reapplies sort.
    func clearAllFilters() {
        activeDifficultyFilter = nil
        searchText = ""
        applyFilters()
    }

    /// Updates the sort option and reapplies filters.
    ///
    /// - Parameter option: The new sort option.
    func updateSort(_ option: LessonSortOption) {
        sortOption = option
        applyFilters()
    }

    // MARK: - Private Methods

    /// Computes the completion state for a lesson.
    ///
    /// - Parameters:
    ///   - lesson: The lesson to evaluate.
    ///   - progress: The progress record, if any.
    ///   - completedLessonIds: Set of all completed lesson IDs.
    /// - Returns: The computed `LessonCompletionState`.
    private static func computeCompletionState(
        lesson: Lesson,
        progress: LessonProgress?,
        completedLessonIds: Set<String>
    ) -> LessonCompletionState {
        // Check prerequisites
        if let prereqs = lesson.decodedPrerequisites, !prereqs.isEmpty {
            let allMet = prereqs.allSatisfy { completedLessonIds.contains($0) }
            if !allMet {
                return .locked
            }
        }

        // Check progress
        guard let progress else {
            return .notStarted
        }

        if progress.isCompleted {
            return .completed
        }

        if progress.progressPercent > 0 {
            return .inProgress(progress.progressPercent)
        }

        return .notStarted
    }

    /// Debounces search text changes by 300ms.
    private func scheduleSearchDebounce() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            applyFilters()
        }
    }
}
