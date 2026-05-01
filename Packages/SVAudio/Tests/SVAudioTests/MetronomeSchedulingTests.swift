import AVFoundation
import Testing

@testable import SVAudio

@Suite("MetronomePlayer AVAudioTime Scheduling Tests")
struct MetronomeSchedulingTests {
    // MARK: - Beat Sample Time Calculation

    @Test("Beat 0 returns the start sample time")
    func beatZeroReturnsStart() {
        let startSample: AVAudioFramePosition = 10000
        let result = MetronomePlayer.sampleTimeForBeat(
            0,
            startSampleTime: startSample,
            sampleRate: 44100,
            bpm: 120
        )
        #expect(result == startSample)
    }

    @Test("Beat sample times at 60 BPM are exactly 1 second apart")
    func beatsAtSixtyBPMOneSecondApart() {
        let sampleRate = 44100.0
        let bpm = 60.0
        let startSample: AVAudioFramePosition = 0

        let beat0 = MetronomePlayer.sampleTimeForBeat(
            0,
            startSampleTime: startSample,
            sampleRate: sampleRate,
            bpm: bpm
        )
        let beat1 = MetronomePlayer.sampleTimeForBeat(
            1,
            startSampleTime: startSample,
            sampleRate: sampleRate,
            bpm: bpm
        )
        let beat2 = MetronomePlayer.sampleTimeForBeat(
            2,
            startSampleTime: startSample,
            sampleRate: sampleRate,
            bpm: bpm
        )

        // At 60 BPM, 1 beat = 1 second = 44100 samples
        #expect(beat1 - beat0 == 44100)
        #expect(beat2 - beat1 == 44100)
    }

    @Test("Beat sample times at 120 BPM are exactly 0.5 seconds apart")
    func beatsAt120BPMHalfSecondApart() {
        let sampleRate = 44100.0
        let bpm = 120.0
        let startSample: AVAudioFramePosition = 0

        let beat0 = MetronomePlayer.sampleTimeForBeat(
            0,
            startSampleTime: startSample,
            sampleRate: sampleRate,
            bpm: bpm
        )
        let beat1 = MetronomePlayer.sampleTimeForBeat(
            1,
            startSampleTime: startSample,
            sampleRate: sampleRate,
            bpm: bpm
        )

        // At 120 BPM, 1 beat = 0.5 seconds = 22050 samples
        #expect(beat1 - beat0 == 22050)
    }

    @Test("All beat intervals are uniform for a given BPM")
    func uniformBeatIntervals() {
        let sampleRate = 44100.0
        let bpm = 90.0
        let startSample: AVAudioFramePosition = 5000
        let expectedInterval = Int64(MusicTime.beatsToSeconds(beats: 1.0, bpm: bpm) * sampleRate)

        var previousSample = MetronomePlayer.sampleTimeForBeat(
            0,
            startSampleTime: startSample,
            sampleRate: sampleRate,
            bpm: bpm
        )

        for beatIndex in 1...100 {
            let currentSample = MetronomePlayer.sampleTimeForBeat(
                beatIndex,
                startSampleTime: startSample,
                sampleRate: sampleRate,
                bpm: bpm
            )
            #expect(currentSample - previousSample == expectedInterval)
            previousSample = currentSample
        }
    }

    @Test("BPM change produces different sample intervals")
    func bpmChangeAffectsInterval() {
        let sampleRate = 44100.0
        let startSample: AVAudioFramePosition = 0

        let interval60 =
            MetronomePlayer.sampleTimeForBeat(
                1,
                startSampleTime: startSample,
                sampleRate: sampleRate,
                bpm: 60
            ) - startSample

        let interval120 =
            MetronomePlayer.sampleTimeForBeat(
                1,
                startSampleTime: startSample,
                sampleRate: sampleRate,
                bpm: 120
            ) - startSample

        // 120 BPM should be exactly half the interval of 60 BPM
        #expect(interval60 == 2 * interval120)
    }

    @Test("Non-zero start sample offsets correctly")
    func nonZeroStartOffset() {
        let sampleRate = 44100.0
        let bpm = 60.0
        let startSample: AVAudioFramePosition = 88200

        let beat1 = MetronomePlayer.sampleTimeForBeat(
            1,
            startSampleTime: startSample,
            sampleRate: sampleRate,
            bpm: bpm
        )

        #expect(beat1 == 88200 + 44100)
    }

    @Test("48000 Hz sample rate calculates correctly")
    func higherSampleRate() {
        let sampleRate = 48000.0
        let bpm = 60.0
        let startSample: AVAudioFramePosition = 0

        let beat1 = MetronomePlayer.sampleTimeForBeat(
            1,
            startSampleTime: startSample,
            sampleRate: sampleRate,
            bpm: bpm
        )

        // At 60 BPM, 1 beat = 1 second = 48000 samples
        #expect(beat1 == 48000)
    }
}
