import SVAudio
import SwiftUI

/// Hosts the `PlayAlongViewModel` at a view-tree level that survives
/// rotation / size-class / NavigationSplitView sidebar toggles.
///
/// `@State` ownership here prevents SwiftUI from rebuilding the VM when
/// a parent view re-renders, which would otherwise call
/// `AudioEngineManager.shared.start()` a second time and violate
/// `LatencyContractTests.testRotationDoesNotRestartAudioEngine`.
///
/// `PlayAlongViewModel` accepts its song via `loadSong(_:)` in
/// `SongPlayAlongView`'s `.task`, so only the song reference is stored
/// here for forwarding — the VM itself is created with injected or
/// default dependencies and owns no song at init time.
///
/// This wrapper is the single enforcement point for the rotation-safety invariant.
struct PlayAlongSceneHost: View {
    // MARK: - Properties

    /// The song to display and play along with.
    let song: Song

    /// View model owned here so that SwiftUI re-renders triggered by
    /// rotation or size-class changes do NOT re-initialize the VM and
    /// therefore do NOT trigger a second `AudioEngineManager.start()` call.
    @State
    private var vm: PlayAlongViewModel

    // MARK: - Initialization

    /// Production init. All audio dependencies default to their singletons.
    ///
    /// - Parameter song: The song to play along with.
    init(song: Song) {
        self.song = song
        _vm = State(initialValue: PlayAlongViewModel())
    }

    // MARK: - Body

    var body: some View {
        SongPlayAlongView(song: song, viewModel: vm)
    }
}

// MARK: - Test Support

#if DEBUG
    extension PlayAlongSceneHost {
        /// Test-only init allowing injection of a stub audio engine provider.
        ///
        /// - Parameters:
        ///   - song: The song to play along with.
        ///   - engineOverride: A stub `AudioEngineProviding` used in place of `AudioEngineManager.shared`.
        init(song: Song, engineOverride: any AudioEngineProviding) {
            self.song = song
            _vm = State(initialValue: PlayAlongViewModel(audioEngine: engineOverride))
        }
    }
#endif
