import Foundation
import Testing
import Accelerate
@testable import TranskriptHubCore

@Suite("Accelerate Waveform Generator Dedicated Unit Test Suite")
struct WaveformGeneratorTests {
    
    @Test("WaveformPoint initialization, bounds and Hashable conformance")
    func testWaveformPointModel() {
        let point = TranskriptHubCore.WaveformPoint(min: 0.15, max: 0.85)
        #expect(point.min == 0.15)
        #expect(point.max == 0.85)
        
        let duplicate = TranskriptHubCore.WaveformPoint(min: 0.15, max: 0.85)
        #expect(point == duplicate)
        
        var pointSet: Set<TranskriptHubCore.WaveformPoint> = []
        pointSet.insert(point)
        #expect(pointSet.contains(duplicate))
    }
    
    @Test("WaveformError description messages")
    func testWaveformErrorDescriptions() {
        let missingURL = URL(fileURLWithPath: "/tmp/nonexistent.m4a")
        let notFound = WaveformError.fileNotFound(missingURL)
        #expect(notFound.errorDescription?.contains("bulunamadı") == true)
        
        let unreadable = WaveformError.unreadable("Corrupt audio stream header")
        #expect(unreadable.errorDescription?.contains("Corrupt audio") == true)
        
        let empty = WaveformError.emptyAudio
        #expect(empty.errorDescription?.contains("boş") == true)
        
        let invalidPoints = WaveformError.invalidTargetPoints(0)
        #expect(invalidPoints.errorDescription?.contains("Geçersiz hedef") == true)
    }
    
    @Test("Waveform generation from synthetic audio samples")
    func testGenerateWaveformSyntheticSamples() {
        let generator = TranskriptHubCore.AccelerateWaveformGenerator()
        let sampleCount = 4410
        var samples = [Float](repeating: 0.0, count: sampleCount)
        for i in 0..<sampleCount {
            let t = Double(i) / 44100.0
            samples[i] = Float(sin(2.0 * Double.pi * 440.0 * t))
        }
        
        let points = generator.generateWaveform(from: samples, targetPoints: 40)
        #expect(points.count == 40)
        
        for point in points {
            #expect(point.min >= 0.0)
            #expect(point.max <= 1.0)
            #expect(point.min <= point.max)
            #expect(point.max > 0.1, "Sine wave peak should be normalized close to 1.0")
        }
    }
    
    @Test("Digital silence samples yield zero points without NaN or crash")
    func testGenerateWaveformDigitalSilence() {
        let generator = TranskriptHubCore.AccelerateWaveformGenerator()
        let silentSamples = [Float](repeating: 0.0, count: 2000)
        
        let points = generator.generateWaveform(from: silentSamples, targetPoints: 25)
        #expect(points.count == 25)
        for point in points {
            #expect(point.min == 0.0)
            #expect(point.max == 0.0)
            #expect(!point.min.isNaN)
            #expect(!point.max.isNaN)
        }
    }
    
    @Test("Target points edge cases: empty samples and zero/negative target points")
    func testTargetPointsEdgeCases() {
        let generator = TranskriptHubCore.AccelerateWaveformGenerator()
        
        // Zero target points
        let zeroPoints = generator.generateWaveform(from: [0.5, 0.2], targetPoints: 0)
        #expect(zeroPoints.isEmpty)
        
        // Negative target points
        let negativePoints = generator.generateWaveform(from: [0.5, 0.2], targetPoints: -5)
        #expect(negativePoints.isEmpty)
        
        // Empty samples with positive target points
        let emptySamples = generator.generateWaveform(from: [], targetPoints: 10)
        #expect(emptySamples.count == 10)
        for p in emptySamples {
            #expect(p.min == 0.0 && p.max == 0.0)
        }
        
        // Fewer samples than target points (upsampling safe fallback)
        let sparseSamples: [Float] = [0.8, -0.6]
        let upsampled = generator.generateWaveform(from: sparseSamples, targetPoints: 8)
        #expect(upsampled.count == 8)
        for p in upsampled {
            #expect(p.min >= 0.0 && p.max <= 1.0)
        }
    }
    
    @Test("Audio URL file-not-found and invalid target points errors")
    func testFileErrors() async {
        let generator = TranskriptHubCore.AccelerateWaveformGenerator()
        let missingURL = URL(fileURLWithPath: "/tmp/does_not_exist_\(UUID().uuidString).wav")
        
        // Invalid target points throws before file check
        await #expect(throws: WaveformError.self) {
            _ = try await generator.generateWaveform(from: missingURL, targetPoints: 0)
        }
        
        // Missing file throws fileNotFound
        await #expect(throws: WaveformError.self) {
            _ = try await generator.generateWaveform(from: missingURL, targetPoints: 50)
        }
    }
    
    @Test("Full waveform generation pipeline from actual uncompressed WAV audio file")
    func testWaveformGenerationFromActualWAV() async throws {
        // Create a temporary valid 16-bit PCM mono WAV file
        let sampleRate = 44100
        let durationSeconds = 0.5
        let numSamples = Int(Double(sampleRate) * durationSeconds)
        let subchunk2Size = numSamples * 2
        let chunkSize = 36 + subchunk2Size
        
        var data = Data()
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46]) // "RIFF"
        var cs = UInt32(chunkSize).littleEndian
        data.append(Data(bytes: &cs, count: 4))
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45]) // "WAVE"
        data.append(contentsOf: [0x66, 0x6d, 0x74, 0x20]) // "fmt "
        var sc1 = UInt32(16).littleEndian
        data.append(Data(bytes: &sc1, count: 4))
        var af = UInt16(1).littleEndian
        data.append(Data(bytes: &af, count: 2))
        var nc = UInt16(1).littleEndian
        data.append(Data(bytes: &nc, count: 2))
        var sr = UInt32(sampleRate).littleEndian
        data.append(Data(bytes: &sr, count: 4))
        var br = UInt32(sampleRate * 2).littleEndian
        data.append(Data(bytes: &br, count: 4))
        var ba = UInt16(2).littleEndian
        data.append(Data(bytes: &ba, count: 2))
        var bps = UInt16(16).littleEndian
        data.append(Data(bytes: &bps, count: 2))
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61]) // "data"
        var sc2 = UInt32(subchunk2Size).littleEndian
        data.append(Data(bytes: &sc2, count: 4))
        
        for i in 0..<numSamples {
            let t = Double(i) / Double(sampleRate)
            let s = Int16(sin(2.0 * Double.pi * 440.0 * t) * 28000.0)
            var sampleLE = s.littleEndian
            data.append(Data(bytes: &sampleLE, count: 2))
        }
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let generator = TranskriptHubCore.AccelerateWaveformGenerator()
        let points = try await generator.generateWaveform(from: tempURL, targetPoints: 50)
        
        #expect(points.count == 50)
        #expect(points.contains { $0.max > 0.2 }, "Real audio file should produce non-zero waveform peaks")
        for point in points {
            #expect(point.min >= 0.0)
            #expect(point.max <= 1.0)
            #expect(point.min <= point.max)
        }
    }
}
