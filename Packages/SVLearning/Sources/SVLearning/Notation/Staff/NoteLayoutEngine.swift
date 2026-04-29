import Foundation

/// A group of notes connected by beams.
///
/// Eighth notes and shorter within the same beat are grouped
/// for beam rendering. The renderer draws a horizontal beam
/// connecting the stems of grouped notes.
public struct BeamGroup: Sendable, Equatable {
    /// Indices into the `NoteLayoutResult.notes` array for notes in this group.
    public let noteIndices: [Int]

    /// Number of beam lines (1 for eighths, 2 for sixteenths).
    public let beamCount: Int
}

/// Complete layout result for a sequence of notes on a staff.
///
/// Contains all the information the renderer needs: positioned notes,
/// beam groups, barline positions, and total width.
public struct NoteLayoutResult: Sendable, Equatable {
    /// Notes with all visual properties and positions computed.
    public let notes: [StaffNoteInfo]

    /// Groups of notes that should be connected by beams.
    public let beamGroups: [BeamGroup]

    /// X-positions where barlines should be drawn.
    public let barlinePositions: [Double]

    /// Total content width in points (for scroll view sizing).
    public let totalWidth: Double

    /// Number of measures in the layout.
    public let measureCount: Int
}

/// Transforms raw note data into a fully laid-out staff notation sequence.
///
/// The layout pipeline:
/// 1. Convert each note to `StaffNoteInfo` with vertical position and notehead type.
/// 2. Resolve accidentals per measure using `AccidentalResolver`.
/// 3. Assign horizontal x-positions with proportional spacing.
/// 4. Assign measure numbers and compute barline positions.
/// 5. Group eligible notes into beam groups.
///
/// ## Usage
/// ```swift
/// let result = NoteLayoutEngine.layout(
///     midiNumbers: notes.map(\.midiNumber),
///     noteNames: notes.map(\.note),
///     durations: notes.map(\.duration),
///     keySignature: .cMajor,
///     timeSignature: .fourFour
/// )
/// ```
public enum NoteLayoutEngine {

    // MARK: - Configuration Constants

    /// Base horizontal spacing per quarter-note beat.
    private static let baseSpacing: Double = 40.0

    /// Minimum spacing between notes (points).
    private static let minimumSpacing: Double = 25.0

    /// Left margin before the first note (space for clef, key sig, time sig).
    private static let leftMargin: Double = 80.0

    /// Right margin after the last note.
    private static let rightMargin: Double = 30.0

    // MARK: - Public Methods

    /// Lay out a sequence of notes for staff notation rendering.
    ///
    /// Takes parallel arrays of note data and produces a complete
    /// `NoteLayoutResult` with positioned notes, beam groups, and barlines.
    ///
    /// - Parameters:
    ///   - midiNumbers: MIDI note numbers for each note.
    ///   - noteNames: Western note names for each note.
    ///   - durations: Durations in beats for each note.
    ///   - keySignature: Key signature for accidental resolution.
    ///   - timeSignature: Time signature for measure assignment.
    ///   - clef: Clef whose bottom line is the position-0 reference for
    ///     `staffYOffset`, `stemDirection`, and `ledgerLines`. Defaults to
    ///     `.treble` for source compatibility.
    /// - Returns: A complete layout result for rendering.
    public static func layout(
        midiNumbers: [Int],
        noteNames: [String],
        durations: [Double],
        keySignature: KeySignature,
        timeSignature: TimeSignature,
        clef: StaffClef = .treble
    ) -> NoteLayoutResult {
        guard !midiNumbers.isEmpty else {
            return NoteLayoutResult(
                notes: [],
                beamGroups: [],
                barlinePositions: [],
                totalWidth: leftMargin + rightMargin,
                measureCount: 0
            )
        }

        // Step 1: Create StaffNoteInfo for each note with initial accidental pass
        var notes = createNoteInfos(
            midiNumbers: midiNumbers,
            noteNames: noteNames,
            durations: durations,
            keySignature: keySignature,
            clef: clef
        )

        // Step 2: Assign x-positions with proportional spacing
        notes = assignXPositions(notes: notes)

        // Step 3: Assign measures and compute barlines
        let measureLayout = MeasureCalculator.assignMeasures(
            notes: notes,
            timeSignature: timeSignature
        )
        notes = measureLayout.notes

        // Reset accidentals at measure boundaries
        notes = resolveAccidentalsWithMeasures(
            notes: notes,
            keySignature: keySignature
        )

        // Step 4: Build beam groups
        let beamGroups = buildBeamGroups(
            notes: notes,
            timeSignature: timeSignature
        )

        // Calculate total width
        let lastNoteEnd = notes.last.map { $0.xPosition + spacingForDuration($0.duration) } ?? 0
        let totalWidth = lastNoteEnd + rightMargin

        return NoteLayoutResult(
            notes: notes,
            beamGroups: beamGroups,
            barlinePositions: measureLayout.barlinePositions,
            totalWidth: totalWidth,
            measureCount: measureLayout.measureCount
        )
    }

    // MARK: - Private Methods

