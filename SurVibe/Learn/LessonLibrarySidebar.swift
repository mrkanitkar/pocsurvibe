import SVCore
import SwiftData
import SwiftUI

/// Sidebar variant of the lesson library used inside `NavigationSplitView`.
///
/// Renders a `List` bound to the parent's `selection` binding so the
/// detail column updates when the user picks a lesson. Uses `@Query`
/// sorted by `orderIndex` — matching the curriculum's intended study order.
/// The full search/filter/progress-aware experience remains available in
/// `LessonLibraryView` on compact layouts.
struct LessonLibrarySidebar: View {
    // MARK: - Properties

    /// The currently selected lesson ID, driving the split-view detail column.
    @Binding var selection: Lesson.ID?

    @Query(sort: \Lesson.orderIndex) private var lessons: [Lesson]

    @Environment(AppThemeManager.self) private var themeManager

    // MARK: - Body

    var body: some View {
        List(lessons, selection: $selection) { lesson in
            LessonSidebarRow(lesson: lesson)
                .tag(lesson.id)
        }
        .navigationTitle("Learn")
        .accessibilityLabel(Text("Learn sidebar"))
    }
}

// MARK: - Private Subview

/// Compact row for a lesson in the sidebar list.
///
/// Displays the lesson title and difficulty indicator in a single
/// accessibility element for efficient VoiceOver navigation.
private struct LessonSidebarRow: View {
    // MARK: - Properties

    let lesson: Lesson

    @Environment(AppThemeManager.self) private var themeManager

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: lesson.title)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text(verbatim: lesson.lessonDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            difficultyIndicator
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(lesson.title), difficulty \(lesson.difficulty) of 5"
        )
    }

    // MARK: - Private Views

    /// Row of filled and unfilled circles representing lesson difficulty (1–5).
    private var difficultyIndicator: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { level in
                Circle()
                    .fill(
                        level <= lesson.difficulty
                            ? (RangLevel(rawValue: lesson.difficulty)?.bodyTextColor ?? .gray)
                            : themeManager.resolved.dividerColor
                    )
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview {
    NavigationSplitView {
        LessonLibrarySidebar(selection: .constant(nil))
            .environment(AppThemeManager())
    } detail: {
        Text("Select a lesson")
    }
    .modelContainer(for: Lesson.self, inMemory: true)
}
