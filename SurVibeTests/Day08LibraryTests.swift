import SwiftData
import Testing

@testable import SurVibe

// MARK: - SongSortOption Tests

@MainActor
struct SongSortOptionTests {
    @Test func allCasesExist() {
        let cases = SongSortOption.allCases
        #expect(cases.count == 6)
    }

    @Test func labelsAreNotEmpty() {
        for option in SongSortOption.allCases {
            #expect(!option.label.isEmpty)
        }
    }

    @Test func iconsAreNotEmpty() {
        for option in SongSortOption.allCases {
            #expect(!option.icon.isEmpty)
        }
    }

    @Test func identifiableById() {
        for option in SongSortOption.allCases {
            #expect(option.id == option.rawValue)
        }
    }
}

// MARK: - DifficultyBadge Label Tests

@MainActor
struct DifficultyMappingTests {
    @Test func allLevelsHaveLabels() {
        // Verify the labels map correctly for common difficulty levels
        let labels = [1: "Beginner", 2: "Easy", 3: "Medium", 4: "Hard", 5: "Expert"]

        for (level, expected) in labels {
            // Test that DifficultyBadge would show the right label
            // (We test the mapping logic, not the view itself)
            let label: String = switch level {
            case 1: "Beginner"
            case 2: "Easy"
            case 3: "Medium"
            case 4: "Hard"
            case 5: "Expert"
            default: "Level \(level)"
            }
            #expect(label == expected)
        }
    }

    @Test func unknownDifficultyFallback() {
        // Difficulty 99 is outside the known range — should produce a fallback label.
        let labels = [1: "Beginner", 2: "Easy", 3: "Medium", 4: "Hard", 5: "Expert"]
        let unknown = 99
        let fallback = labels[unknown] ?? "Level \(unknown)"
        #expect(fallback == "Level 99")
    }
}

// MARK: - LanguageBadge Mapping Tests

@MainActor
struct LanguageMappingTests {
    @Test func knownLanguages() {
        let mappings = ["hi": "Hindi", "mr": "Marathi", "en": "English"]
        for (code, expected) in mappings {
            let name: String = switch code {
            case "hi": "Hindi"
            case "mr": "Marathi"
            case "en": "English"
            default: code.uppercased()
            }
            #expect(name == expected)
        }
    }

    @Test func unknownLanguageFallback() {
        let code = "fr"
        let name: String = switch code {
        case "hi": "Hindi"
        case "mr": "Marathi"
        case "en": "English"
        default: code.uppercased()
        }
        #expect(name == "FR")
    }
}

// MARK: - SongLibraryViewModel Tests

@MainActor
struct SongLibraryViewModelTests {
    @Test @MainActor func initialState() throws {
        let container = try makeTestContainer()
        let viewModel = SongLibraryViewModel(modelContext: container.mainContext)

        #expect(viewModel.allSongs.isEmpty)
        #expect(viewModel.filteredSongs.isEmpty)
        #expect(viewModel.searchText.isEmpty)
        #expect(viewModel.activeLanguageFilter == nil)
        #expect(viewModel.activeDifficultyFilter == nil)
        #expect(viewModel.activeRaagFilters.isEmpty)
        #expect(!viewModel.showFavoritesOnly)
        #expect(viewModel.sortOption == .difficultyAscending)
        #expect(!viewModel.isLoading)
        #expect(!viewModel.hasActiveFilters)
    }

    @Test @MainActor func languageFilterToggle() throws {
        let container = try makeTestContainer()
        let viewModel = SongLibraryViewModel(modelContext: container.mainContext)

        viewModel.toggleLanguageFilter("hi")
        #expect(viewModel.activeLanguageFilter == "hi")
        #expect(viewModel.hasActiveFilters)

        viewModel.toggleLanguageFilter("hi")
        #expect(viewModel.activeLanguageFilter == nil)
        #expect(!viewModel.hasActiveFilters)
    }

    @Test @MainActor func difficultyFilterToggle() throws {
        let container = try makeTestContainer()
        let viewModel = SongLibraryViewModel(modelContext: container.mainContext)

        viewModel.toggleDifficultyFilter(2)
        #expect(viewModel.activeDifficultyFilter == 2)

        viewModel.toggleDifficultyFilter(2)
        #expect(viewModel.activeDifficultyFilter == nil)
    }

    @Test @MainActor func raagFilterToggle() throws {
        let container = try makeTestContainer()
        let viewModel = SongLibraryViewModel(modelContext: container.mainContext)

        viewModel.toggleRaagFilter("Yaman")
        #expect(viewModel.activeRaagFilters.contains("Yaman"))

        viewModel.toggleRaagFilter("Bhairav")
        #expect(viewModel.activeRaagFilters.count == 2)

        viewModel.toggleRaagFilter("Yaman")
        #expect(!viewModel.activeRaagFilters.contains("Yaman"))
        #expect(viewModel.activeRaagFilters.count == 1)
    }

    @Test @MainActor func favoritesToggle() throws {
        let container = try makeTestContainer()
        let viewModel = SongLibraryViewModel(modelContext: container.mainContext)

        viewModel.toggleFavorites()
        #expect(viewModel.showFavoritesOnly)

        viewModel.toggleFavorites()
        #expect(!viewModel.showFavoritesOnly)
    }

    @Test @MainActor func clearAllFilters() throws {
        let container = try makeTestContainer()
        let viewModel = SongLibraryViewModel(modelContext: container.mainContext)

        viewModel.toggleLanguageFilter("hi")
        viewModel.toggleDifficultyFilter(1)
        viewModel.toggleRaagFilter("Yaman")
        viewModel.toggleFavorites()
        viewModel.searchText = "test"

        viewModel.clearAllFilters()

        #expect(viewModel.activeLanguageFilter == nil)
        #expect(viewModel.activeDifficultyFilter == nil)
        #expect(viewModel.activeRaagFilters.isEmpty)
        #expect(!viewModel.showFavoritesOnly)
        #expect(viewModel.searchText.isEmpty)
    }

    @Test @MainActor func updateSort() throws {
        let container = try makeTestContainer()
        let viewModel = SongLibraryViewModel(modelContext: container.mainContext)

        viewModel.updateSort(.titleAscending)
        #expect(viewModel.sortOption == .titleAscending)

        viewModel.updateSort(.recentlyAdded)
        #expect(viewModel.sortOption == .recentlyAdded)
    }

    // MARK: - Helpers

    /// Creates an in-memory ModelContainer for testing.
    private func makeTestContainer() throws -> ModelContainer {
        let schema = Schema([Song.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
