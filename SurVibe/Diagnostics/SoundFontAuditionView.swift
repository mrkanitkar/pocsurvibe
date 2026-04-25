#if DEBUG
import AVFoundation
import AudioToolbox
import SVAudio
import SwiftUI

/// On-device A/B audition tool for comparing two SoundFont banks side-by-side
/// through `AVAudioUnitSampler` — the same Audio Unit used in production.
///
/// Loads two user-selected `.sf2` files into separate sampler instances
/// attached to the shared `AudioEngineManager.shared.engine`, then plays the
/// same notes through whichever sampler is currently active. Switching is
/// instant because both samplers stay loaded and the inactive one is silenced
/// via `volume = 0` rather than detached/reloaded.
///
/// What it produces is exactly what students will hear in the production
/// playback path: same AU, same engine, same audio session. Browser players
/// (SpessaSynth, Polyphone) have better SF2 modulator support than Apple's
/// sampler and can mislead a casual A/B test.
///
/// ## Usage
///
/// 1. Copy `MuseScore_General.sf2` and `GeneralUser-GS.sf2` to the iPad's
///    Files app (iCloud Drive or "On My iPad").
/// 2. In SurVibe (DEBUG build), open Settings → SoundFont A/B Audition.
/// 3. Tap "Pick Bank A" and "Pick Bank B" to load both files.
/// 4. Pick a GM program (Bright Piano, Strings, Sitar, Flute, etc.).
/// 5. Toggle A ↔ B while playing notes to compare timbres.
struct SoundFontAuditionView: View {

    // MARK: - Types

    /// One of the two A/B audition slots.
    enum Slot: String, CaseIterable, Identifiable {
        case a = "A"
        case b = "B"
        var id: String { rawValue }
    }

    /// A General MIDI program with a friendly label for the picker.
    struct GMProgram: Hashable, Identifiable {
        let program: UInt8
        let label: String
        var id: UInt8 { program }
    }

    // MARK: - Constants

    /// One General MIDI Level 1 family — 8 consecutive programs sharing a
    /// timbral category. Used to group the 128-program picker by section.
    struct GMFamily: Identifiable {
        let name: String
        let programs: [GMProgram]
        var id: String { name }
    }

