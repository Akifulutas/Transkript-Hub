import Foundation
import Testing
import Accelerate
@testable import TranskriptHubCore

@Suite("Challenger 2 Empirical Verification & Stress Test Suite")
struct ChallengerEmpiricalTests {
    
    // MARK: - 1. AccelerateWaveformGenerator Latency Stress Tests
    
    @Test("WaveformGenerator Latency: 60s audio at 16kHz, 44.1kHz, and 48kHz (<15ms)")
    func testWaveformLatency60s() {
        let generator = TranskriptHubCore.AccelerateWaveformGenerator()
        let clock = ContinuousClock()
        
        let sampleRates = [16000, 44100, 48000]
        let targetPointConfigurations = [200, 500, 1000]
        
        for sampleRate in sampleRates {
            let totalSamples = sampleRate * 60
            var samples = [Float](repeating: 0.0, count: totalSamples)
            
            // Populate with rich harmonic waveform
            for i in 0..<totalSamples {
                let t = Double(i) / Double(sampleRate)
                samples[i] = Float(sin(2.0 * .pi * 440.0 * t) * 0.7 + sin(2.0 * .pi * 880.0 * t) * 0.3)
            }
            
            for targetPoints in targetPointConfigurations {
                let elapsed = clock.measure {
                    let points = generator.generateWaveform(from: samples, targetPoints: targetPoints)
                    #expect(points.count == targetPoints)
                }
                
                let elapsedMs = Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0
                print("[EMPIRICAL] 60s audio (\(sampleRate)Hz, \(totalSamples) samples) -> \(targetPoints) points: \(elapsedMs) ms")
                #expect(elapsed < .milliseconds(15), "60s audio waveform generation took \(elapsedMs)ms (must be <15ms)")
            }
        }
    }
    
    @Test("WaveformGenerator Latency: 300s (5 minutes) audio at 16kHz, 44.1kHz, and 48kHz (<15ms)")
    func testWaveformLatency300s() {
        let generator = TranskriptHubCore.AccelerateWaveformGenerator()
        let clock = ContinuousClock()
        
        let sampleRates = [16000, 44100, 48000]
        let targetPoints = 500
        
        for sampleRate in sampleRates {
            let totalSamples = sampleRate * 300
            var samples = [Float](repeating: 0.0, count: totalSamples)
            
            for i in 0..<totalSamples {
                let t = Double(i) / Double(sampleRate)
                samples[i] = Float(sin(2.0 * .pi * 300.0 * t) * 0.8)
            }
            
            let elapsed = clock.measure {
                let points = generator.generateWaveform(from: samples, targetPoints: targetPoints)
                #expect(points.count == targetPoints)
            }
            
            let elapsedMs = Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0
            print("[EMPIRICAL] 300s audio (\(sampleRate)Hz, \(totalSamples) samples) -> \(targetPoints) points: \(elapsedMs) ms")
            #expect(elapsed < .milliseconds(15), "300s audio waveform generation took \(elapsedMs)ms (must be <15ms)")
        }
    }
    
    @Test("WaveformGenerator Latency: Large audio buffer (1800s / 30 mins at 16kHz)")
    func testWaveformLatencyLargeBuffer1800s() {
        let generator = TranskriptHubCore.AccelerateWaveformGenerator()
        let clock = ContinuousClock()
        
        // 30 minutes at 16kHz = 28,800,000 samples
        let sampleRate = 16000
        let durationSeconds = 1800
        let totalSamples = sampleRate * durationSeconds
        let samples = [Float](repeating: 0.35, count: totalSamples)
        
        let elapsed = clock.measure {
            let points = generator.generateWaveform(from: samples, targetPoints: 500)
            #expect(points.count == 500)
        }
        
        let elapsedMs = Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0
        print("[EMPIRICAL] 1800s audio (\(sampleRate)Hz, \(totalSamples) samples) -> 500 points: \(elapsedMs) ms")
        // Even for 30 minutes (28.8M samples), vDSP SIMD vectorization should complete in under 50ms
        #expect(elapsed < .milliseconds(50), "30m audio buffer generation took \(elapsedMs)ms")
    }
    
