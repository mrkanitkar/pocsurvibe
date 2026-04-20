import SVCore
import SwiftUI
import os.log

/// The main Home tab view providing a discovery-oriented landing experience.
///
/// Displays a welcome header and a grid of "Doors" — tappable cards that
/// navigate to different sections of the app. Enabled doors switch tabs
/// directly; disabled doors present a "Coming Soon" half-sheet explaining
/// the upcoming feature.
///
/// The view wraps its content in a `NavigationStack` since the Home tab
/// does not have one provided by ContentView's TabView.
///
/// ## Door Layout
/// - **Songs** and **Learn** are enabled and navigate to their respective tabs.
/// - **Moods**, **Events**, and **Ragas** are disabled with "Coming Soon" overlays.
struct HomeTab: View {
    // MARK: - Properties

    /// App-wide navigation router injected from the environment.
    @Environment(AppRouter.self)
    private var router

    /// App-wide theme manager for background gradients and accent colors.
    @Environment(AppThemeManager.self) private var themeManager

    /// Tracks which "Coming Soon" door is currently showing its sheet.
    /// The value is a `ComingSoonDoor` case, or `nil` if no sheet is presented.
    @State
    private var showComingSoon: ComingSoonDoor?

    /// Adaptive grid layout for door cards, minimum 160pt per column.
    private let gridColumns = [
        GridItem(.adaptive(minimum: 160), spacing: 16)
    ]

    /// Logger for Home tab events.
    private static let logger = Logger.survibe(category: "HomeTab")

    /// Tracks which door has hardware-keyboard focus.
    @FocusState
    private var focusedDoorID: HomeDoorID?

    /// Home grid is effectively 2 columns (adaptive minimum 160pt on all
    /// supported widths packs the 5 doors into 2-col grid on iPhone +
    /// iPad portrait). Wide-iPad landscape may render 3+ columns; arrow-
    /// key math stays 2-col (graceful linear degradation).
    private static let homeGridColumns = 2

    /// Moves keyboard focus to the next door in the given direction.
    private func moveFocus(_ direction: LibraryFocusNavigator.FocusDirection, from currentID: HomeDoorID) {
        let doors = HomeDoorID.allCases
        guard let currentIndex = doors.firstIndex(of: currentID) else { return }
        guard
            let nextIndex = LibraryFocusNavigator.nextIndex(
                for: direction,
                currentIndex: currentIndex,
                count: doors.count,
                columns: Self.homeGridColumns
            )
        else { return }
        focusedDoorID = doors[nextIndex]
    }

    /// Builds the focus + keyboard + ring modifier chain for a DoorCard.
    /// Consolidates the 4-modifier chain so each DoorCard site stays scannable.
    private func homeDoorNav(for doorID: HomeDoorID, action: @escaping () -> Void) -> HomeDoorNavModifier {
        HomeDoorNavModifier(
            doorID: doorID,
            focusedID: focusedDoorID,
            focusBinding: $focusedDoorID,
            accent: themeManager.resolved.accentColor,
            onReturn: action,
            onMove: { direction, id in moveFocus(direction, from: id) }
        )
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    welcomeHeader
                    discoverSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 24)
            }
            .navigationTitle("Home")
            .background(
                LinearGradient(
                    colors: themeManager.resolved.backgroundGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
        }
        .sheet(item: $showComingSoon) { door in
            ComingSoonSheet(
                doorTitle: door.title,
                doorIcon: door.icon,
                doorDescription: door.sheetDescription
            )
        }
        .onAppear {
            if focusedDoorID == nil {
                focusedDoorID = .songs
            }
        }
        .accessibilityLabel(AccessibilityHelper.tabLabel(for: "Home"))
    }

    // MARK: - Private Views

    /// Welcome header with app title and tagline.
    private var welcomeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Welcome to SurVibe")
                .font(.title)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)

            Text("Explore Indian classical music through play")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Discover section containing the door card grid.
    private var discoverSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Discover")
                .font(.title3)
                .fontWeight(.semibold)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: gridColumns, spacing: 16) {
                // Songs — enabled
                DoorCard(
                    icon: "music.note",
                    title: "Songs",
                    subtitle: "Explore melodies from Indian cinema",
                    gradientColors: [
                        .rangNeel,
                        Color(red: 0.18, green: 0.22, blue: 0.55),
                    ],
                    isEnabled: true
                ) {
                    Self.logger.debug("Door tapped: Songs")
                    router.switchTab(to: .songs)
                }
                .modifier(homeDoorNav(for: .songs) {
                    router.switchTab(to: .songs)
                })

                // Learn — enabled
                DoorCard(
                    icon: "book.circle",
                    title: "Learn",
                    subtitle: "Guided sargam lessons",
                    gradientColors: [
                        .orange,
                        Color(red: 0.8, green: 0.4, blue: 0.0),
                    ],
                    isEnabled: true
                ) {
                    Self.logger.debug("Door tapped: Learn")
                    router.switchTab(to: .learn)
                }
                .modifier(homeDoorNav(for: .learn) {
                    router.switchTab(to: .learn)
                })

                // Moods — disabled (coming soon)
                DoorCard(
                    icon: "heart.fill",
                    title: "Moods",
                    subtitle: "Play by emotion",
                    gradientColors: [
                        .rangLal,
                        Color(red: 0.65, green: 0.12, blue: 0.12),
                    ],
                    isEnabled: false
                ) {
                    showComingSoon = .moods
                }
                .modifier(homeDoorNav(for: .moods) {
                    showComingSoon = .moods
                })

                // Events — disabled (coming soon)
                DoorCard(
                    icon: "calendar",
                    title: "Events",
                    subtitle: "Seasonal collections",
                    gradientColors: [
                        .rangHara,
                        Color(red: 0.14, green: 0.40, blue: 0.16),
                    ],
                    isEnabled: false
                ) {
                    showComingSoon = .events
                }
                .modifier(homeDoorNav(for: .events) {
                    showComingSoon = .events
                })

                // Ragas — disabled (coming soon)
                DoorCard(
                    icon: "waveform",
                    title: "Ragas",
                    subtitle: "Dive into melodic frameworks",
                    gradientColors: [
                        .purple,
                        Color(red: 0.38, green: 0.15, blue: 0.55),
                    ],
                    isEnabled: false
                ) {
                    showComingSoon = .ragas
                }
                .modifier(homeDoorNav(for: .ragas) {
                    showComingSoon = .ragas
                })
            }
        }
    }
}

