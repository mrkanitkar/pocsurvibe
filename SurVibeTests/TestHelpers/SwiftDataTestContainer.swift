import Foundation
import SwiftData
import Testing

@testable import SurVibe

/// Shared SwiftData ModelContainer for tests.
///
/// ## Why this exists
/// The SurVibe app schema includes `UserProfile`, which uses
/// `@Attribute(.externalStorage)` for the profile image blob. Combined with
/// `ModelConfiguration(isStoredInMemoryOnly: true)`, repeated container
/// creation across tests in a single process trips an EXC_BREAKPOINT inside
/// SwiftData (CoreData+CloudKit setup races on `file:///dev/null` and the
/// recovery path eventually traps a precondition). The crash kills the test
/// host mid-run and produces ~800 cascading "Test crashed with signal trap"
/// failures in xcresult.
///
/// ## What it does
/// - Hands out **one** on-disk `ModelContainer` per test process.
/// - Disables CloudKit (`cloudKitDatabase: .none`) so the recovery path
///   never engages on the simulator's no-iCloud-account environment.
/// - Provides a `freshContext()` helper so each test starts from an empty
///   store without paying the cost of creating a new container.
enum SwiftDataTestContainer {
    /// All `@Model` types the app target ships. Tests that need only a
    /// subset still get the full schema — there is no cost to including
    /// unused types in an empty store.
    ///
    /// Must stay in sync with `SurVibeApp.appSchema` — all 13 models.
    static let schema = Schema([
        UserProfile.self,
        RiyazEntry.self,
        Achievement.self,
        SongProgress.self,
        LessonProgress.self,
        SubscriptionState.self,
        Song.self,
        Lesson.self,
        Curriculum.self,
        XPEntry.self,
        NoteScoreEntry.self,
        MIDIEventEntry.self,
        PitchLogEntry.self,
    ])

    /// Process-global container — created once on first access.
    /// A failure here aborts the entire test process, which is the
    /// desired behaviour: every SwiftData test depends on this container.
    static let shared: ModelContainer = {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SurVibeTests-\(UUID().uuidString).store")
        let config = ModelConfiguration(url: url, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("SwiftDataTestContainer setup failed: \(error)")
        }
    }()

    /// Returns a brand-new `ModelContext` on the shared container with
    /// every row from every model type deleted. Use this in test setup
    /// instead of allocating a fresh container.
    ///
    /// When adding a model, also add a `context.delete(model:)` line below —
    /// the model-count assertion in `SwiftDataSchemaSyncTests` is the reminder.
    @MainActor
    static func freshContext() throws -> ModelContext {
        let context = ModelContext(shared)
        try context.delete(model: XPEntry.self)
        try context.delete(model: Achievement.self)
        try context.delete(model: RiyazEntry.self)
        try context.delete(model: SongProgress.self)
        try context.delete(model: LessonProgress.self)
        try context.delete(model: SubscriptionState.self)
        try context.delete(model: Song.self)
        try context.delete(model: Lesson.self)
        try context.delete(model: Curriculum.self)
        try context.delete(model: UserProfile.self)
        try context.delete(model: NoteScoreEntry.self)
        try context.delete(model: MIDIEventEntry.self)
        try context.delete(model: PitchLogEntry.self)
        try context.save()
        return context
    }
}

/// Guards against silent drift between `SurVibeApp.appSchema`,
/// `SwiftDataTestContainer.schema`, and `freshContext()`'s delete list.
///
/// If you add a new `@Model` class, these tests fail loudly until you:
/// 1. Add it to `SurVibeApp.appSchema`
/// 2. Add it to `SwiftDataTestContainer.schema`
/// 3. Add a `context.delete(model:)` line to `freshContext()`
/// 4. Bump `expectedModelCount` below
@Suite("SwiftData Schema Sync")
struct SwiftDataSchemaSyncTests {
    /// Hard-coded model count. Bumping this is the checkpoint that forces
    /// a human to revisit all three sync points above.
    private static let expectedModelCount = 13

    @Test("Test container schema matches the hard-coded model count")
    func testContainerSchemaCountMatchesExpected() {
        #expect(
            SwiftDataTestContainer.schema.entities.count == Self.expectedModelCount,
            """
            SwiftDataTestContainer.schema has \
            \(SwiftDataTestContainer.schema.entities.count) models; \
            expected \(Self.expectedModelCount). If you added a model, also \
            update freshContext() and bump expectedModelCount.
            """
        )
    }

    @Test("App schema and test container schema contain the same model set")
    func appAndTestSchemasMatch() {
        let appNames = Set(SurVibeApp.appSchema.entities.map(\.name))
        let testNames = Set(SwiftDataTestContainer.schema.entities.map(\.name))
        let appOnly = appNames.subtracting(testNames)
        let testOnly = testNames.subtracting(appNames)
        #expect(
            appOnly.isEmpty && testOnly.isEmpty,
            """
            Schema drift detected.
            In app but missing from test container: \(appOnly.sorted())
            In test container but missing from app: \(testOnly.sorted())
            """
        )
    }
}