    // MARK: - 2. Edge Waveforms Tests
    
    @Test("Edge Waveforms: Digital silence (all zeros) produces exact [0.0, 0.0] points without NaN/Inf")
    func testEdgeDigitalSilence() {
        let generator = TranskriptHubCore.AccelerateWaveformGenerator()
        
        for sampleCount in [0, 1, 10, 1000, 100_000] {
            let silence = [Float](repeating: 0.0, count: sampleCount)
            for target in [1, 50, 200] {
                let points = generator.generateWaveform(from: silence, targetPoints: target)
                #expect(points.count == target)
                for p in points {
                    #expect(p.min == 0.0)
                    #expect(p.max == 0.0)
                    #expect(!p.min.isNaN)
                    #expect(!p.max.isNaN)
                    #expect(!p.min.isInfinite)
                    #expect(!p.max.isInfinite)
                }
            }
        }
    }
    
    @Test("Edge Waveforms: DC offset (+0.8, +1.0, +10.0, -5.0) normalized cleanly within [0.0, 1.0]")
    func testEdgeDCOffset() {
        let generator = TranskriptHubCore.AccelerateWaveformGenerator()
        
        let offsets: [Float] = [0.8, 1.0, 5.0, 10.0, -0.8, -1.0, -5.0, -10.0]
        for dc in offsets {
            let samples = (0..<1000).map { i in dc + 0.05 * sin(Float(i)) }
            let points = generator.generateWaveform(from: samples, targetPoints: 25)
            #expect(points.count == 25)
            for p in points {
                #expect(p.min >= 0.0, "Min should be >= 0.0 for DC offset \(dc), got \(p.min)")
                #expect(p.max <= 1.0, "Max should be <= 1.0 for DC offset \(dc), got \(p.max)")
                #expect(p.min <= p.max, "Min should be <= max for DC offset \(dc)")
                #expect(!p.min.isNaN && !p.max.isNaN)
            }
        }
        
        // Pure constant DC offset
        let constantDCSamples = [Float](repeating: 0.75, count: 500)
        let dcPoints = generator.generateWaveform(from: constantDCSamples, targetPoints: 20)
        #expect(dcPoints.count == 20)
        for p in dcPoints {
            #expect(p.min >= 0.0 && p.max <= 1.0)
            #expect(p.min <= p.max)
        }
    }
    
    @Test("Edge Waveforms: Extreme clipping (+50.0, -50.0, +1000.0) clamped to 1.0 without overflow")
    func testEdgeClipping() {
        let generator = TranskriptHubCore.AccelerateWaveformGenerator()
        
        let extremeSamples: [Float] = [
            50.0, -50.0, 25.0, -25.0, 1000.0, -1000.0, 0.0, 50.0, -30.0, 100.0
        ]
        
        let points = generator.generateWaveform(from: extremeSamples, targetPoints: 10)
        #expect(points.count == 10)
        for p in points {
            #expect(p.min >= 0.0)
            #expect(p.max <= 1.0)
            #expect(p.min <= p.max)
            #expect(!p.min.isNaN)
            #expect(!p.max.isNaN)
        }
    }
    
    @Test("Edge Waveforms: Single-sample buffer handled safely")
    func testEdgeSingleSampleBuffer() {
        let generator = TranskriptHubCore.AccelerateWaveformGenerator()
        let singleSample: [Float] = [0.85]
        
        // 1 target point: sampleCount == targetPoints (downsampling path with peak normalization)
        let singlePoint = generator.generateWaveform(from: singleSample, targetPoints: 1)
        #expect(singlePoint.count == 1)
        #expect(singlePoint[0].min >= 0.0)
        #expect(singlePoint[0].max <= 1.0)
        #expect(singlePoint[0].min <= singlePoint[0].max)
        #expect(abs(singlePoint[0].max - 1.0) < 0.001) // Normalized peak to 1.0
        #expect(abs(singlePoint[0].min - 0.5) < 0.001) // RMS (0.85) * 0.5 * (1/0.85) = 0.5
        
        // 10 target points: sampleCount < targetPoints (upsampling fallback)
        let multiPoints = generator.generateWaveform(from: singleSample, targetPoints: 10)
        #expect(multiPoints.count == 10)
        for p in multiPoints {
            #expect(p.min == 0.0)
            #expect(abs(p.max - 0.85) < 0.001)
            #expect(p.min <= p.max)
        }
    }
    