// MARK: - HomeDoorNavModifier

/// Attaches `@FocusState` binding + focus ring + Return + arrow-key nav to a DoorCard.
/// Centralises the 4-modifier chain so each HomeTab DoorCard call site is concise.
struct HomeDoorNavModifier: ViewModifier {
    let doorID: HomeDoorID
    let focusedID: HomeDoorID?
    let focusBinding: FocusState<HomeDoorID?>.Binding
    let accent: Color
    let onReturn: () -> Void
    let onMove: (LibraryFocusNavigator.FocusDirection, HomeDoorID) -> Void

    func body(content: Content) -> some View {
        content
            .focused(focusBinding, equals: doorID)
            .focusRing(itemID: doorID, focusedID: focusedID, accent: accent)
            .onKeyPress(.return) {
                onReturn()
                return .handled
            }
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                let direction: LibraryFocusNavigator.FocusDirection
                switch press.key {
                case .upArrow: direction = .up
                case .downArrow: direction = .down
                case .leftArrow: direction = .left
                case .rightArrow: direction = .right
                default: return .ignored
                }
                onMove(direction, doorID)
                return .handled
            }
            .onKeyPress(.escape) {
                // Escape-to-clear handled at the tab container level; no-op here.
                .ignored
            }
    }
}

// MARK: - HomeDoorID

/// Stable identity for the 5 Home DoorCards, used for hardware-keyboard focus.
/// Order matches the rendered grid (row-major, 2 cols assumed).
enum HomeDoorID: String, Hashable, CaseIterable {
    case songs
    case learn
    case moods
    case events
    case ragas
}

// MARK: - ComingSoonDoor

/// Identifiable model for "Coming Soon" door sheets.
///
/// Each case represents a disabled door on the Home tab. Conforming to
/// `Identifiable` enables use with SwiftUI's `.sheet(item:)` modifier.
enum ComingSoonDoor: String, Identifiable {
    case moods
    case events
    case ragas

    /// Unique identifier for `.sheet(item:)`.
    var id: String { rawValue }

    /// Display title for the sheet header.
    var title: String {
        switch self {
        case .moods: "Moods"
        case .events: "Events"
        case .ragas: "Ragas"
        }
    }

    /// SF Symbol icon for the sheet.
    var icon: String {
        switch self {
        case .moods: "heart.fill"
        case .events: "calendar"
        case .ragas: "waveform"
        }
    }

    /// Description text displayed in the "Coming Soon" sheet.
    var sheetDescription: String {
        switch self {
        case .moods:
            "Play songs that match your mood. Relaxing ragas, energizing compositions, and everything in between."
        case .events:
            "Seasonal collections for Diwali, Holi, and more. Play festive music when it matters most."
        case .ragas:
            "Explore the melodic frameworks of Indian classical music. Learn aroha, avaroha, and signature phrases."
        }
    }
}

// MARK: - Preview

#Preview {
    HomeTab()
        .environment(AppRouter())
        .environment(AppThemeManager())
}
