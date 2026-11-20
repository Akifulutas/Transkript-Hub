import Foundation
import Testing
@testable import TranskriptHubCore

@Suite("AudioVAD Comprehensive Test Suite")
struct AudioVADTests {

    private func makeSineWave(
        amplitude: Float,
        frequency: Double = 440.0,
        duration: Double,
        sampleRate: Double = 16000.0
    ) -> [Float] {
        let count = Int((duration * sampleRate).rounded())
        guard count > 0 else { return [] }
        return (0..<count).map { i in
            let t = Double(i) / sampleRate
            return amplitude * Float(sin(2.0 * Double.pi * frequency * t))
        }
    }

    private func makeDeterministicNoise(
        rms: Float,
        duration: Double,
        sampleRate: Double = 16000.0
    ) -> [Float] {
        let count = Int((duration * sampleRate).rounded())
        guard count > 0 else { return [] }
        // Alternating +/-rms produces exact RMS == rms with zero DC bias
        return (0..<count).map { i in
            (i % 2 == 0) ? rms : -rms
        }
    }

    @Test("SpeechSegment clamps negative start, inverted end, and non-finite inputs")
    func testSpeechSegmentClampingAndCodable() throws {
        let neg = SpeechSegment(start: -1.5, end: 2.0)
        #expect(neg.start == 0.0)
        #expect(neg.end == 2.0)
        #expect(neg.duration == 2.0)

        let inverted = SpeechSegment(start: 3.0, end: 1.0)
        #expect(inverted.start == 3.0)
        #expect(inverted.end == 3.0)
        #expect(inverted.duration == 0.0)

        let nonFinite = SpeechSegment(start: .nan, end: .infinity)
        #expect(nonFinite.start == 0.0)
        #expect(nonFinite.end == 0.0)

        let data = try JSONEncoder().encode(neg)
        let decoded = try JSONDecoder().decode(SpeechSegment.self, from: data)
        #expect(decoded == neg)
    }

    @Test("Empty, sub-frame, and invalid sampleRate inputs return empty segments")
    func testInvalidAndSubFrameInputs() {
        #expect(AudioVAD.detectSpeech(samples: []).isEmpty)
        #expect(AudioVAD.detectSpeech(samples: [Float](repeating: 0.5, count: 16), sampleRate: 16000.0).isEmpty)
        #expect(AudioVAD.detectSpeech(samples: makeSineWave(amplitude: 0.5, duration: 1.0), sampleRate: 0.0).isEmpty)
        #expect(AudioVAD.detectSpeech(samples: makeSineWave(amplitude: 0.5, duration: 1.0), sampleRate: -16000.0).isEmpty)
        #expect(AudioVAD.detectSpeech(samples: makeSineWave(amplitude: 0.5, duration: 1.0), sampleRate: .nan).isEmpty)
    }

    @Test("NaN and Infinity samples are sanitized safely without false detections")
    func testNonFiniteSamplesSanitized() {
        var samples = [Float](repeating: 0.0, count: 16000)
        samples[100] = .nan
        samples[500] = .infinity
        samples[900] = -.infinity

        let segments = AudioVAD.detectSpeech(samples: samples, sampleRate: 16000.0)
        #expect(segments.isEmpty)
    }

    @Test("Pure digital silence and stationary very-low noise are rejected")
    func testSilenceAndLowStationaryNoiseRejected() {
        let silence = [Float](repeating: 0.0, count: 48000)
        #expect(AudioVAD.detectSpeech(samples: silence).isEmpty)

        let lowNoise = makeDeterministicNoise(rms: 0.005, duration: 3.0)
        #expect(AudioVAD.detectSpeech(samples: lowNoise).isEmpty)
    }

    @Test("Continuous sine wave over entire buffer returns single [0.0, T] segment")
    func testContinuousSignalDetectedWithoutNoiseFloorRejection() {
        let duration = 4.0
        let sine = makeSineWave(amplitude: 1.0, duration: duration, sampleRate: 16000.0)
        let segments = AudioVAD.detectSpeech(samples: sine, sampleRate: 16000.0)

        #expect(segments.count == 1)
        #expect(segments[0].start == 0.0)
        #expect(abs(segments[0].end - duration) < 0.001)
    }

