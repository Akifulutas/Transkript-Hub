import Foundation
import Testing
import Accelerate
@testable import TranskriptHubCore

// MARK: - Interface Contract Types (PROJECT.md)

public struct WaveformPoint: Sendable, Codable, Equatable {
    public let min: Float
    public let max: Float
    
    public init(min: Float, max: Float) {
        self.min = min
        self.max = max
    }
}

public protocol WaveformGenerating: Sendable {
    func generateWaveform(from audioURL: URL, targetPoints: Int) async throws -> [WaveformPoint]
}

// MARK: - High-Performance Accelerate/vDSP Waveform Engine Harness

public final class AccelerateWaveformGenerator: WaveformGenerating, Sendable {
    
    public init() {}
    
    public func generateWaveform(from audioURL: URL, targetPoints: Int) async throws -> [WaveformPoint] {
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw AudioDecoderError.fileNotFound(audioURL)
        }
        
        let decoder = AudioDecoder()
        let prepared = try decoder.decode(fileURL: audioURL)
        return generateWaveform(from: prepared.samples, targetPoints: targetPoints)
    }
    
    /// Pure Accelerate/vDSP downsampling and normalization
    public func generateWaveform(from samples: [Float], targetPoints: Int) -> [WaveformPoint] {
        guard targetPoints > 0 else { return [] }
        guard !samples.isEmpty else {
            return (0..<targetPoints).map { _ in WaveformPoint(min: 0.0, max: 0.0) }
        }
        
        let sampleCount = samples.count
        
        // Handle case where samples are fewer than target points
        if sampleCount < targetPoints {
            var points: [WaveformPoint] = []
            points.reserveCapacity(targetPoints)
            for i in 0..<targetPoints {
                let sampleIndex = min(sampleCount - 1, Int(Double(i) * Double(sampleCount) / Double(targetPoints)))
                let rawVal = samples[sampleIndex]
                let val = (rawVal.isNaN || rawVal.isInfinite) ? 0.0 : min(1.0, max(0.0, abs(rawVal)))
                points.append(WaveformPoint(min: 0.0, max: val))
            }
            return points
        }
        
        let samplesPerPoint = sampleCount / targetPoints
        var rawMaxMagnitudes = [Float](repeating: 0.0, count: targetPoints)
        var rawMinMagnitudes = [Float](repeating: 0.0, count: targetPoints)
        
        samples.withUnsafeBufferPointer { sampleBuffer in
            guard let baseAddress = sampleBuffer.baseAddress else { return }
            
            for i in 0..<targetPoints {
                let offset = i * samplesPerPoint
                let count = (i == targetPoints - 1) ? (sampleCount - offset) : samplesPerPoint
                let chunkPointer = baseAddress.advanced(by: offset)
                
                var maxMag: Float = 0.0
                var rmsVal: Float = 0.0
                
                // Vectorized peak magnitude via vDSP (SIMD accelerated)
                vDSP_maxmgv(chunkPointer, 1, &maxMag, vDSP_Length(count))
                // Vectorized RMS energy via vDSP
                vDSP_rmsqv(chunkPointer, 1, &rmsVal, vDSP_Length(count))
                
                rawMaxMagnitudes[i] = (maxMag.isNaN || maxMag.isInfinite) ? 0.0 : maxMag
                rawMinMagnitudes[i] = (rmsVal.isNaN || rmsVal.isInfinite) ? 0.0 : min(maxMag, rmsVal * 0.5)
            }
        }
        
        // Vectorized global maximum for normalization
        var globalMax: Float = 0.0
        vDSP_maxv(rawMaxMagnitudes, 1, &globalMax, vDSP_Length(targetPoints))
        
        let normalizationFactor: Float
        if globalMax > 1.0 {
            // Signal clipped or scaled: normalize so max is 1.0
            normalizationFactor = 1.0 / globalMax
        } else if globalMax > 0.0001 {
            // Normal range: scale to utilize full envelope
            normalizationFactor = 1.0 / globalMax
        } else {
            // Complete silence
            normalizationFactor = 0.0
        }
        
        var points: [WaveformPoint] = []
        points.reserveCapacity(targetPoints)
        
        for i in 0..<targetPoints {
            let normalizedMax = min(1.0, max(0.0, rawMaxMagnitudes[i] * normalizationFactor))
            let normalizedMin = min(normalizedMax, max(0.0, rawMinMagnitudes[i] * normalizationFactor))
            points.append(WaveformPoint(min: normalizedMin, max: normalizedMax))
        }
        
        return points
    }
}

// MARK: - Test Suite

@Suite("Accelerate/vDSP Waveform Generator E2E Test Suite")
struct WaveformGeneratorE2ETests {
    