    @Test("Edge Waveforms: Target points boundary conditions (0, 1, 10000)")
    func testEdgeTargetPointsBoundaries() {
        let generator = TranskriptHubCore.AccelerateWaveformGenerator()
        let samples: [Float] = (0..<1000).map { Float(sin(Double($0))) }
        
        // 0 target points
        let zeroPoints = generator.generateWaveform(from: samples, targetPoints: 0)
        #expect(zeroPoints.isEmpty)
        
        // Negative target points
        let negativePoints = generator.generateWaveform(from: samples, targetPoints: -50)
        #expect(negativePoints.isEmpty)
        
        // 1 target point
        let onePoint = generator.generateWaveform(from: samples, targetPoints: 1)
        #expect(onePoint.count == 1)
        #expect(onePoint[0].min >= 0.0 && onePoint[0].max <= 1.0)
        #expect(onePoint[0].min <= onePoint[0].max)
        
        // 10,000 target points on small buffer (100 samples)
        let smallSamples = [Float](repeating: 0.5, count: 100)
        let upsampled10k = generator.generateWaveform(from: smallSamples, targetPoints: 10_000)
        #expect(upsampled10k.count == 10_000)
        for p in upsampled10k.prefix(50) {
            #expect(p.min == 0.0 && p.max == 0.5)
        }
        
        // 10,000 target points on large buffer (100,000 samples)
        let largeSamples = (0..<100_000).map { Float(sin(Double($0) * 0.01)) }
        let downsampled10k = generator.generateWaveform(from: largeSamples, targetPoints: 10_000)
        #expect(downsampled10k.count == 10_000)
        for p in downsampled10k.prefix(50) {
            #expect(p.min >= 0.0 && p.max <= 1.0)
            #expect(p.min <= p.max)
        }
    }
    
    @Test("Edge Waveforms: Subnormal values, NaNs, and Infs handled without crash")
    func testEdgeSubnormalAndNaNs() {
        let generator = TranskriptHubCore.AccelerateWaveformGenerator()
        let dirtySamples: [Float] = [
            Float.nan, Float.infinity, -Float.infinity, 0.5, -0.5,
            Float.leastNonzeroMagnitude, Float.leastNormalMagnitude
        ]
        
        // Upsampling path (samples < targetPoints)
        let pointsUpsampled = generator.generateWaveform(from: dirtySamples, targetPoints: 20)
        #expect(pointsUpsampled.count == 20)
        for p in pointsUpsampled {
            #expect(!p.min.isNaN && !p.max.isNaN)
            #expect(!p.min.isInfinite && !p.max.isInfinite)
            #expect(p.min >= 0.0 && p.max <= 1.0)
        }
        
        // Downsampling path (samples >= targetPoints)
        var manyDirty = [Float]()
        for _ in 0..<100 {
            manyDirty.append(contentsOf: dirtySamples)
        }
        let pointsDownsampled = generator.generateWaveform(from: manyDirty, targetPoints: 20)
        #expect(pointsDownsampled.count == 20)
        for p in pointsDownsampled {
            #expect(!p.min.isNaN && !p.max.isNaN)
            #expect(!p.min.isInfinite && !p.max.isInfinite)
            #expect(p.min >= 0.0 && p.max <= 1.0)
        }
    }
    
    // MARK: - 3. Word & Segment BPE Coalescing & Stress Tests
    