    @Test("Single speech burst applies >= 300ms pre-pad and >= 500ms post-pad")
    func testBoundaryPaddingApplied() {
        let silenceBefore = [Float](repeating: 0.0, count: Int(2.0 * 16000.0))
        let burst = makeSineWave(amplitude: 0.5, duration: 2.0)
        let silenceAfter = [Float](repeating: 0.0, count: Int(2.0 * 16000.0))
        let buffer = silenceBefore + burst + silenceAfter

        let segments = AudioVAD.detectSpeech(samples: buffer, sampleRate: 16000.0)
        #expect(segments.count == 1)
        #expect(segments[0].start <= 1.701)
        #expect(segments[0].start >= 1.65)
        #expect(segments[0].end >= 4.499)
        #expect(segments[0].end <= 4.55)
    }

    @Test("Pre-pad at start and post-pad at end clamp cleanly to [0.0, totalDuration]")
    func testBoundaryPaddingClampedToBufferBounds() {
        // Speech at very beginning
        let startBuffer = makeSineWave(amplitude: 0.5, duration: 1.0) + [Float](repeating: 0.0, count: 32000)
        let startSegs = AudioVAD.detectSpeech(samples: startBuffer, sampleRate: 16000.0)
        #expect(startSegs.count == 1)
        #expect(startSegs[0].start == 0.0)

        // Speech at very end with non-frame-aligned trailing samples (+100 samples)
        let endBuffer = [Float](repeating: 0.0, count: 32000) + makeSineWave(amplitude: 0.5, duration: 1.0) + makeSineWave(amplitude: 0.5, duration: 100.0 / 16000.0)
        let expectedDuration = Double(endBuffer.count) / 16000.0
        let endSegs = AudioVAD.detectSpeech(samples: endBuffer, sampleRate: 16000.0)
        #expect(endSegs.count == 1)
        #expect(abs(endSegs[0].end - expectedDuration) < 0.0001)
    }

    @Test("Silence gaps < 800ms bridge into 1 segment while gaps > 800ms split into 2 segments")
    func testSilenceBridgingVsSplittingOrdering() {
        // 500ms gap (< 800ms) -> 1 segment
        let burst1 = makeSineWave(amplitude: 0.5, duration: 1.0)
        let gap500ms = [Float](repeating: 0.0, count: Int(0.5 * 16000.0))
        let burst2 = makeSineWave(amplitude: 0.5, duration: 1.0)
        let pad = [Float](repeating: 0.0, count: 16000)

        let bridgedBuffer = pad + burst1 + gap500ms + burst2 + pad
        let bridgedSegs = AudioVAD.detectSpeech(samples: bridgedBuffer, sampleRate: 16000.0)
        #expect(bridgedSegs.count == 1)

        // 1200ms gap (> 800ms) -> must remain 2 segments even after 300ms + 500ms padding
        let gap1200ms = [Float](repeating: 0.0, count: Int(1.2 * 16000.0))
        let splitBuffer = pad + burst1 + gap1200ms + burst2 + pad
        let splitSegs = AudioVAD.detectSpeech(samples: splitBuffer, sampleRate: 16000.0)
        #expect(splitSegs.count == 2)
        #expect(splitSegs[0].end < splitSegs[1].start)
    }

    @Test("Adaptive threshold isolates speech above background noise floor")
    func testAdaptiveThresholdWithNoiseFloor() {
        let noise1 = makeDeterministicNoise(rms: 0.005, duration: 1.5)
        let speech = makeSineWave(amplitude: 0.56, duration: 1.0) // RMS ~ 0.40
        let noise2 = makeDeterministicNoise(rms: 0.005, duration: 1.5)

        let segments = AudioVAD.detectSpeech(samples: noise1 + speech + noise2, sampleRate: 16000.0)
        #expect(segments.count == 1)
        #expect(segments[0].start >= 1.15 && segments[0].start <= 1.25)
        #expect(segments[0].end >= 2.95 && segments[0].end <= 3.05)
    }

    @Test("Supports non-16kHz sample rates accurately")
    func testNon16kHzSampleRate() {
        let sr = 48000.0
        let buffer = [Float](repeating: 0.0, count: Int(1.0 * sr))
            + makeSineWave(amplitude: 0.5, duration: 1.0, sampleRate: sr)
            + [Float](repeating: 0.0, count: Int(1.0 * sr))

        let segments = AudioVAD.detectSpeech(samples: buffer, sampleRate: sr)
        #expect(segments.count == 1)
        #expect(abs(segments[0].start - 0.7) < 0.03)
        #expect(abs(segments[0].end - 2.5) < 0.03)
    }