    @Test("vDSP Waveform generation latency is strictly under 15 milliseconds for 60s audio")
    func testWaveformLatencyUnder15Milliseconds() throws {
        let generator = AccelerateWaveformGenerator()
        
        // 60 seconds of 16kHz audio = 960,000 float samples
        let sampleRate: Int = 16000
        let durationSeconds: Int = 60
        let totalSamples = sampleRate * durationSeconds
        
        var syntheticBuffer = [Float](repeating: 0.0, count: totalSamples)
        // Generate multi-frequency modulated speech-like audio
        for i in 0..<totalSamples {
            let t = Double(i) / Double(sampleRate)
            let fundamental = sin(2.0 * .pi * 220.0 * t) // 220 Hz
            let harmonic = sin(2.0 * .pi * 440.0 * t) * 0.5
            let modulation = sin(2.0 * .pi * 2.0 * t) // 2 Hz envelope
            syntheticBuffer[i] = Float(max(-1.0, min(1.0, (fundamental + harmonic) * modulation * 0.8)))
        }
        
        let clock = ContinuousClock()
        let targetPoints = 500
        
        let elapsed = clock.measure {
            let points = generator.generateWaveform(from: syntheticBuffer, targetPoints: targetPoints)
            #expect(points.count == targetPoints)
        }
        
        let elapsedMillis = Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0
        #expect(elapsed < .milliseconds(15), "vDSP waveform calculation must complete in < 15ms. Actual: \(elapsedMillis)ms")
    }
    
    @Test("Waveform envelope bounds strictly conform to [0.0, 1.0] with min <= max")
    func testWaveformEnvelopeBoundsZeroToOne() throws {
        let generator = AccelerateWaveformGenerator()
        let sampleCount = 50000
        var testSamples = [Float](repeating: 0.0, count: sampleCount)
        
        for i in 0..<sampleCount {
            testSamples[i] = Float.random(in: -1.0...1.0)
        }
        
        let points = generator.generateWaveform(from: testSamples, targetPoints: 200)
        #expect(points.count == 200)
        
        for (idx, point) in points.enumerated() {
            #expect(point.min >= 0.0, "Point \(idx) min \(point.min) must be >= 0.0")
            #expect(point.max <= 1.0, "Point \(idx) max \(point.max) must be <= 1.0")
            #expect(point.min <= point.max, "Point \(idx) min \(point.min) must be <= max \(point.max)")
        }
    }
    
    @Test("Digital silence buffer produces [0.0, 0.0] points without NaN or crash")
    func testDigitalSilenceEnvelope() throws {
        let generator = AccelerateWaveformGenerator()
        let silentSamples = [Float](repeating: 0.0, count: 10000)
        
        let points = generator.generateWaveform(from: silentSamples, targetPoints: 50)
        #expect(points.count == 50)
        
        for point in points {
            #expect(point.min == 0.0)
            #expect(point.max == 0.0)
        }
    }
    
    @Test("Extreme clipped signal is clamped cleanly to 1.0 without overflow")
    func testExtremeClippedSignalClamping() throws {
        let generator = AccelerateWaveformGenerator()
        // Clipped signal with massive amplitudes up to ±5.0
        let clippedSamples: [Float] = [5.0, -4.5, 3.2, -5.0, 4.0, 2.5, -3.8]
        
        let points = generator.generateWaveform(from: clippedSamples, targetPoints: 10)
        #expect(points.count == 10)
        
        for point in points {
            #expect(point.max <= 1.0)
            #expect(point.min >= 0.0)
            #expect(point.min <= point.max)
        }
    }
    
    @Test("DC Offset handling prevents numeric distortion outside [0.0, 1.0]")
    func testDcOffsetHandlingAndRemoval() throws {
        let generator = AccelerateWaveformGenerator()
        // Strong positive DC offset (+0.9) with tiny ripple
        let dcSamples = (0..<1000).map { i in 0.9 + 0.05 * sin(Float(i)) }
        
        let points = generator.generateWaveform(from: dcSamples, targetPoints: 20)
        #expect(points.count == 20)
        
        for point in points {
            #expect(point.min >= 0.0)
            #expect(point.max <= 1.0)
            #expect(point.min <= point.max)
        }
    }
    
    @Test("Dynamic target points scaling strictly matches requested counts")
    func testTargetPointsExactCountMatching() throws {
        let generator = AccelerateWaveformGenerator()
        let samples = (0..<5000).map { _ in Float.random(in: -0.5...0.5) }
        
        for target in [1, 10, 64, 128, 500, 1000] {
            let points = generator.generateWaveform(from: samples, targetPoints: target)
            #expect(points.count == target)
        }
    }
    
    @Test("Minimal sample count (fewer samples than target points) handles safely")
    func testMinimalAudioSampleCountEdgeCase() throws {
        let generator = AccelerateWaveformGenerator()
        let sparseSamples: [Float] = [0.1, -0.3, 0.5]
        
        let points = generator.generateWaveform(from: sparseSamples, targetPoints: 20)
        #expect(points.count == 20)
        
        for point in points {
            #expect(point.min >= 0.0)
            #expect(point.max <= 1.0)
        }
    }
    
    @Test("Waveform generation from local fixture file succeeds")
    func testWaveformGenerationFromFixtureFile() async throws {
        let sampleURL = URL(fileURLWithPath: "Tests/Fixtures/sample.m4a")
        if FileManager.default.fileExists(atPath: sampleURL.path) {
            let generator = AccelerateWaveformGenerator()
            let points = try await generator.generateWaveform(from: sampleURL, targetPoints: 100)
            #expect(points.count == 100)
            #expect(points.contains { $0.max > 0.01 })
        }
    }
}