    @Test("Word and Segment: BPE Coalescing Simulation with Special Tokens and Empty Strings")
    func testBPECoalescingSimulation() {
        // Mock Whisper token data simulating subwords and special tokens
        struct MockToken {
            let id: Int32
            let text: String
            let t0: Int64
            let t1: Int64
            let p: Float
        }
        
        let eotId: Int32 = 50257
        let mockTokens: [MockToken] = [
            // Segment starts
            MockToken(id: 50258, text: "<|startoftranscript|>", t0: 0, t1: 0, p: 0.99),
            MockToken(id: 50259, text: "<|en|>", t0: 0, t1: 0, p: 0.99),
            MockToken(id: 50260, text: "<|transcribe|>", t0: 0, t1: 0, p: 0.99),
            MockToken(id: 50261, text: "<|notimestamps|>", t0: 0, t1: 0, p: 0.99),
            
            // First word: "Apple" (single token with leading space)
            MockToken(id: 100, text: " Apple", t0: 50, t1: 90, p: 0.98),
            
            // Second word: "Silicon" (split into two BPE tokens: " Sili" + "con")
            MockToken(id: 101, text: " Sili", t0: 100, t1: 130, p: 0.95),
            MockToken(id: 102, text: "con", t0: 130, t1: 170, p: 0.92),
            
            // Empty string and whitespace-only tokens
            MockToken(id: 103, text: "", t0: 170, t1: 170, p: 1.0),
            MockToken(id: 104, text: "   ", t0: 170, t1: 180, p: 1.0),
            
            // Third word: "Performance" (split into three BPE tokens: " Per" + "form" + "ance")
            MockToken(id: 105, text: " Per", t0: 190, t1: 220, p: 0.90),
            MockToken(id: 106, text: "form", t0: 220, t1: 250, p: 0.88),
            MockToken(id: 107, text: "ance", t0: 250, t1: 290, p: 0.94),
            
            // Noise / special timestamp token
            MockToken(id: 108, text: "[_BEG_]", t0: 290, t1: 290, p: 1.0),
            MockToken(id: 109, text: "<|nospeech|>", t0: 290, t1: 300, p: 1.0),
            
            // Fourth word with punctuation: "powerhouse!"
            MockToken(id: 110, text: " powerhouse", t0: 310, t1: 380, p: 0.96),
            MockToken(id: 111, text: "!", t0: 380, t1: 400, p: 0.99),
            
            // End of transcript
            MockToken(id: 50257, text: "<|endoftext|>", t0: 400, t1: 400, p: 1.0),
            MockToken(id: 60000, text: " ShouldBeIgnoredAfterEot", t0: 410, t1: 450, p: 0.5)
        ]
        
        // Run WhisperCppEngine coalescing logic
        var words: [Word] = []
        var currentText = ""
        var currentStart: Double = 0.0
        var currentEnd: Double = 4.0
        var currentConfidences: [Float] = []
        var hasActiveWord = false
        
        func flushCurrentWord() {
            guard hasActiveWord else { return }
            let trimmed = currentText.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                let avgConf = currentConfidences.isEmpty ? 1.0 : currentConfidences.reduce(0, +) / Float(currentConfidences.count)
                words.append(Word(
                    text: trimmed,
                    start: currentStart,
                    end: max(currentStart, currentEnd),
                    confidence: avgConf
                ))
            }
            currentText = ""
            currentConfidences.removeAll()
            hasActiveWord = false
        }
        
        for token in mockTokens {
            if token.id >= eotId { continue }
            let tokenStr = token.text
            guard !tokenStr.isEmpty else { continue }
            
            if tokenStr.hasPrefix("[_") || tokenStr.hasPrefix("<|") || tokenStr.hasSuffix("|>") {
                continue
            }
            
            let tokenStart = token.t0 >= 0 ? Double(token.t0) / 100.0 : 0.0
            let tokenEnd = token.t1 >= 0 ? Double(token.t1) / 100.0 : max(tokenStart, 4.0)
            let confidence = token.p
            
            let trimmed = tokenStr.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flushCurrentWord()
                continue
            }
            
