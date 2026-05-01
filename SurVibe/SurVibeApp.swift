import SVAI
import SVAdvanced
import SVAudio
import SVBilling
import SVCore
import SVLearning
import SVSocial
import SwiftData
import SwiftUI
import os.log

/// SurVibe app entry point — Indian music learning platform.
@main
struct SurVibeApp: App {
    // MARK: - Properties

    /// ModelContainer with all 16 SwiftData models and CloudKit automatic sync.
    /// Falls back to in-memory store if persistent container fails.
    let modelContainer: ModelContainer

    // MARK: - Initialization

    init() {
        // Unbuffer stdout so debug print() statements flow to devicectl --console
        // in real time instead of accumulating in libc's 4KB block buffer.
        // Debug-only — production builds have no print() calls in hot paths.
        #if DEBUG
        setvbuf(stdout, nil, _IONBF, 0)
        #endif

        let schema = Self.appSchema
        let isTestHost = ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil

        if isTestHost {
            modelContainer = Self.createTestContainer(schema: schema)
        } else {
            modelContainer = Self.createProductionContainer(schema: schema)
        }

        // Gamification service with dedicated context from the same container.
        let gamContext = ModelContext(modelContainer)
        _gamificationService = State(wrappedValue: GamificationService(modelContext: gamContext))

        Self.configureAnalytics()
        CrashReportingManager.shared.activate()

        if !isTestHost {
            // Diagnostic instrumentation (Task 20 hang triage): always force
            // file-mirror ON in DEBUG, regardless of any persisted user toggle.
            // Release builds still respect the user toggle.
            #if DEBUG
            MultiChannelLog.shared.isFileMirrorEnabled = true
            MultiChannelLog.shared.log(.info, "=== app launch (DEBUG file-mirror forced ON) ===")
            #else
            if UserDefaults.standard.object(forKey: "audioLogsEnabled") != nil {
                MultiChannelLog.shared.isFileMirrorEnabled =
                    UserDefaults.standard.bool(forKey: "audioLogsEnabled")
            }
            #endif
        }

        if !isTestHost {
            SeedContentLoader.loadSeedContentIfNeeded(into: modelContainer)
        }
    }

    // MARK: - Schema

    /// SwiftData schema with all app models.
    ///
    /// Must stay in sync with `SwiftDataTestContainer.schema` and
    /// `SwiftDataTestContainer.freshContext()`.
    /// `SwiftDataSchemaSyncTests` enforces the app/test schema match at test time.
    static var appSchema: Schema {
        Schema([
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
            RecordedTake.self,
            PlayAlongSession.self,
            NotationCache.self,
        ])
    }

    // MARK: - Container Factory

    /// Create an in-memory container for test hosts.
    private static func createTestContainer(schema: Schema) -> ModelContainer {
        do {
            let testConfig = ModelConfiguration(isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [testConfig])
        } catch {
            fatalError("Test ModelContainer failed: \(error)")
        }
    }

    /// Create the production container with CloudKit sync and schema migration.
    private static func createProductionContainer(schema: Schema) -> ModelContainer {
        let appLogger = Logger.survibe(category: "App")
        let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)