    @Test("Continuous quiet-to-moderate speech (RMS 0.02..0.14) is detected without noise-floor self-rejection")
    func testContinuousQuietToModerateSpeechDetected() {
        let duration = 4.0
        for amplitude in [Float(0.03), Float(0.08), Float(0.10), Float(0.15)] {
            let sine = makeSineWave(amplitude: amplitude, duration: duration, sampleRate: 16000.0)
            let segments = AudioVAD.detectSpeech(samples: sine, sampleRate: 16000.0)
            #expect(segments.count == 1, "Continuous sine at amplitude \(amplitude) must not be dropped")
            if let seg = segments.first {
                #expect(seg.start == 0.0)
                #expect(abs(seg.end - duration) < 0.001)
            }
        }
    }

    @Test("Dense speech (92% speech at RMS 0.08 + 8% silence) and modulated speech with 5% silence are preserved")
    func testDenseAndModulatedSpeechPreserved() {
        let sr = 16000.0
        let dense = [Float](repeating: 0.0, count: Int(0.4 * sr))
            + makeDeterministicNoise(rms: 0.08, duration: 9.2, sampleRate: sr)
            + [Float](repeating: 0.0, count: Int(0.4 * sr))
        let denseSegments = AudioVAD.detectSpeech(samples: dense, sampleRate: sr)
        #expect(denseSegments.count == 1)
        if let seg = denseSegments.first {
            #expect(seg.duration >= 9.2)
        }

        // 5% silence + 45% quiet speech (RMS 0.04) + 50% loud speech (RMS 0.10)
        let modulated = [Float](repeating: 0.0, count: Int(0.5 * sr))
            + makeDeterministicNoise(rms: 0.04, duration: 4.5, sampleRate: sr)
            + makeDeterministicNoise(rms: 0.10, duration: 5.0, sampleRate: sr)
        let modSegments = AudioVAD.detectSpeech(samples: modulated, sampleRate: sr)
        #expect(modSegments.count == 1)
        if let seg = modSegments.first {
            #expect(seg.start <= 0.25)
            #expect(seg.end >= 9.99)
        }
    }

    @Test("Single NaN sample inside an active speech frame does not poison frame RMS")
    func testNaNSampleInSpeechFramePreservesSpeech() {
        let sr = 16000.0
        var speech = makeDeterministicNoise(rms: 0.5, duration: 1.0, sampleRate: sr)
        // Inject 1 NaN into every 320-sample (20ms) frame
        for frameStart in stride(from: 0, to: speech.count, by: 320) {
            speech[frameStart] = .nan
        }
        let segments = AudioVAD.detectSpeech(samples: speech, sampleRate: sr)
        #expect(segments.count == 1)
        if let seg = segments.first {
            #expect(seg.start == 0.0)
            #expect(abs(seg.end - 1.0) < 0.001)
        }
    }

    @Test("Single-sample click/impulse in silence is rejected while >=40ms speech is detected")
    func testSingleSampleImpulseRejected() {
        var clickBuffer = [Float](repeating: 0.0, count: 5 * 16000)
        clickBuffer[40000] = 1.0
        #expect(AudioVAD.detectSpeech(samples: clickBuffer, sampleRate: 16000.0).isEmpty)

        // Two consecutive active frames (40ms = 640 samples) must still be detected
        let shortBurst = [Float](repeating: 0.0, count: 16000)
            + makeSineWave(amplitude: 0.3, duration: 0.040, sampleRate: 16000.0)
            + [Float](repeating: 0.0, count: 16000)
        let shortSegments = AudioVAD.detectSpeech(samples: shortBurst, sampleRate: 16000.0)
        #expect(shortSegments.count == 1)
    }

    private func makeBroadbandNoise(
        targetRMS: Float,
        duration: Double,
        sampleRate: Double = 16000.0,
        seed: UInt64 = 0x9E37_79B9_7F4A_7C15
    ) -> [Float] {
        let count = Int((duration * sampleRate).rounded())
        guard count > 0 else { return [] }
        var state = seed
        var raw = [Float](repeating: 0.0, count: count)
        var sumSq: Double = 0.0
        for i in 0..<count {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z = z ^ (z >> 31)
            let unit = Float(Double(z >> 11) / Double(1 << 53)) * 2.0 - 1.0
            raw[i] = unit
            sumSq += Double(unit) * Double(unit)
        }
        let actualRMS = Float(sqrt(sumSq / Double(count)))
        guard actualRMS > 0 else { return raw }
        let scale = targetRMS / actualRMS
        return raw.map { $0 * scale }
    }