            let startsWithSpace = tokenStr.first?.isWhitespace == true
            if startsWithSpace || !hasActiveWord {
                flushCurrentWord()
                currentText = trimmed
                currentStart = tokenStart
                currentEnd = tokenEnd
                currentConfidences = [confidence]
                hasActiveWord = true
            } else {
                currentText.append(tokenStr)
                currentEnd = max(currentEnd, tokenEnd)
                currentConfidences.append(confidence)
            }
        }
        flushCurrentWord()
        
        #expect(words.count == 4)
        
        // Word 1: "Apple"
        #expect(words[0].text == "Apple")
        #expect(words[0].start == 0.50)
        #expect(words[0].end == 0.90)
        #expect(abs(words[0].confidence - 0.98) < 0.01)
        
        // Word 2: "Silicon" (coalesced from " Sili" + "con")
        #expect(words[1].text == "Silicon")
        #expect(words[1].start == 1.00)
        #expect(words[1].end == 1.70)
        #expect(abs(words[1].confidence - ((0.95 + 0.92) / 2.0)) < 0.01)
        
        // Word 3: "Performance" (coalesced from " Per" + "form" + "ance")
        #expect(words[2].text == "Performance")
        #expect(words[2].start == 1.90)
        #expect(words[2].end == 2.90)
        #expect(abs(words[2].confidence - ((0.90 + 0.88 + 0.94) / 3.0)) < 0.01)
        
        // Word 4: "powerhouse!" (coalesced with punctuation)
        #expect(words[3].text == "powerhouse!")
        #expect(words[3].start == 3.10)
        #expect(words[3].end == 4.00)
    }
    
    @Test("Word and Segment: Empty strings, whitespace interpolation, and zero-duration safety")
    func testWordAndSegmentEmptyAndZeroDuration() {
        // Empty text string interpolation
        let emptyWords = Segment.interpolateWords(for: "", start: 0.0, end: 5.0)
        #expect(emptyWords.isEmpty)
        
        // Whitespace only interpolation
        let whitespaceWords = Segment.interpolateWords(for: "   \t\n   ", start: 0.0, end: 5.0)
        #expect(whitespaceWords.isEmpty)
        
        // Inverted or zero duration interpolation
        let zeroDurationWords = Segment.interpolateWords(for: "Quick test", start: 5.0, end: 5.0)
        #expect(zeroDurationWords.count == 2)
        #expect(zeroDurationWords[0].start == 5.0)
        #expect(zeroDurationWords[0].end >= 5.0)
        
        // Segment with no words
        let emptySegment = Segment(start: 1.0, end: 3.0, text: "No words here", words: [])
        #expect(emptySegment.word(at: 1.5) == nil)
        #expect(emptySegment.duration == 2.0)
        
        // Word with negative duration clamped safely
        let negativeDurationWord = Word(text: "broken", start: 2.0, end: 1.0)
        #expect(negativeDurationWord.duration == 0.0)
        #expect(!negativeDurationWord.contains(time: 1.5))
    }
    
    @Test("Word and Segment: Rapid word-at lookup on 10,000 words scale stress test")
    func testRapidWordAtLookup10000Words() {
        let count = 10_000
        var words: [Word] = []
        words.reserveCapacity(count)
        
        for i in 0..<count {
            let start = Double(i) * 0.5
            let end = start + 0.45
            words.append(Word(text: "word_\(i)", start: start, end: end, confidence: 0.95))
        }
        
        let segment = Segment(
            start: 0.0,
            end: Double(count) * 0.5,
            text: "Huge 10k transcript segment",
            words: words
        )
        
        let clock = ContinuousClock()
        
        // 1,000 rapid lookups at various timestamps across the 10,000 words
        let lookups = 1_000
        let elapsed = clock.measure {
            for q in 0..<lookups {
                let targetTime = Double(q * 9) * 0.5 + 0.2 // Hit exactly inside word_(q*9)
                let found = segment.word(at: targetTime)
                #expect(found != nil)
                #expect(found?.text == "word_\(q * 9)")
            }
        }
        
        let elapsedMs = Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0
        let avgPerLookupUs = (elapsedMs * 1000.0) / Double(lookups)
        print("[EMPIRICAL] 1,000 word(at:) lookups across 10,000 words: total \(elapsedMs) ms, avg \(avgPerLookupUs) µs/lookup")
        
        // Lookup in gaps between words
        let gapHit = segment.word(at: 0.47) // Between 0.45 and 0.50
        #expect(gapHit == nil, "Timestamp in inter-word gap should return nil")
        
        // Lookup before start and after end
        #expect(segment.word(at: -1.0) == nil)
        #expect(segment.word(at: Double(count) * 0.5 + 10.0) == nil)
    }
}