    /// All 128 General MIDI Level 1 melodic programs, grouped by family.
    /// Names follow the GM Level 1 standard (https://en.wikipedia.org/wiki/General_MIDI).
    /// Both MuseScore_General and GeneralUser-GS implement the full GM map
    /// in bank 0, so any of these 128 programs is auditionable on either bank.
    private static let gmFamilies: [GMFamily] = [
        GMFamily(name: "Piano",                 programs: makeFamily(start: 0, names: [
            "Acoustic Grand", "Bright Acoustic", "Electric Grand", "Honky-Tonk",
            "Electric Piano 1 (Rhodes)", "Electric Piano 2 (FM)", "Harpsichord", "Clavinet",
        ])),
        GMFamily(name: "Chromatic Percussion",  programs: makeFamily(start: 8, names: [
            "Celesta", "Glockenspiel", "Music Box", "Vibraphone",
            "Marimba", "Xylophone", "Tubular Bells", "Dulcimer",
        ])),
        GMFamily(name: "Organ",                 programs: makeFamily(start: 16, names: [
            "Drawbar Organ", "Percussive Organ", "Rock Organ", "Church Organ",
            "Reed Organ", "Accordion", "Harmonica", "Tango Accordion",
        ])),
        GMFamily(name: "Guitar",                programs: makeFamily(start: 24, names: [
            "Nylon Guitar", "Steel Guitar", "Jazz Guitar", "Clean Guitar",
            "Muted Guitar", "Overdrive Guitar", "Distortion Guitar", "Guitar Harmonics",
        ])),
        GMFamily(name: "Bass",                  programs: makeFamily(start: 32, names: [
            "Acoustic Bass", "Finger Bass", "Pick Bass", "Fretless Bass",
            "Slap Bass 1", "Slap Bass 2", "Synth Bass 1", "Synth Bass 2",
        ])),
        GMFamily(name: "Strings (Solo)",        programs: makeFamily(start: 40, names: [
            "Violin", "Viola", "Cello", "Contrabass",
            "Tremolo Strings", "Pizzicato Strings", "Orchestral Harp", "Timpani",
        ])),
        GMFamily(name: "Ensemble",              programs: makeFamily(start: 48, names: [
            "String Ensemble 1", "String Ensemble 2", "Synth Strings 1", "Synth Strings 2",
            "Choir Aahs", "Voice Oohs", "Synth Voice", "Orchestra Hit",
        ])),
        GMFamily(name: "Brass",                 programs: makeFamily(start: 56, names: [
            "Trumpet", "Trombone", "Tuba", "Muted Trumpet",
            "French Horn", "Brass Section", "Synth Brass 1", "Synth Brass 2",
        ])),
        GMFamily(name: "Reed",                  programs: makeFamily(start: 64, names: [
            "Soprano Sax", "Alto Sax", "Tenor Sax", "Baritone Sax",
            "Oboe", "English Horn", "Bassoon", "Clarinet",
        ])),
        GMFamily(name: "Pipe",                  programs: makeFamily(start: 72, names: [
            "Piccolo", "Flute", "Recorder", "Pan Flute",
            "Blown Bottle", "Shakuhachi", "Whistle", "Ocarina",
        ])),
        GMFamily(name: "Synth Lead",            programs: makeFamily(start: 80, names: [
            "Lead 1 (Square)", "Lead 2 (Sawtooth)", "Lead 3 (Calliope)", "Lead 4 (Chiff)",
            "Lead 5 (Charang)", "Lead 6 (Voice)", "Lead 7 (Fifths)", "Lead 8 (Bass+Lead)",
        ])),
        GMFamily(name: "Synth Pad",             programs: makeFamily(start: 88, names: [
            "Pad 1 (New Age)", "Pad 2 (Warm)", "Pad 3 (Polysynth)", "Pad 4 (Choir)",
            "Pad 5 (Bowed)", "Pad 6 (Metallic)", "Pad 7 (Halo)", "Pad 8 (Sweep)",
        ])),
        GMFamily(name: "Synth Effects",         programs: makeFamily(start: 96, names: [
            "FX 1 (Rain)", "FX 2 (Soundtrack)", "FX 3 (Crystal)", "FX 4 (Atmosphere)",
            "FX 5 (Brightness)", "FX 6 (Goblins)", "FX 7 (Echoes)", "FX 8 (Sci-Fi)",
        ])),
        GMFamily(name: "Ethnic",                programs: makeFamily(start: 104, names: [
            "Sitar", "Banjo", "Shamisen", "Koto",
            "Kalimba", "Bagpipe", "Fiddle", "Shenai",
        ])),
        GMFamily(name: "Percussive",            programs: makeFamily(start: 112, names: [
            "Tinkle Bell", "Agogo", "Steel Drums", "Woodblock",
            "Taiko Drum", "Melodic Tom", "Synth Drum", "Reverse Cymbal",
        ])),
        GMFamily(name: "Sound Effects",         programs: makeFamily(start: 120, names: [
            "Guitar Fret Noise", "Breath Noise", "Seashore", "Bird Tweet",
            "Telephone Ring", "Helicopter", "Applause", "Gunshot",
        ])),
    ]

    /// Flat list of all 128 GM programs (used to find the default selection
    /// and to look up by program number).
    private static let allPrograms: [GMProgram] = gmFamilies.flatMap(\.programs)

    private static func makeFamily(start: Int, names: [String]) -> [GMProgram] {
        names.enumerated().map { offset, name in
            let pc = UInt8(start + offset)
            return GMProgram(program: pc, label: "\(pc) — \(name)")
        }
    }

    /// One-octave chromatic keyboard from C4 (MIDI 60) to C5 (MIDI 72).
    /// Reasonable lap-friendly size on iPad without a ScrollView.
    private static let keyboardRange: ClosedRange<UInt8> = 60...72