    @Test("Probe 1C-2 & 1C-6: Quiet leading speech with 0% silence and loud speech is preserved")
    func testQuietLeadingSpeechWithZeroSilenceAndLoudSpeech() {
        let sr = 16000.0
        for loudRMS in [Float(0.25), Float(0.10)] {
            let buffer = makeDeterministicNoise(rms: 0.020, duration: 1.5, sampleRate: sr)
                + makeDeterministicNoise(rms: loudRMS, duration: 8.5, sampleRate: sr)
            let segments = AudioVAD.detectSpeech(samples: buffer, sampleRate: sr)
            #expect(segments.count == 1)
            if let seg = segments.first {
                #expect(seg.start == 0.0)
                #expect(seg.end >= 9.999)
            }
        }

        // Sine-wave equivalent (RMS 0.020 -> amplitude 0.020 * sqrt(2))
        let sineBuffer = makeSineWave(amplitude: 0.020 * sqrt(2.0), duration: 1.5, sampleRate: sr)
            + makeSineWave(amplitude: 0.25 * sqrt(2.0), duration: 8.5, sampleRate: sr)
        let sineSegments = AudioVAD.detectSpeech(samples: sineBuffer, sampleRate: sr)
        #expect(sineSegments.count == 1)
        if let seg = sineSegments.first {
            #expect(seg.start == 0.0)
            #expect(seg.end >= 9.999)
        }
    }

    @Test("Probe 1C-3: Quiet speech with sub-2% silence (1.5%) and loud speech is preserved")
    func testQuietSpeechWithSub2PercentSilence() {
        let sr = 16000.0
        let buffer = [Float](repeating: 0.0, count: Int(0.15 * sr))
            + makeDeterministicNoise(rms: 0.020, duration: 1.5, sampleRate: sr)
            + makeDeterministicNoise(rms: 0.25, duration: 8.35, sampleRate: sr)
        let segments = AudioVAD.detectSpeech(samples: buffer, sampleRate: sr)
        #expect(segments.count == 1)
        if let seg = segments.first {
            #expect(seg.start == 0.0)
            #expect(seg.end >= 9.999)
        }
    }

    @Test("Probe 1C-5: Trailing quiet speech after loud speech with 0% silence is preserved")
    func testTrailingQuietSpeechWithLoudPrefix() {
        let sr = 16000.0
        let buffer = makeDeterministicNoise(rms: 0.25, duration: 8.5, sampleRate: sr)
            + makeDeterministicNoise(rms: 0.020, duration: 1.5, sampleRate: sr)
        let segments = AudioVAD.detectSpeech(samples: buffer, sampleRate: sr)
        #expect(segments.count == 1)
        if let seg = segments.first {
            #expect(seg.start == 0.0)
            #expect(seg.end >= 9.999)
        }
    }

    @Test("Embedded quiet speech between two loud segments is preserved without splitting")
    func testEmbeddedQuietSpeechBetweenLoudSegments() {
        let sr = 16000.0
        let buffer = makeDeterministicNoise(rms: 0.25, duration: 4.25, sampleRate: sr)
            + makeDeterministicNoise(rms: 0.020, duration: 1.5, sampleRate: sr)
            + makeDeterministicNoise(rms: 0.25, duration: 4.25, sampleRate: sr)
        let segments = AudioVAD.detectSpeech(samples: buffer, sampleRate: sr)
        #expect(segments.count == 1)
        if let seg = segments.first {
            #expect(seg.start == 0.0)
            #expect(seg.end >= 9.999)
        }
    }

    @Test("Quiet Sweep: Quiet speech across 0.012..0.044 RMS with loud tail is preserved")
    func testQuietSpeechDynamicRangeSweepDownToMinRMS() {
        let sr = 16000.0
        for quietRMS in [Float(0.012), Float(0.013), Float(0.015), Float(0.020), Float(0.030), Float(0.040), Float(0.044)] {
            let buffer = makeDeterministicNoise(rms: quietRMS, duration: 1.5, sampleRate: sr)
                + makeDeterministicNoise(rms: 0.25, duration: 8.5, sampleRate: sr)
            let segments = AudioVAD.detectSpeech(samples: buffer, sampleRate: sr)
            #expect(segments.count == 1, "Quiet RMS \(quietRMS) failed count check")
            if let seg = segments.first {
                #expect(seg.start == 0.0, "Quiet RMS \(quietRMS) dropped leading speech: start=\(seg.start)")
                #expect(seg.end >= 9.999, "Quiet RMS \(quietRMS) dropped trailing speech: end=\(seg.end)")
            }
        }

        // Sine wave at RMS 0.015 with loud 0.25 tail
        let sineBuffer = makeSineWave(amplitude: 0.015 * sqrt(2.0), duration: 1.5, sampleRate: sr)
            + makeSineWave(amplitude: 0.25 * sqrt(2.0), duration: 8.5, sampleRate: sr)
        let sineSegs = AudioVAD.detectSpeech(samples: sineBuffer, sampleRate: sr)
        #expect(sineSegs.count == 1)
        if let seg = sineSegs.first {
            #expect(seg.start == 0.0)
            #expect(seg.end >= 9.999)
        }
    }

