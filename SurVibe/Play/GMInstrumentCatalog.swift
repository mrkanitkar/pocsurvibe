import Foundation

/// One of the 16 General MIDI instrument categories. Each contains exactly 8 programs.
public enum GMInstrumentCategory: String, CaseIterable, Hashable, Sendable {
    case piano = "Piano"
    case chromaticPercussion = "Chromatic Percussion"
    case organ = "Organ"
    case guitar = "Guitar"
    case bass = "Bass"
    case strings = "Strings"
    case ensemble = "Ensemble"
    case brass = "Brass"
    case reed = "Reed"
    case pipe = "Pipe"
    case synthLead = "Synth Lead"
    case synthPad = "Synth Pad"
    case synthEffects = "Synth Effects"
    case ethnic = "Ethnic"
    case percussive = "Percussive"
    case soundEffects = "Sound Effects"
}

/// A single GM melodic program (0...127) with display name and category.
public struct GMInstrument: Identifiable, Hashable, Sendable {
    public let program: UInt8
    public let name: String
    public let category: GMInstrumentCategory
    public var id: UInt8 { program }
}

/// Static lookup over the General MIDI 128 program list.
///
/// Programs are partitioned 8-per-category in canonical GM order
/// (https://en.wikipedia.org/wiki/General_MIDI#Program_change_events).
public enum GMInstrumentCatalog {
    /// All 128 programs in program-number order.
    public static let all: [GMInstrument] = [
        // Piano (0-7)
        GMInstrument(program: 0, name: "Acoustic Grand Piano", category: .piano),
        GMInstrument(program: 1, name: "Bright Acoustic Piano", category: .piano),
        GMInstrument(program: 2, name: "Electric Grand Piano", category: .piano),
        GMInstrument(program: 3, name: "Honky-tonk Piano", category: .piano),
        GMInstrument(program: 4, name: "Electric Piano 1", category: .piano),
        GMInstrument(program: 5, name: "Electric Piano 2", category: .piano),
        GMInstrument(program: 6, name: "Harpsichord", category: .piano),
        GMInstrument(program: 7, name: "Clavinet", category: .piano),
        // Chromatic Percussion (8-15)
        GMInstrument(program: 8, name: "Celesta", category: .chromaticPercussion),
        GMInstrument(program: 9, name: "Glockenspiel", category: .chromaticPercussion),
        GMInstrument(program: 10, name: "Music Box", category: .chromaticPercussion),
        GMInstrument(program: 11, name: "Vibraphone", category: .chromaticPercussion),
        GMInstrument(program: 12, name: "Marimba", category: .chromaticPercussion),
        GMInstrument(program: 13, name: "Xylophone", category: .chromaticPercussion),
        GMInstrument(program: 14, name: "Tubular Bells", category: .chromaticPercussion),
        GMInstrument(program: 15, name: "Dulcimer", category: .chromaticPercussion),
        // Organ (16-23)
        GMInstrument(program: 16, name: "Drawbar Organ", category: .organ),
        GMInstrument(program: 17, name: "Percussive Organ", category: .organ),
        GMInstrument(program: 18, name: "Rock Organ", category: .organ),
        GMInstrument(program: 19, name: "Church Organ", category: .organ),
        GMInstrument(program: 20, name: "Reed Organ", category: .organ),
        GMInstrument(program: 21, name: "Accordion", category: .organ),
        GMInstrument(program: 22, name: "Harmonica", category: .organ),
        GMInstrument(program: 23, name: "Tango Accordion", category: .organ),
        // Guitar (24-31)
        GMInstrument(program: 24, name: "Acoustic Guitar (nylon)", category: .guitar),
        GMInstrument(program: 25, name: "Acoustic Guitar (steel)", category: .guitar),
        GMInstrument(program: 26, name: "Electric Guitar (jazz)", category: .guitar),
        GMInstrument(program: 27, name: "Electric Guitar (clean)", category: .guitar),
        GMInstrument(program: 28, name: "Electric Guitar (muted)", category: .guitar),
        GMInstrument(program: 29, name: "Overdriven Guitar", category: .guitar),
        GMInstrument(program: 30, name: "Distortion Guitar", category: .guitar),
        GMInstrument(program: 31, name: "Guitar Harmonics", category: .guitar),
        // Bass (32-39)
        GMInstrument(program: 32, name: "Acoustic Bass", category: .bass),
        GMInstrument(program: 33, name: "Electric Bass (finger)", category: .bass),
        GMInstrument(program: 34, name: "Electric Bass (pick)", category: .bass),
        GMInstrument(program: 35, name: "Fretless Bass", category: .bass),
        GMInstrument(program: 36, name: "Slap Bass 1", category: .bass),
        GMInstrument(program: 37, name: "Slap Bass 2", category: .bass),
        GMInstrument(program: 38, name: "Synth Bass 1", category: .bass),
        GMInstrument(program: 39, name: "Synth Bass 2", category: .bass),
        // Strings (40-47)
        GMInstrument(program: 40, name: "Violin", category: .strings),
        GMInstrument(program: 41, name: "Viola", category: .strings),
        GMInstrument(program: 42, name: "Cello", category: .strings),
        GMInstrument(program: 43, name: "Contrabass", category: .strings),
        GMInstrument(program: 44, name: "Tremolo Strings", category: .strings),
        GMInstrument(program: 45, name: "Pizzicato Strings", category: .strings),
        GMInstrument(program: 46, name: "Orchestral Harp", category: .strings),
        GMInstrument(program: 47, name: "Timpani", category: .strings),
        // Ensemble (48-55)
        GMInstrument(program: 48, name: "String Ensemble 1", category: .ensemble),
        GMInstrument(program: 49, name: "String Ensemble 2", category: .ensemble),
        GMInstrument(program: 50, name: "Synth Strings 1", category: .ensemble),
        GMInstrument(program: 51, name: "Synth Strings 2", category: .ensemble),
        GMInstrument(program: 52, name: "Choir Aahs", category: .ensemble),
        GMInstrument(program: 53, name: "Voice Oohs", category: .ensemble),
        GMInstrument(program: 54, name: "Synth Voice", category: .ensemble),
        GMInstrument(program: 55, name: "Orchestra Hit", category: .ensemble),
        // Brass (56-63)
        GMInstrument(program: 56, name: "Trumpet", category: .brass),
        GMInstrument(program: 57, name: "Trombone", category: .brass),
        GMInstrument(program: 58, name: "Tuba", category: .brass),
        GMInstrument(program: 59, name: "Muted Trumpet", category: .brass),
        GMInstrument(program: 60, name: "French Horn", category: .brass),
        GMInstrument(program: 61, name: "Brass Section", category: .brass),
        GMInstrument(program: 62, name: "Synth Brass 1", category: .brass),
        GMInstrument(program: 63, name: "Synth Brass 2", category: .brass),
        // Reed (64-71)
        GMInstrument(program: 64, name: "Soprano Sax", category: .reed),
        GMInstrument(program: 65, name: "Alto Sax", category: .reed),
        GMInstrument(program: 66, name: "Tenor Sax", category: .reed),
        GMInstrument(program: 67, name: "Baritone Sax", category: .reed),
        GMInstrument(program: 68, name: "Oboe", category: .reed),
        GMInstrument(program: 69, name: "English Horn", category: .reed),
        GMInstrument(program: 70, name: "Bassoon", category: .reed),
        GMInstrument(program: 71, name: "Clarinet", category: .reed),
        // Pipe (72-79)
        GMInstrument(program: 72, name: "Piccolo", category: .pipe),
        GMInstrument(program: 73, name: "Flute", category: .pipe),
        GMInstrument(program: 74, name: "Recorder", category: .pipe),
        GMInstrument(program: 75, name: "Pan Flute", category: .pipe),
        GMInstrument(program: 76, name: "Blown Bottle", category: .pipe),
        GMInstrument(program: 77, name: "Shakuhachi", category: .pipe),
        GMInstrument(program: 78, name: "Whistle", category: .pipe),
        GMInstrument(program: 79, name: "Ocarina", category: .pipe),
        // Synth Lead (80-87)
        GMInstrument(program: 80, name: "Lead 1 (square)", category: .synthLead),
        GMInstrument(program: 81, name: "Lead 2 (sawtooth)", category: .synthLead),
        GMInstrument(program: 82, name: "Lead 3 (calliope)", category: .synthLead),
        GMInstrument(program: 83, name: "Lead 4 (chiff)", category: .synthLead),
        GMInstrument(program: 84, name: "Lead 5 (charang)", category: .synthLead),
        GMInstrument(program: 85, name: "Lead 6 (voice)", category: .synthLead),
        GMInstrument(program: 86, name: "Lead 7 (fifths)", category: .synthLead),
        GMInstrument(program: 87, name: "Lead 8 (bass + lead)", category: .synthLead),
        // Synth Pad (88-95)
        GMInstrument(program: 88, name: "Pad 1 (new age)", category: .synthPad),
        GMInstrument(program: 89, name: "Pad 2 (warm)", category: .synthPad),
        GMInstrument(program: 90, name: "Pad 3 (polysynth)", category: .synthPad),
        GMInstrument(program: 91, name: "Pad 4 (choir)", category: .synthPad),
        GMInstrument(program: 92, name: "Pad 5 (bowed)", category: .synthPad),
        GMInstrument(program: 93, name: "Pad 6 (metallic)", category: .synthPad),
        GMInstrument(program: 94, name: "Pad 7 (halo)", category: .synthPad),
        GMInstrument(program: 95, name: "Pad 8 (sweep)", category: .synthPad),
        // Synth Effects (96-103)
        GMInstrument(program: 96, name: "FX 1 (rain)", category: .synthEffects),
        GMInstrument(program: 97, name: "FX 2 (soundtrack)", category: .synthEffects),
        GMInstrument(program: 98, name: "FX 3 (crystal)", category: .synthEffects),
        GMInstrument(program: 99, name: "FX 4 (atmosphere)", category: .synthEffects),
        GMInstrument(program: 100, name: "FX 5 (brightness)", category: .synthEffects),
        GMInstrument(program: 101, name: "FX 6 (goblins)", category: .synthEffects),
        GMInstrument(program: 102, name: "FX 7 (echoes)", category: .synthEffects),
        GMInstrument(program: 103, name: "FX 8 (sci-fi)", category: .synthEffects),
        // Ethnic (104-111)
        GMInstrument(program: 104, name: "Sitar", category: .ethnic),
        GMInstrument(program: 105, name: "Banjo", category: .ethnic),
        GMInstrument(program: 106, name: "Shamisen", category: .ethnic),
        GMInstrument(program: 107, name: "Koto", category: .ethnic),
        GMInstrument(program: 108, name: "Kalimba", category: .ethnic),
        GMInstrument(program: 109, name: "Bagpipe", category: .ethnic),
        GMInstrument(program: 110, name: "Fiddle", category: .ethnic),
        GMInstrument(program: 111, name: "Shanai", category: .ethnic),
        // Percussive (112-119)
        GMInstrument(program: 112, name: "Tinkle Bell", category: .percussive),
        GMInstrument(program: 113, name: "Agogô", category: .percussive),
        GMInstrument(program: 114, name: "Steel Drums", category: .percussive),
        GMInstrument(program: 115, name: "Woodblock", category: .percussive),
        GMInstrument(program: 116, name: "Taiko Drum", category: .percussive),
        GMInstrument(program: 117, name: "Melodic Tom", category: .percussive),
        GMInstrument(program: 118, name: "Synth Drum", category: .percussive),
        GMInstrument(program: 119, name: "Reverse Cymbal", category: .percussive),
        // Sound Effects (120-127)
        GMInstrument(program: 120, name: "Guitar Fret Noise", category: .soundEffects),
        GMInstrument(program: 121, name: "Breath Noise", category: .soundEffects),
        GMInstrument(program: 122, name: "Seashore", category: .soundEffects),
        GMInstrument(program: 123, name: "Bird Tweet", category: .soundEffects),
        GMInstrument(program: 124, name: "Telephone Ring", category: .soundEffects),
        GMInstrument(program: 125, name: "Helicopter", category: .soundEffects),
        GMInstrument(program: 126, name: "Applause", category: .soundEffects),
        GMInstrument(program: 127, name: "Gunshot", category: .soundEffects),
    ]

    /// Return the display name for a GM program (0...127).
    /// Returns "Unknown" if the program is out of range — the catalog covers all valid GM programs.
    public static func name(for program: UInt8) -> String {
        guard program < 128 else { return "Unknown" }
        return all[Int(program)].name
    }

    /// Return the category for a GM program. Returns `.piano` as a safe default for out-of-range input.
    public static func category(for program: UInt8) -> GMInstrumentCategory {
        guard program < 128 else { return .piano }
        return all[Int(program)].category
    }

    /// Return all 8 instruments in a category, in program-number order.
    public static func entries(in category: GMInstrumentCategory) -> [GMInstrument] {
        all.filter { $0.category == category }
    }
}