    /// The Sa-Re-Ga-Ma-Pa-Dha-Ni-Sa ascending sequence used by the auto-test
    /// button — the canonical pedagogical scale for SurVibe's domain.
    private static let testSequence: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]

    // MARK: - State

    @State private var samplerA: AVAudioUnitSampler?
    @State private var samplerB: AVAudioUnitSampler?
    @State private var urlA: URL?
    @State private var urlB: URL?
    @State private var fileNameA: String?
    @State private var fileNameB: String?
    @State private var loadErrorA: String?
    @State private var loadErrorB: String?
    @State private var activeSlot: Slot = .a
    @State private var selectedProgram: GMProgram = allPrograms[1]  // Bright Acoustic
    @State private var pickerSlot: Slot?
    @State private var isFileImporterPresented = false
    @State private var heldNotes: Set<UInt8> = []
    @State private var isPlayingSequence = false

    // MARK: - Body

    var body: some View {
        Form {
            Section("Bank A") {
                slotRow(for: .a, fileName: fileNameA, error: loadErrorA)
            }
            Section("Bank B") {
                slotRow(for: .b, fileName: fileNameB, error: loadErrorB)
            }
            Section("Active") {
                Picker("Active bank", selection: $activeSlot) {
                    ForEach(Slot.allCases) { slot in
                        Text(slot.rawValue).tag(slot)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: activeSlot) { _, _ in updateActiveVolumes() }
                .accessibilityLabel("Active sampler bank")
            }
            Section("Voice (GM Program — all 128)") {
                Picker("Program", selection: $selectedProgram) {
                    ForEach(Self.gmFamilies) { family in
                        Section(family.name) {
                            ForEach(family.programs) { program in
                                Text(program.label).tag(program)
                            }
                        }
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: selectedProgram) { _, newValue in
                    reloadProgramOnAllLoadedSamplers(newValue.program)
                }
                Text(verbatim: "Tap the menu above to pick any of all 128 GM programs, grouped by family.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Play") {
                keyboard
                Button {
                    Task { await playTestSequence() }
                } label: {
                    Label(
                        isPlayingSequence ? "Playing Sa-Re-Ga…" : "Play Sa-Re-Ga-Ma-Pa-Dha-Ni-Sa",
                        systemImage: isPlayingSequence ? "stop.circle" : "play.circle.fill"
                    )
                }
                .disabled(isPlayingSequence || (samplerA == nil && samplerB == nil))
                .accessibilityLabel("Play the Sa-Re-Ga-Ma scale through the active bank")
            }
            AuditionSongPlaybackSection(samplerA: samplerA, samplerB: samplerB)
        }
        .navigationTitle("SoundFont A/B Audition")
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.init(filenameExtension: "sf2") ?? .data]
        ) { result in
            handleFileImport(result)
        }
        .task {
            await ensureEngineRunning()
            attachSamplersIfNeeded()
            autoLoadBundledBanksIfPresent()
        }
        .onDisappear {
            detachSamplers()
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func slotRow(for slot: Slot, fileName: String?, error: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                pickerSlot = slot
                isFileImporterPresented = true
            } label: {
                Label(
                    fileName ?? "Pick .sf2 for slot \(slot.rawValue)",
                    systemImage: fileName != nil ? "checkmark.circle.fill" : "doc.badge.plus"
                )
            }
            .accessibilityLabel("Pick SoundFont for slot \(slot.rawValue)")
            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Load error for slot \(slot.rawValue): \(error)")
            }
        }
    }

    private var keyboard: some View {
        HStack(spacing: 2) {
            ForEach(Array(Self.keyboardRange), id: \.self) { midi in
                let isBlack = Self.isBlackKey(midi)
                let isHeld = heldNotes.contains(midi)
                Rectangle()
                    .fill(isHeld ? Color.accentColor : (isBlack ? Color.black : Color.white))
                    .frame(height: isBlack ? 80 : 120)
                    .overlay(
                        Rectangle().stroke(Color.gray.opacity(0.4), lineWidth: 0.5)
                    )
                    .overlay(alignment: .bottom) {
                        Text(Self.noteName(midi))
                            .font(.caption2)
                            .foregroundStyle(isBlack ? .white : .black)
                            .padding(.bottom, 4)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                guard !heldNotes.contains(midi) else { return }
                                heldNotes.insert(midi)
                                playNote(midi)
                            }
                            .onEnded { _ in
                                heldNotes.remove(midi)
                                stopNote(midi)
                            }
                    )
                    .accessibilityLabel("Play \(Self.noteName(midi))")
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Engine Setup

    /// Ensure the shared production engine is running so we can attach
    /// audition samplers to it. We deliberately reuse `AudioEngineManager`'s
    /// engine rather than spinning a second `AVAudioEngine` to honor the
    /// project-wide single-engine rule (see `.claude/rules/audio.md`).
    private func ensureEngineRunning() async {
        do {
            try AudioEngineManager.shared.startForPlayback()
        } catch {
            loadErrorA = "Engine start failed: \(error.localizedDescription)"
        }
    }

    /// Attach two fresh samplers (A and B) to the shared engine and connect
    /// them to the main mixer. Idempotent — bails out if they already exist.
    private func attachSamplersIfNeeded() {
        let engine = AudioEngineManager.shared.engine
        let mixer = engine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)

        if samplerA == nil {
            let sampler = AVAudioUnitSampler()
            engine.attach(sampler)
            engine.connect(sampler, to: mixer, format: format)
            sampler.volume = activeSlot == .a ? 1.0 : 0.0
            samplerA = sampler
        }
        if samplerB == nil {
            let sampler = AVAudioUnitSampler()
            engine.attach(sampler)
            engine.connect(sampler, to: mixer, format: format)
            sampler.volume = activeSlot == .b ? 1.0 : 0.0
            samplerB = sampler
        }
    }

    /// Detach both audition samplers from the shared engine when the view
    /// dismisses so the production graph returns to its baseline state.
    private func detachSamplers() {
        let engine = AudioEngineManager.shared.engine
        for note in heldNotes { stopNote(note) }
        heldNotes.removeAll()
        if let sampler = samplerA {
            engine.detach(sampler)
            samplerA = nil
        }
        if let sampler = samplerB {
            engine.detach(sampler)
            samplerB = nil
        }
        urlA = nil
        urlB = nil
    }

    // MARK: - File Loading

    /// Auto-load the two bundled audition banks if they're present in the
    /// app bundle (added via the synchronized `Diagnostics/AuditionAssets/`
    /// folder group). Skips a slot that already has a file picked manually.
    /// Only runs in DEBUG; the resources are excluded from Release builds
    /// via target membership.
    private func autoLoadBundledBanksIfPresent() {
        let bundle = Bundle.main
        if fileNameA == nil,
           let url = bundle.url(forResource: "MuseScore_General", withExtension: "sf2") {
            loadSoundFont(at: url, into: .a)
        }
        if fileNameB == nil,
           let url = bundle.url(forResource: "GeneralUser-GS", withExtension: "sf2") {
            loadSoundFont(at: url, into: .b)
        }
    }

    private func handleFileImport(_ result: Result<URL, Error>) {
        guard let slot = pickerSlot else { return }
        defer { pickerSlot = nil }
        switch result {
        case .success(let url):
            loadSoundFont(at: url, into: slot)
        case .failure(let error):
            switch slot {
            case .a: loadErrorA = error.localizedDescription
            case .b: loadErrorB = error.localizedDescription
            }
        }
    }

    /// Load an SF2 into the given slot's sampler at the currently-selected
    /// GM program. Acquires a security-scoped resource for files outside the
    /// app's container (iCloud Drive, On My iPad, etc.).
    private func loadSoundFont(at url: URL, into slot: Slot) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        let sampler: AVAudioUnitSampler?
        switch slot {
        case .a: sampler = samplerA
        case .b: sampler = samplerB
        }
        guard let sampler else {
            setError("Sampler not attached", for: slot)
            return
        }

        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: selectedProgram.program,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: 0
            )
            switch slot {
            case .a:
                fileNameA = url.lastPathComponent
                urlA = url
                loadErrorA = nil
            case .b:
                fileNameB = url.lastPathComponent
                urlB = url
                loadErrorB = nil
            }
        } catch {
            setError("Load failed: \(error.localizedDescription)", for: slot)
        }
    }

    /// Reload the new GM program on every loaded sampler so the user can
    /// switch voices (e.g. Bright Piano → Sitar) without re-picking files.
    ///
    /// IMPORTANT: `AVAudioUnitSampler` only ever holds ONE preset at a time.
    /// `sendProgramChange` does NOT swap the loaded preset — it sends a
    /// MIDI message that has nothing to swap to. Real preset switching
    /// requires re-calling `loadSoundBankInstrument` with the new program.
    /// (For multi-timbral playback you'd use `AUMIDISynth` instead, but
    /// this audition tool stays on the same AU SurVibe ships in production.)
    private func reloadProgramOnAllLoadedSamplers(_ program: UInt8) {
        for note in heldNotes { stopNote(note) }
        heldNotes.removeAll()
        if let urlA, let samplerA {
            reloadSampler(samplerA, url: urlA, program: program, slot: .a)
        }
        if let urlB, let samplerB {
            reloadSampler(samplerB, url: urlB, program: program, slot: .b)
        }
    }

    private func reloadSampler(
        _ sampler: AVAudioUnitSampler,
        url: URL,
        program: UInt8,
        slot: Slot
    ) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: program,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: 0
            )
            switch slot {
            case .a: loadErrorA = nil
            case .b: loadErrorB = nil
            }
        } catch {
            setError("Program switch failed: \(error.localizedDescription)", for: slot)
        }
    }

    // MARK: - Playback

    private func updateActiveVolumes() {
        samplerA?.volume = activeSlot == .a ? 1.0 : 0.0
        samplerB?.volume = activeSlot == .b ? 1.0 : 0.0
    }

    private func playNote(_ midi: UInt8) {
        // Send to BOTH samplers so the inactive one stays "armed" and the
        // toggle is instant — the inactive sampler's volume is 0 so it's
        // silent regardless.
        samplerA?.startNote(midi, withVelocity: 100, onChannel: 0)
        samplerB?.startNote(midi, withVelocity: 100, onChannel: 0)
    }

    private func stopNote(_ midi: UInt8) {
        samplerA?.stopNote(midi, onChannel: 0)
        samplerB?.stopNote(midi, onChannel: 0)
    }

    private func playTestSequence() async {
        isPlayingSequence = true
        defer { isPlayingSequence = false }
        for note in Self.testSequence {
            playNote(note)
            try? await Task.sleep(nanoseconds: 350_000_000)  // 350 ms per note
            stopNote(note)
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: - Helpers

    private func setError(_ message: String, for slot: Slot) {
        switch slot {
        case .a: loadErrorA = message
        case .b: loadErrorB = message
        }
    }

    private static func isBlackKey(_ midi: UInt8) -> Bool {
        let pitchClass = Int(midi) % 12
        return [1, 3, 6, 8, 10].contains(pitchClass)
    }

    private static func noteName(_ midi: UInt8) -> String {
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        let octave = Int(midi) / 12 - 1
        return "\(names[Int(midi) % 12])\(octave)"
    }
}

#Preview {
    NavigationStack {
        SoundFontAuditionView()
    }
}