        // Proactive store reset on schema version change
        let currentSchemaVersion = 9
        let previousVersion = UserDefaults.standard.integer(forKey: "survibe_schema_version")
        if previousVersion != 0, previousVersion < currentSchemaVersion {
            appLogger.info(
                "Schema version changed (\(previousVersion) → \(currentSchemaVersion)). Resetting store."
            )
            deleteSwiftDataStore()
            // Reset seed content version so SeedContentLoader re-imports after store wipe
            SeedContentLoader.resetForSchemaMigration()
        }
        UserDefaults.standard.set(currentSchemaVersion, forKey: "survibe_schema_version")

        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            appLogger.error(
                "ModelContainer creation failed: \(error.localizedDescription). Attempting store reset."
            )
            deleteSwiftDataStore()
            return retryOrFallback(schema: schema, config: config, logger: appLogger)
        }
    }

    /// Retry container creation after store deletion, falling back to in-memory.
    private static func retryOrFallback(
        schema: Schema,
        config: ModelConfiguration,
        logger: Logger
    ) -> ModelContainer {
        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            logger.info("ModelContainer created after store reset.")
            return container
        } catch {
            logger.error(
                "Retry failed: \(error.localizedDescription). Falling back to in-memory store."
            )
            do {
                let fallback = ModelConfiguration(isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [fallback])
            } catch {
                fatalError("Failed to create even in-memory ModelContainer: \(error)")
            }
        }
    }

    /// Configure PostHog analytics from Info.plist API key.
    private static func configureAnalytics() {
        let apiKey = Bundle.main.object(forInfoDictionaryKey: "POSTHOG_API_KEY") as? String ?? ""
        #if DEBUG
            if apiKey.isEmpty || apiKey.contains("PLACEHOLDER") {
                Logger.survibe(category: "App")
                    .warning("PostHog API key not configured. Analytics disabled.")
            }
        #endif
        #if !DEBUG
            if apiKey.isEmpty || apiKey.contains("PLACEHOLDER") {
                preconditionFailure(
                    """
                    PostHog API key is not configured. \
                    Set POSTHOG_API_KEY in PostHogConfig.xcconfig \
                    before building for Release.
                    """
                )
            }
        #endif
        if !apiKey.isEmpty, !apiKey.contains("PLACEHOLDER") {
            AnalyticsManager.shared.configure(apiKey: apiKey)
        }
        AnalyticsManager.shared.track(.appScaffoldingLoaded)
    }

    // MARK: - Store Management

    /// Deletes all SwiftData/Core Data store files to recover from schema mismatches.
    ///
    /// During early development, new `@Model` types change the schema.
    /// SwiftData with CloudKit cannot use versioned-schema migration, so the safest
    /// recovery is to delete the local store and let CloudKit re-sync.
    /// Scans Application Support for all `.store` / `.sqlite` files and their
    /// WAL/SHM companions.
    private static func deleteSwiftDataStore() {
        let appLogger = Logger.survibe(category: "App")
        guard
            let appSupportURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else { return }

        let fm = FileManager.default
        let storeExtensions: Set<String> = ["store", "store-shm", "store-wal", "sqlite", "sqlite-shm", "sqlite-wal"]

        guard
            let contents = try? fm.contentsOfDirectory(
                at: appSupportURL,
                includingPropertiesForKeys: nil
            )
        else { return }

        for file in contents where storeExtensions.contains(file.pathExtension) {
            do {
                try fm.removeItem(at: file)
                appLogger.info("Deleted store file: \(file.lastPathComponent)")
            } catch {
                appLogger.error("Failed to delete \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - State

    /// Onboarding manager injected into the view hierarchy.
    @State
    private var onboardingManager = OnboardingManager()

    /// Gamification service managing XP, Rang, Achievements, and Streaks.
    ///
    /// Uses a dedicated `ModelContext` from the same `ModelContainer`.
    /// All critical writes call `save()`, keeping it in sync with the
    /// view hierarchy's auto-saving context.
    @State
    private var gamificationService: GamificationService

    /// App-wide theme manager controlling background gradients, accent colors,
    /// and visual presets. Injected into the environment for all views.
    @State
    private var themeManager = AppThemeManager()

    /// App-wide router managing tab selection and navigation. Hosted here
    /// (not in `ContentView`) so menu-bar `AppCommands` can receive it as
    /// a constructor parameter.
    @State
    private var router = AppRouter()

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(onboardingManager)
                .environment(AuthManager.shared)
                .environment(gamificationService)
                .environment(themeManager)
                .environment(router)
        }
        .modelContainer(modelContainer)
        .commands {
            AppCommands(router: router)
            TransportCommands()  // NEW
        }

        #if os(macOS)
            // Settings scene — on macOS (SP-6) this becomes the
            // Preferences window, activated by Cmd+,.
            // On iOS/iPadOS, this is unavailable by design (Apple HIG
            // directs in-app settings to live in the app itself; SP-4 will add
            // an iOS navigation route).
            Settings {
                SettingsView()
                    .environment(onboardingManager)
                    .environment(AuthManager.shared)
                    .environment(gamificationService)
                    .environment(themeManager)
                    .environment(router)
            }
        #endif
    }
}