    @Test("Sub-2% and 5% low stationary noise preserve quiet 0.013 speech alongside loud speech")
    func testLowNoiseWithQuietAndLoudSpeech() {
        let sr = 16000.0
        let sub2Percent = makeDeterministicNoise(rms: 0.005, duration: 0.15, sampleRate: sr)
            + makeDeterministicNoise(rms: 0.013, duration: 1.5, sampleRate: sr)
            + makeDeterministicNoise(rms: 0.25, duration: 8.35, sampleRate: sr)
        let sub2Segs = AudioVAD.detectSpeech(samples: sub2Percent, sampleRate: sr)
        #expect(sub2Segs.count == 1)
        if let seg = sub2Segs.first {
            #expect(seg.start == 0.0)
            #expect(seg.end >= 9.999)
        }

        for noiseRMS in [Float(0.005), Float(0.008)] {
            let fivePercent = makeDeterministicNoise(rms: noiseRMS, duration: 0.5, sampleRate: sr)
                + makeDeterministicNoise(rms: 0.013, duration: 1.5, sampleRate: sr)
                + makeDeterministicNoise(rms: 0.25, duration: 8.0, sampleRate: sr)
            let segs = AudioVAD.detectSpeech(samples: fivePercent, sampleRate: sr)
            #expect(segs.count == 1)
            if let seg = segs.first {
                #expect(seg.start >= 0.15 && seg.start <= 0.25)
                #expect(seg.end >= 9.999)
            }
        }
    }

    @Test("Stationary and broadband sub-speech noise (< 0.012) is rejected cleanly")
    func testElevatedSubSpeechStationaryNoiseRejected() {
        let sr = 16000.0
        for noiseRMS in [Float(0.005), Float(0.008), Float(0.011)] {
            #expect(AudioVAD.detectSpeech(samples: makeDeterministicNoise(rms: noiseRMS, duration: 3.0, sampleRate: sr), sampleRate: sr).isEmpty)
            #expect(AudioVAD.detectSpeech(samples: makeBroadbandNoise(targetRMS: noiseRMS, duration: 3.0, sampleRate: sr), sampleRate: sr).isEmpty)
        }

        let broadbandWithSpeech = makeBroadbandNoise(targetRMS: 0.010, duration: 2.0, sampleRate: sr, seed: 1)
            + makeSineWave(amplitude: 0.25 * sqrt(2.0), duration: 2.0, sampleRate: sr)
            + makeBroadbandNoise(targetRMS: 0.010, duration: 2.0, sampleRate: sr, seed: 2)
        let segs = AudioVAD.detectSpeech(samples: broadbandWithSpeech, sampleRate: sr)
        #expect(segs.count == 1)
        if let seg = segs.first {
            #expect(seg.start >= 1.65 && seg.start <= 1.75)
            #expect(seg.end >= 4.45 && seg.end <= 4.55)
        }
    }

    @Test("Modulated quiet and loud speech separated by 2.0s silence splits cleanly into 2 segments")
    func testModulatedQuietAndLoudSeparatedByTwoSecondSilence() {
        let sr = 16000.0
        let buffer = [Float](repeating: 0.0, count: Int(0.5 * sr))
            + makeDeterministicNoise(rms: 0.015, duration: 4.5, sampleRate: sr)
            + [Float](repeating: 0.0, count: Int(2.0 * sr))
            + makeDeterministicNoise(rms: 0.25, duration: 5.0, sampleRate: sr)
        let segs = AudioVAD.detectSpeech(samples: buffer, sampleRate: sr)
        #expect(segs.count == 2)
        if segs.count == 2 {
            #expect(segs[0].start >= 0.15 && segs[0].start <= 0.25)
            #expect(segs[0].end >= 5.45 && segs[0].end <= 5.55)
            #expect(segs[1].start >= 6.65 && segs[1].start <= 6.75)
            #expect(segs[1].end >= 11.99)
        }
    }
}