// MARK: - AuditionSongPlaybackSection

/// Bundled-MIDI playback section of the audition view, factored into a
/// child View struct so the parent struct stays under SwiftLint's
/// `type_body_length` limit. Owns the two `AVAudioSequencer` instances
/// and the song-playback state machine; the parent retains the two
/// `AVAudioUnitSampler` nodes (the destinations) and the A↔B selection.
///
/// The audible bank is selected by sampler volume in the parent view's
/// `updateActiveVolumes` — both sequencers play in lockstep regardless,
/// and the inactive sampler renders to silence. Toggling A↔B mid-playback
/// is therefore a glitch-free volume swap.
@MainActor
private struct AuditionSongPlaybackSection: View {

    /// Phases of song playback through the bundled MIDI sequencer pair.
    enum PlaybackPhase: String {
        case stopped, playing, paused
    }

    /// Resource name (without extension) of the bundled audition song MIDI
    /// inside `AuditionAssets/`.
    private static let bundledSongResource = "Sukhkarta_Dukhharta"

    /// Position-display refresh rate while the song is playing (Hz).
    /// 30 Hz keeps `Slider` and time labels visually fluid without burning
    /// significant main-thread budget on a diagnostic view.
    private static let positionUpdateRate: Double = 30.0

    /// Two destination samplers owned by the parent view. May be `nil`
    /// briefly during view setup; `loadSongIfBundled` waits until both are
    /// non-`nil` before instantiating sequencers.
    let samplerA: AVAudioUnitSampler?
    let samplerB: AVAudioUnitSampler?

