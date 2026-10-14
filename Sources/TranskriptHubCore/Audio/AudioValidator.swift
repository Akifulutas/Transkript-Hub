import Foundation
import AVFoundation

public enum AudioValidationError: Error, LocalizedError {
    case fileNotFound(URL)
    case unreadable(String)
    case tooShort(Double)
    case emptyFile
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Ses dosyası bulunamadı: \(url.path)"
        case .unreadable(let msg):
            return "Ses dosyası açılamadı: \(msg)"
        case .tooShort(let dur):
            return "Ses dosyası çok kısa (\(String(format: "%.2f", dur)) sn). En az 1.0 saniye olmalıdır."
        case .emptyFile:
            return "Ses dosyası boş (0 bayt)."
        }
    }
}

public enum AudioValidator {
    public static let allowedExtensions: Set<String> = [
        "m4a", "mp3", "wav", "aac", "caf", "aiff", "mp4", "mov"
    ]
    
    public static func isExtensionSupported(_ ext: String) -> Bool {
        allowedExtensions.contains(ext.lowercased())
    }
    
    /// Validates an audio file on disk for non-zero size, valid tracks, and duration > 1.0s.
    public static func validate(fileURL: URL) throws -> Double {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            throw AudioValidationError.fileNotFound(fileURL)
        }
        
        let attrs = try fm.attributesOfItem(atPath: fileURL.path)
        let size = attrs[.size] as? Int64 ?? 0
        guard size > 0 else {
            throw AudioValidationError.emptyFile
        }
        
        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let frames = audioFile.length
            let sampleRate = audioFile.processingFormat.sampleRate
            guard sampleRate > 0 else {
                throw AudioValidationError.unreadable("Geçersiz örnekleme frekansı (0 Hz).")
            }
            let duration = Double(frames) / sampleRate
            guard duration >= 1.0 else {
                throw AudioValidationError.tooShort(duration)
            }
            return duration
        } catch let err as AudioValidationError {
            throw err
        } catch {
            throw AudioValidationError.unreadable(error.localizedDescription)
        }
    }
}
