import Foundation

/// Serialises a `QuantizedScore` to a MusicXML 4.0 partwise document string.
///
/// Format follows W3C MusicXML 4.0 Community Group Final Report (1 June 2021).
/// The DTD declaration is included for maximum compatibility with consumers
/// (MuseScore 4, Finale, Sibelius, Dorico) that haven't moved to the XSD form.
/// NO `xmlns` attribute on the root — MusicXML 4.0 is namespace-free.
///
/// The output is a two-staff piano part: notes with MIDI ≥60 land on staff 1
/// (treble clef), notes <60 land on staff 2 (bass clef). Voice numbers are
/// taken directly from `QuantizedNote.voice` (1 = treble, 2 = bass).
public enum MusicXMLSerializer {

    /// Serialises `score` to a MusicXML 4.0 partwise document.
    ///
    /// - Parameter score: Quantized score (output of `Quantizer.quantize`).
    /// - Returns: A complete, well-formed MusicXML 4.0 document string,
    ///   ready to be written to disk or wrapped into an `.mxl` container.
    public static func serialize(score: QuantizedScore) -> String {
        var out = ""
        out += #"<?xml version="1.0" encoding="UTF-8" standalone="no"?>"# + "\n"
        out += #"<!DOCTYPE score-partwise PUBLIC "-//Recordare//DTD MusicXML 4.0 Partwise//EN" "http://www.musicxml.org/dtds/partwise.dtd">"# + "\n"
        out += #"<score-partwise version="4.0">"# + "\n"
        out += "  <part-list>\n"
        out += #"    <score-part id="P1"><part-name>Piano</part-name></score-part>"# + "\n"
        out += "  </part-list>\n"
        out += #"  <part id="P1">"# + "\n"

        // 4 divisions per quarter note (so a 16th = 1 division, a 32nd = 0.5 — we
        // round triplets/32nds to the nearest division).
        let divisions = 4
        for (idx, measure) in score.measures.enumerated() {
            out += #"    <measure number="\#(measure.number)">"# + "\n"
            if idx == 0 {
                out += renderAttributes(score: score, divisions: divisions)
            }
            let sorted = measure.notes.sorted(by: { ($0.startBeat, $0.voice) < ($1.startBeat, $1.voice) })
            for note in sorted {
                out += renderNote(note, divisions: divisions)
            }
            out += "    </measure>\n"
        }

        out += "  </part>\n"
        out += "</score-partwise>\n"
        return out
    }

    /// Emits the first-measure `<attributes>` block plus a tempo `<direction>`.
    private static func renderAttributes(score: QuantizedScore, divisions: Int) -> String {
        var out = "      <attributes>\n"
        out += "        <divisions>\(divisions)</divisions>\n"
        out += "        <key><fifths>0</fifths></key>\n"
        let num = score.timeSignature.numerator
        let den = score.timeSignature.denominator
        out += "        <time><beats>\(num)</beats><beat-type>\(den)</beat-type></time>\n"
        out += "        <staves>2</staves>\n"
        out += #"        <clef number="1"><sign>G</sign><line>2</line></clef>"# + "\n"
        out += #"        <clef number="2"><sign>F</sign><line>4</line></clef>"# + "\n"
        out += "      </attributes>\n"
        var direction = #"      <direction placement="above"><direction-type>"#
        direction += "<metronome><beat-unit>quarter</beat-unit>"
        direction += "<per-minute>\(score.bpm)</per-minute></metronome>"
        direction += "</direction-type></direction>\n"
        out += direction
        return out
    }

    /// Emits a single `<note>` element with pitch, duration, voice, type, staff,
    /// and optional `<dot/>` / `<time-modification>` for dotted/triplet variants.
    private static func renderNote(_ note: QuantizedNote, divisions: Int) -> String {
        let pitch = midiToPitch(note.midi)
        let durationDivs = max(1, Int((note.duration.beats * Double(divisions)).rounded()))
        let staffNum = note.staff == .treble ? 1 : 2
        var out = "      <note>\n"
        out += "        <pitch><step>\(pitch.step)</step>"
        if pitch.alter != 0 { out += "<alter>\(pitch.alter)</alter>" }
        out += "<octave>\(pitch.octave)</octave></pitch>\n"
        out += "        <duration>\(durationDivs)</duration>\n"
        out += "        <voice>\(note.voice)</voice>\n"
        out += "        <type>\(note.duration.musicXMLTypeName)</type>\n"
        if note.duration.isDotted { out += "        <dot/>\n" }
        if note.duration.isTriplet {
            var mod = "        <time-modification>"
            mod += "<actual-notes>3</actual-notes>"
            mod += "<normal-notes>2</normal-notes>"
            mod += "</time-modification>\n"
            out += mod
        }
        out += "        <staff>\(staffNum)</staff>\n"
        out += "      </note>\n"
        return out
    }

    /// A pitch decomposed for MusicXML emission.
    private struct Pitch {
        let step: String
        let alter: Int
        let octave: Int
    }

    /// Maps a MIDI note number to a MusicXML `<pitch>` decomposition using
    /// sharps for accidentals (matches piano default; flats are not used).
    ///
    /// MIDI 60 → C4. MIDI 0 → C-1. The standard MIDI octave convention.
    private static func midiToPitch(_ midi: UInt8) -> Pitch {
        let names: [(step: String, alter: Int)] = [
            ("C", 0), ("C", 1), ("D", 0), ("D", 1), ("E", 0), ("F", 0),
            ("F", 1), ("G", 0), ("G", 1), ("A", 0), ("A", 1), ("B", 0),
        ]
        let pitchClass = Int(midi) % 12
        let octave = Int(midi) / 12 - 1
        let entry = names[pitchClass]
        return Pitch(step: entry.step, alter: entry.alter, octave: octave)
    }
}