    /// Create initial StaffNoteInfo array from raw note data.
    ///
    /// Position math is anchored to `clef`'s bottom line: treble = E4, bass
    /// = G2. The renderer can read `staffYOffset` directly without any
    /// post-hoc clef shift.
    private static func createNoteInfos(
        midiNumbers: [Int],
        noteNames: [String],
        durations: [Double],
        keySignature: KeySignature,
        clef: StaffClef
    ) -> [StaffNoteInfo] {
        let count = min(midiNumbers.count, min(noteNames.count, durations.count))
        var resolver = AccidentalResolver(keySignature: keySignature)
        var notes: [StaffNoteInfo] = []

        for index in 0..<count {
            let midi = midiNumbers[index]
            let name = noteNames[index]
            let duration = durations[index]

            let noteInfo = StaffNoteInfo(
                midiNumber: midi,
                noteName: name,
                duration: duration,
                noteheadType: NoteheadType(duration: duration),
                isDotted: DurationHelper.isDotted(duration: duration),
                staffYOffset: StaffPositionCalculator.staffPosition(midi: midi, clef: clef),
                stemDirection: StaffPositionCalculator.stemDirection(midi: midi, clef: clef),
                ledgerLines: StaffPositionCalculator.ledgerLines(midi: midi, clef: clef),
                accidental: resolver.resolve(midiNumber: midi)
            )
            notes.append(noteInfo)
        }

        return notes
    }

    /// Assign horizontal x-positions based on note durations.
    private static func assignXPositions(notes: [StaffNoteInfo]) -> [StaffNoteInfo] {
        var result = notes
        var xPos = leftMargin

        for index in result.indices {
            result[index].xPosition = xPos
            let spacing = spacingForDuration(result[index].duration)
            xPos += spacing
        }

        return result
    }

    /// Calculate horizontal spacing for a given duration.
    private static func spacingForDuration(_ duration: Double) -> Double {
        max(minimumSpacing, baseSpacing * duration)
    }

    /// Re-resolve accidentals respecting measure boundaries.
    ///
    /// After measure assignment, we need to reset the accidental resolver
    /// at each barline so accidentals don't carry across measures.
    private static func resolveAccidentalsWithMeasures(
        notes: [StaffNoteInfo],
        keySignature: KeySignature
    ) -> [StaffNoteInfo] {
        var result = notes
        var resolver = AccidentalResolver(keySignature: keySignature)
        var currentMeasure = 0

        for index in result.indices {
            if result[index].measureNumber != currentMeasure {
                resolver.resetMeasure()
                currentMeasure = result[index].measureNumber
            }

            let accidental = resolver.resolve(midiNumber: result[index].midiNumber)
            result[index] = StaffNoteInfo(
                midiNumber: result[index].midiNumber,
                noteName: result[index].noteName,
                duration: result[index].duration,
                isRest: result[index].isRest,
                noteheadType: result[index].noteheadType,
                isDotted: result[index].isDotted,
                staffYOffset: result[index].staffYOffset,
                stemDirection: result[index].stemDirection,
                ledgerLines: result[index].ledgerLines,
                accidental: accidental,
                xPosition: result[index].xPosition,
                measureNumber: result[index].measureNumber
            )
        }

        return result
    }

    /// Build beam groups for eighth and sixteenth notes within beat boundaries.
    ///
    /// Notes shorter than a quarter note that are adjacent and within the
    /// same beat are grouped for beam rendering.
    private static func buildBeamGroups(
        notes: [StaffNoteInfo],
        timeSignature: TimeSignature
    ) -> [BeamGroup] {
        var groups: [BeamGroup] = []
        var currentGroup: [Int] = []
        var currentBeamCount = 0
        var beatAccumulator = 0.0
        var currentMeasure = notes.first?.measureNumber ?? 0

        for (index, note) in notes.enumerated() {
            // Reset at measure boundaries
            if note.measureNumber != currentMeasure {
                finalizeGroup(&groups, indices: &currentGroup, beamCount: currentBeamCount)
                currentMeasure = note.measureNumber
                beatAccumulator = 0.0
            }

            let beams = note.noteheadType.beamCount
            if beams > 0 && !note.isRest {
                if currentGroup.isEmpty {
                    // Start a new group
                    currentGroup.append(index)
                    currentBeamCount = beams
                } else {
                    // Check if still within same beat
                    let beatBoundary = beatAccumulator.truncatingRemainder(dividingBy: 1.0) < 0.001
                        && beatAccumulator > 0.001
                    if beatBoundary {
                        // New beat — finalize current group and start new
                        finalizeGroup(&groups, indices: &currentGroup, beamCount: currentBeamCount)
                        currentGroup.append(index)
                        currentBeamCount = beams
                    } else {
                        currentGroup.append(index)
                        currentBeamCount = max(currentBeamCount, beams)
                    }
                }
            } else {
                // Not a beamable note — finalize any pending group
                finalizeGroup(&groups, indices: &currentGroup, beamCount: currentBeamCount)
            }

            beatAccumulator += note.duration
        }

        // Finalize any remaining group
        finalizeGroup(&groups, indices: &currentGroup, beamCount: currentBeamCount)

        return groups
    }

    /// Finalize a beam group if it has 2 or more notes.
    private static func finalizeGroup(
        _ groups: inout [BeamGroup],
        indices: inout [Int],
        beamCount: Int
    ) {
        if indices.count >= 2 {
            groups.append(BeamGroup(noteIndices: indices, beamCount: beamCount))
        }
        indices.removeAll()
    }
}
