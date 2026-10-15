import Foundation
import Accelerate

public struct WaveformPoint: Sendable, Codable, Equatable, Hashable {
    public let min: Float
    public let max: Float
    
    public init(min: Float, max: Float) {
        self.min = min
        self.max = max
    }
}

public enum WaveformError: Error, LocalizedError, Sendable {
    case fileNotFound(URL)
    case unreadable(String)
    case emptyAudio
    case invalidTargetPoints(Int)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Ses dosyası bulunamadı: \(url.path)"
        case .unreadable(let reason):
            return "Dalga formu için ses dosyası okunamadı: \(reason)"
        case .emptyAudio:
            return "Ses dosyası boş (0 frame)."
        case .invalidTargetPoints(let points):
            return "Geçersiz hedef nokta sayısı: \(points). En az 1 olmalıdır."
        }
    }
}

public protocol WaveformGenerating: Sendable {
    func generateWaveform(from audioURL: URL, targetPoints: Int) async throws -> [WaveformPoint]
}

public typealias WaveformGenerator = AccelerateWaveformGenerator

/// High-Performance Accelerate/vDSP Waveform Engine
public final class AccelerateWaveformGenerator: WaveformGenerating, Sendable {
    
    public init() {}
    
    public func generateWaveform(from audioURL: URL, targetPoints: Int) async throws -> [WaveformPoint] {
        guard targetPoints > 0 else {
            throw WaveformError.invalidTargetPoints(targetPoints)
        }
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw WaveformError.fileNotFound(audioURL)
        }
        
        let decoder = AudioDecoder()
        let prepared: PreparedAudio
        do {
            prepared = try decoder.decode(fileURL: audioURL)
        } catch {
            throw WaveformError.unreadable(error.localizedDescription)
        }
        guard !prepared.samples.isEmpty else {
            throw WaveformError.emptyAudio
        }
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
            normalizationFactor = 1.0 / globalMax
        } else if globalMax > 0.0001 {
            normalizationFactor = 1.0 / globalMax
        } else {
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
