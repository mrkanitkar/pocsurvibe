#if DEBUG
import AudioKit
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

    /// Single shared sampler used by all paths in this view: keyboard taps,
    /// "Play Sa-Re-Ga…" sequence, and bundled song playback. Routed via
    /// `destinationMIDIEndpoint` (CoreMIDI) for sequencer playback so SF2
    /// modulator-driven dynamics render correctly. The A/B segmented
    /// control reloads the corresponding bank's SF2 into this single
    /// sampler (a few-hundred-millisecond reload) — same routing, only
    /// the bank file swaps.
    @State private var sampler: MIDISampler?
    /// Which bank's SF2 is currently loaded into `sampler`, for the
    /// active-slot reload skip and the diagnostic display.
    @State private var loadedSlot: Slot?
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
                .onChange(of: activeSlot) { _, newValue in applySelectedBank(newValue) }
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
                .disabled(isPlayingSequence || sampler == nil)
                .accessibilityLabel("Play the Sa-Re-Ga-Ma scale through the active bank")
            }
            AuditionSongPlaybackSection(sampler: sampler)
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
        guard sampler == nil else { return }
        let engine = AudioEngineManager.shared.engine
        let mixer = engine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)

        let midiSampler = MIDISampler(name: "AuditionShared")
        engine.attach(midiSampler.avAudioNode)
        engine.connect(midiSampler.avAudioNode, to: mixer, format: format)
        midiSampler.volume = 1.0  // single sampler, always audible
        sampler = midiSampler
    }

    /// Detach both audition samplers from the shared engine when the view
    /// dismisses so the production graph returns to its baseline state.
    private func detachSamplers() {
        let engine = AudioEngineManager.shared.engine
        for note in heldNotes { stopNote(note) }
        heldNotes.removeAll()
        if let sampler {
            engine.detach(sampler.avAudioNode)
        }
        sampler = nil
        loadedSlot = nil
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
    /// Store the URL for the slot (so the A/B picker can recall it),
    /// and — if `slot` is currently active — load it into the shared
    /// sampler immediately. Bank picks for the inactive slot are deferred
    /// until the user toggles to that slot.
    private func loadSoundFont(at url: URL, into slot: Slot) {
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
        if slot == activeSlot {
            performBankReload(url: url, slot: slot, program: selectedProgram.program)
        }
    }

    /// Actual SF2 reload into the shared sampler. Acquires security-scoped
    /// resource access if needed (URLs from the file picker require it;
    /// bundle URLs do not).
    ///
    /// **Engine pause/restart wrap (fix P):** `loadSoundBankInstrument` is
    /// synchronous and reallocates AU render resources. Calling it while
    /// the engine is rendering and the sequencer is dispatching MIDI to
    /// the AU's `scheduleMIDIEventBlock` is undocumented behavior and the
    /// likely cause of the "sudden loss" we saw on Bank B. We pause the
    /// engine, reload, restart — Apple's recommended pattern for AU
    /// state changes during a session.
    private func performBankReload(url: URL, slot: Slot, program: UInt8) {
        guard let sampler else {
            setError("Sampler not attached", for: slot)
            return
        }
        let engine = AudioEngineManager.shared.engine
        let wasRunning = engine.isRunning
        if wasRunning { engine.pause() }

        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            try sampler.loadMelodicSoundFont(url: url, preset: Int(program))
            loadedSlot = slot
            switch slot {
            case .a: loadErrorA = nil
            case .b: loadErrorB = nil
            }
        } catch {
            setError("Load failed: \(error.localizedDescription)", for: slot)
        }

        if wasRunning {
            do {
                try engine.start()
            } catch {
                setError(
                    "Engine restart after reload failed: \(error.localizedDescription)",
                    for: slot
                )
            }
        }
    }

    /// Switch the sampler's loaded bank to whichever slot is now active.
    /// Called from the A/B segmented control's `onChange`.
    private func applySelectedBank(_ slot: Slot) {
        let url: URL? = (slot == .a) ? urlA : urlB
        guard let url else { return }
        guard slot != loadedSlot else { return }
        performBankReload(url: url, slot: slot, program: selectedProgram.program)
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
    /// Re-load the active slot's SF2 with the new GM program. Same
    /// reload-on-change pattern we use for A↔B bank switching.
    private func reloadProgramOnAllLoadedSamplers(_ program: UInt8) {
        for note in heldNotes { stopNote(note) }
        heldNotes.removeAll()
        let url: URL? = (activeSlot == .a) ? urlA : urlB
        guard let url else { return }
        performBankReload(url: url, slot: activeSlot, program: program)
    }

    // MARK: - Playback

    private func playNote(_ midi: UInt8) {
        sampler?.play(noteNumber: midi, velocity: 100, channel: 0)
    }

    private func stopNote(_ midi: UInt8) {
        sampler?.stop(noteNumber: midi, channel: 0)
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

/// Bundled-MIDI playback section. Plays `Sukhkarta_Dukhharta.mid` through
/// the parent's shared `MIDISampler` via `AVMusicTrack.destinationMIDIEndpoint`
/// (CoreMIDI), the routing path that preserves SF2 modulator-driven dynamics
/// on Apple's `AVAudioUnitSampler`. The parent's A↔B segmented control
/// reloads the corresponding SF2 into the shared sampler — A and B both
/// audition through this same MIDI-endpoint route.
@MainActor
private struct AuditionSongPlaybackSection: View {

    enum PlaybackPhase: String {
        case stopped, playing, paused
    }

    /// One bundled song's resource metadata.
    /// `id` is the resource base name shared by `.mid`, `.mxl`, and `.mp3`.
    struct BundledSong: Identifiable, Hashable {
        let id: String
        let displayName: String
        let hasMP3: Bool
        let multiInstrument: Bool
    }

    /// All audition songs. Add an entry here to make a new song selectable.
    private static let songs: [BundledSong] = [
        BundledSong(
            id: "Sukhkarta_Dukhharta",
            displayName: "Sukhkarta Dukhharta",
            hasMP3: false,
            multiInstrument: false
        ),
        BundledSong(
            id: "james-bond-theme",
            displayName: "James Bond Theme",
            hasMP3: true,
            multiInstrument: true
        ),
    ]

    let sampler: MIDISampler?

    @State private var sequencer: AVAudioSequencer?
    @State private var playState: PlaybackPhase = .stopped
    @State private var songLoadError: String?
    @State private var selectedSong: BundledSong = AuditionSongPlaybackSection.songs[0]
    @State private var mp3Player: AVAudioPlayerNode?
    @State private var mp3File: AVAudioFile?
    @State private var mp3PlayState: PlaybackPhase = .stopped
    @State private var mp3LoadError: String?

    var body: some View {
        Section("Song playback") {
            Picker("Song", selection: $selectedSong) {
                ForEach(Self.songs) { song in
                    Text(song.displayName).tag(song)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedSong) { _, newValue in
                applySongSelection(newValue)
            }
            .accessibilityLabel("Choose audition song")

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
                    Label("Play MIDI", systemImage: "play.fill")
                }
                .disabled(playState == .playing || sequencer == nil)
                .accessibilityLabel("Play MIDI through active bank")

                Button {
                    pauseSong()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .disabled(playState != .playing)
                .accessibilityLabel("Pause MIDI")

                Button {
                    stopSong()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(playState == .stopped)
                .accessibilityLabel("Stop MIDI and reset to start")
            }
            Text(verbatim: "Toggle A↔B above mid-playback to compare banks. Both play through the same MIDI-endpoint route — only the SF2 swaps.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let mp3LoadError {
                Text(verbatim: mp3LoadError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("MP3 error: \(mp3LoadError)")
            }
            HStack(spacing: 16) {
                Button {
                    playMP3()
                } label: {
                    Label("Play MP3", systemImage: "play.fill")
                }
                .disabled(mp3Player == nil || mp3PlayState == .playing)
                .accessibilityLabel("Play original MP3 recording")

                Button {
                    pauseMP3()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
                .disabled(mp3PlayState != .playing)
                .accessibilityLabel("Pause MP3")

                Button {
                    stopMP3()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(mp3PlayState == .stopped)
                .accessibilityLabel("Stop MP3")
            }
            Text(verbatim: "Original recording — no SF2 routing, direct audio playback. Independent of A↔B.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { applySongSelection(selectedSong) }
        .onDisappear {
            teardownSequencer()
            teardownMP3()
        }
    }

    /// Load the chosen song's MP3 if bundled, attach an `AVAudioPlayerNode`
    /// to the shared engine, and prepare it for playback. If the song has
    /// no MP3 (`hasMP3 == false`) or the file is missing, leaves the
    /// player nil so MP3 controls stay disabled.
    private func loadMP3For(_ song: BundledSong) {
        teardownMP3()
        guard song.hasMP3 else { return }
        guard let url = Bundle.main.url(
            forResource: song.id, withExtension: "mp3"
        ) else {
            mp3LoadError = "MP3 not bundled for '\(song.displayName)'"
            return
        }
        let engine = AudioEngineManager.shared.engine
        do {
            let file = try AVAudioFile(forReading: url)
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
            mp3File = file
            mp3Player = player
            mp3LoadError = nil
        } catch {
            mp3LoadError = "MP3 load failed: \(error.localizedDescription)"
        }
    }

    /// Stop, detach, and discard the MP3 player and file.
    private func teardownMP3() {
        mp3Player?.stop()
        if let player = mp3Player {
            AudioEngineManager.shared.engine.detach(player)
        }
        mp3Player = nil
        mp3File = nil
        mp3PlayState = .stopped
    }

    /// Start MP3 playback from the beginning, or resume if paused.
    /// `AVAudioPlayerNode.pause()` preserves render state, so resuming
    /// from `.paused` only requires `play()`. From `.stopped` we must
    /// `scheduleFile` again because `stop()` clears the schedule.
    private func playMP3() {
        guard let mp3Player, let mp3File else { return }
        if mp3PlayState == .paused {
            mp3Player.play()
            mp3PlayState = .playing
            return
        }
        mp3Player.scheduleFile(mp3File, at: nil) { /* completion ignored */ }
        mp3Player.play()
        mp3PlayState = .playing
    }

    private func pauseMP3() {
        mp3Player?.pause()
        mp3PlayState = .paused
    }

    private func stopMP3() {
        mp3Player?.stop()
        mp3PlayState = .stopped
    }

    /// Load the chosen song's MIDI and route every track to the parent's
    /// shared `MIDISampler` via `destinationMIDIEndpoint` (CoreMIDI).
    /// Stops and discards the previous sequencer if any.
    private func loadMIDIFor(_ song: BundledSong) {
        sequencer?.stop()
        sequencer = nil
        playState = .stopped
        guard let url = Bundle.main.url(
            forResource: song.id, withExtension: "mid"
        ) else {
            songLoadError = "MIDI not found for '\(song.displayName)'"
            return
        }
        guard let sampler else {
            songLoadError = "Shared sampler not attached"
            return
        }
        let engine = AudioEngineManager.shared.engine
        do {
            let seq = AVAudioSequencer(audioEngine: engine)
            try seq.load(from: url, options: [])
            for track in seq.tracks {
                track.destinationMIDIEndpoint = sampler.midiIn
            }
            sequencer = seq
            songLoadError = nil
        } catch {
            songLoadError = "Song load failed: \(error.localizedDescription)"
        }
    }

    /// Apply the song selection to both playback paths.
    private func applySongSelection(_ song: BundledSong) {
        loadMIDIFor(song)
        loadMP3For(song)
    }

    private func teardownSequencer() {
        sequencer?.stop()
        sequencer = nil
        playState = .stopped
    }

    private func playSong() {
        guard let sequencer else { return }
        do {
            try sequencer.start()
            playState = .playing
        } catch {
            songLoadError = "Sequencer start failed: \(error.localizedDescription)"
            playState = .stopped
        }
    }

    private func pauseSong() {
        sequencer?.stop()
        playState = .paused
    }

    private func stopSong() {
        sequencer?.stop()
        sequencer?.currentPositionInSeconds = 0
        playState = .stopped
    }
}
#endif