    @State private var sequencerA: AVAudioSequencer?
    @State private var sequencerB: AVAudioSequencer?
    @State private var playState: PlaybackPhase = .stopped
    @State private var currentPosition: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var tempoMultiplier: Double = 1.0
    @State private var songLoadError: String?

    var body: some View {
        Section("Song A/B (Sukhkarta Dukhharta)") {
            if let songLoadError {
                Text(verbatim: songLoadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Song error: \(songLoadError)")
            }
            HStack(spacing: 16) {
                Button {
                    playSong()
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(playState == .playing || sequencerA == nil)
                .accessibilityLabel("Play song through active bank")

                Button {
                    pauseSong()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .disabled(playState != .playing)
                .accessibilityLabel("Pause song")

                Button {
                    stopSong()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(playState == .stopped && currentPosition == 0)
                .accessibilityLabel("Stop song and reset to start")
            }
        }
        .task { loadSongIfBundled() }
        .onDisappear { teardownSequencers() }
    }

    /// Load the bundled MIDI song into two `AVAudioSequencer` instances
    /// and route each to its corresponding audition sampler. Idempotent.
    private func loadSongIfBundled() {
        guard sequencerA == nil, sequencerB == nil else { return }
        guard let url = Bundle.main.url(
            forResource: Self.bundledSongResource, withExtension: "mid"
        ) else {
            songLoadError = "Bundled song MIDI not found"
            return
        }
        guard let samplerA, let samplerB else {
            songLoadError = "Samplers not attached"
            return
        }
        let engine = AudioEngineManager.shared.engine
        do {
            let seqA = AVAudioSequencer(audioEngine: engine)
            try seqA.load(from: url, options: [])
            for track in seqA.tracks {
                track.destinationAudioUnit = samplerA
            }
            let seqB = AVAudioSequencer(audioEngine: engine)
            try seqB.load(from: url, options: [])
            for track in seqB.tracks {
                track.destinationAudioUnit = samplerB
            }
            let maxLen = max(
                seqA.tracks.map(\.lengthInSeconds).max() ?? 0,
                seqB.tracks.map(\.lengthInSeconds).max() ?? 0
            )
            sequencerA = seqA
            sequencerB = seqB
            duration = maxLen
            songLoadError = nil
        } catch {
            songLoadError = "Song load failed: \(error.localizedDescription)"
        }
    }

    private func teardownSequencers() {
        sequencerA?.stop()
        sequencerB?.stop()
        sequencerA = nil
        sequencerB = nil
        playState = .stopped
        currentPosition = 0
    }

    /// Start both sequencers simultaneously. The active sampler's volume
    /// determines what the user hears.
    private func playSong() {
        guard let sequencerA, let sequencerB else { return }
        do {
            try sequencerA.start()
            try sequencerB.start()
            playState = .playing
        } catch {
            songLoadError = "Sequencer start failed: \(error.localizedDescription)"
            playState = .stopped
        }
    }

    /// Pause both sequencers. `currentPositionInSeconds` is preserved.
    private func pauseSong() {
        sequencerA?.stop()
        sequencerB?.stop()
        playState = .paused
    }

    /// Stop both sequencers and seek back to 0.
    private func stopSong() {
        sequencerA?.stop()
        sequencerB?.stop()
        sequencerA?.currentPositionInSeconds = 0
        sequencerB?.currentPositionInSeconds = 0
        currentPosition = 0
        playState = .stopped
    }
}
#endif
