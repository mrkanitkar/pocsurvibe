import SVCore
import SwiftUI

/// The main lesson library list view with search, filters, and sort.
///
/// Displays lessons in a scrollable list grouped by difficulty, with a search bar,
/// filter bar, sort menu, and lesson count badge. Locked lessons show grayed-out
/// with a lock icon and a prerequisite alert on tap.
///
/// Receives `LessonLibraryViewModel` via the SwiftUI environment.
struct LessonLibraryView: View {
    // MARK: - Properties

    @Environment(LessonLibraryViewModel.self)
    private var viewModel

    @Environment(AppThemeManager.self)
    private var themeManager

    @Environment(AppRouter.self)
    private var router

    /// Tracks keyboard focus for hardware-keyboard navigation.
    @FocusState
    private var focusedLessonID: Lesson.ID?

    /// The locked lesson that triggered the prerequisite alert.
    @State
    private var lockedLessonAlert: Lesson?

    // MARK: - Body

    var body: some View {
        @Bindable
        var vm = viewModel

        VStack(spacing: 0) {
            // Filter bar
            LessonFilterBar()

            // Content area
            if viewModel.isLoading {
                loadingState
            } else if viewModel.filteredLessons.isEmpty {
                LessonLibraryEmptyState(
                    hasActiveFilters: viewModel.hasActiveFilters
                        || !viewModel.searchText.isEmpty,
                    clearFilters: { viewModel.clearAllFilters() }
                )
            } else {
                lessonList
            }
        }
        .searchable(text: $vm.searchText, prompt: Text("Search lessons..."))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                sortMenu
            }

            ToolbarItem(placement: .topBarTrailing) {
                lessonCountBadge
            }
        }
        .alert(
            "Lesson Locked",
            isPresented: Binding(
                get: { lockedLessonAlert != nil },
                set: { if !$0 { lockedLessonAlert = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            if let lesson = lockedLessonAlert {
                Text(prerequisiteMessage(for: lesson))
            }
        }
        .task {
            await viewModel.loadLessons()
        }
    }

    // MARK: - Subviews

    /// Lesson list grouped by sections.
    private var lessonList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.filteredLessons) { item in
                    if item.completionState == .locked {
                        LessonCardView(item: item)
                            .onTapGesture {
                                lockedLessonAlert = item.lesson
                            }
                            .focused($focusedLessonID, equals: item.lesson.id)
                            .onKeyPress(.return) {
                                lockedLessonAlert = item.lesson
                                return .handled
                            }
                    } else {
                        NavigationLink(value: item.lesson) {
                            LessonCardView(item: item)
                        }
                        .buttonStyle(.plain)
                        .focused($focusedLessonID, equals: item.lesson.id)
                        .onKeyPress(.return) {
                            router.openLesson(item.lesson.id)
                            return .handled
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    /// Loading state with placeholder rows.
    private var loadingState: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(themeManager.resolved.cardBackgroundColor)
                        .frame(height: 80)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    /// Sort menu in the toolbar.
    private var sortMenu: some View {
        Menu {
            ForEach(LessonSortOption.allCases) { option in
                Button {
                    viewModel.updateSort(option)
                } label: {
                    Label(option.label, systemImage: option.icon)
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .accessibilityLabel(Text("Sort lessons"))
                .accessibilityHint(Text("Double tap to choose a sort order"))
        }
    }

    /// Lesson count badge in the toolbar.
    private var lessonCountBadge: some View {
        Text(verbatim: "\(viewModel.filteredLessons.count)")
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(themeManager.resolved.nestedSurfaceColor)
            )
            .accessibilityLabel(Text("\(viewModel.filteredLessons.count) lessons"))
    }

    // MARK: - Private Methods

    /// Builds a message describing which prerequisites are needed.
    ///
    /// - Parameter lesson: The locked lesson.
    /// - Returns: A human-readable description of required prerequisites.
    private func prerequisiteMessage(for lesson: Lesson) -> String {
        guard let prereqs = lesson.decodedPrerequisites, !prereqs.isEmpty else {
            return "This lesson has prerequisites that must be completed first."
        }

        let names = prereqs.map { id in
            // Try to find the lesson title from loaded lessons
            viewModel.allLessons
                .first { $0.lesson.lessonId == id }?
                .lesson.title ?? id
        }

        if names.count == 1 {
            return "Complete \"\(names[0])\" first to unlock this lesson."
        }

        let joined = names.dropLast().joined(separator: ", ")
        return "Complete \(joined) and \(names.last ?? "") first to unlock this lesson."
    }
}
