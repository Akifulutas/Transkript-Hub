import Foundation
import AVFoundation

public enum AudioDecoderError: Error, LocalizedError {
    case fileNotFound(URL)
    case unsupportedMedia(String)
    case conversionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Ses dosyası bulunamadı: \(url.path)"
        case .unsupportedMedia(let reason):
            return "Desteklenmeyen veya bozuk ses formatı: \(reason)"
        case .conversionFailed(let reason):
            return "Ses 16 kHz PCM formatına dönüştürülemedi: \(reason)"
        }
    }
}

public final class AudioDecoder: Sendable {
    public static let targetSampleRate: Double = 16000.0
    
    public init() {}
    
    /// Decodes any AVFoundation-compatible audio file into 16 kHz mono Float32 samples.
    public func decode(fileURL: URL) throws -> PreparedAudio {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw AudioDecoderError.fileNotFound(fileURL)
        }
        
        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: fileURL)
        } catch {
            throw AudioDecoderError.unsupportedMedia(error.localizedDescription)
        }
        
        let sourceFormat = audioFile.processingFormat
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioDecoderError.conversionFailed("Hedef ses formatı oluşturulamadı (16kHz mono Float32).")
        }
        
        guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw AudioDecoderError.conversionFailed("AVAudioConverter başlatılamadı.")
        }
        
        guard audioFile.length > 0 && audioFile.length <= Int64(UInt32.max) else {
            throw AudioDecoderError.unsupportedMedia("Ses dosyası geçersiz uzunlukta veya boş (\(audioFile.length) frame).")
        }
        
        let frameCount = AVAudioFrameCount(audioFile.length)
        
        // Output frame estimation for 16kHz
        let ratio = Self.targetSampleRate / sourceFormat.sampleRate
        let estimatedTargetFrames = AVAudioFrameCount(Double(frameCount) * ratio) + 1024
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: estimatedTargetFrames) else {
            throw AudioDecoderError.conversionFailed("Çıktı ses tamponu (PCMBuffer) tahsis edilemedi.")
        }
        
        var error: NSError?
        var readCompleted = false
        var reusableChunkBuffer: AVAudioPCMBuffer? = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: 4096)
        
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            if readCompleted {
                outStatus.pointee = .noDataNow
                return nil
            }
            
            let buffer: AVAudioPCMBuffer
            if let existing = reusableChunkBuffer, existing.frameCapacity >= inNumPackets {
                buffer = existing
                buffer.frameLength = 0
            } else if let newBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: max(inNumPackets, 4096)) {
                reusableChunkBuffer = newBuffer
                buffer = newBuffer
            } else {
                readCompleted = true
                outStatus.pointee = .endOfStream
                return nil
            }
            
            do {
                try audioFile.read(into: buffer)
                if buffer.frameLength == 0 {
                    readCompleted = true
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return buffer
            } catch {
                readCompleted = true
                outStatus.pointee = .endOfStream
                return nil
            }
        }
        
        let status = converter.convert(to: outputBuffer, error: &error, withInputFrom: inputBlock)
        if let error = error {
            throw AudioDecoderError.conversionFailed(error.localizedDescription)
        }
        
        guard status != .error, let channelData = outputBuffer.floatChannelData else {
            throw AudioDecoderError.conversionFailed("Ses verisi Float kanalına dönüştürülemedi.")
        }
        
        let actualFrames = Int(outputBuffer.frameLength)
        guard actualFrames > 0 else {
            throw AudioDecoderError.unsupportedMedia("Dönüştürülen ses verisi 0 örnek içeriyor.")
        }
        
        let floatPointer = channelData[0]
        let samples = Array(UnsafeBufferPointer(start: floatPointer, count: actualFrames))
        let duration = Double(actualFrames) / Self.targetSampleRate
        
        return PreparedAudio(samples: samples, duration: duration)
    }
}
