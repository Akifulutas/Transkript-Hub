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
    public static let allowedAudioExtensions: Set<String> = [
        "m4a", "mp3", "wav", "aac", "caf", "aiff", "flac", "ogg", "wma", "alac"
    ]
    
    public static let allowedVideoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "flv", "wmv", "ts", "3gp"
    ]
    
    public static let allowedExtensions: Set<String> = allowedAudioExtensions.union(allowedVideoExtensions)
    
    public static func isExtensionSupported(_ ext: String) -> Bool {
        allowedExtensions.contains(ext.lowercased())
    }
    
    public static func isVideoExtension(_ ext: String) -> Bool {
        allowedVideoExtensions.contains(ext.lowercased())
    }
    
    /// Validates an audio or video file on disk for non-zero size, valid tracks, and duration > 0.5s.
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
        
        let ext = fileURL.pathExtension.lowercased()
        
        // 1. Audio files: fast-path via AVAudioFile
        if !isVideoExtension(ext) {
            if let dur = try? durationViaAudioFile(fileURL: fileURL) {
                return dur
            }
        }
        
        // 2. Video / Apple-compatible containers via AVURLAsset
        let asset = AVURLAsset(url: fileURL)
        let assetDur = CMTimeGetSeconds(asset.duration)
        if assetDur.isFinite && assetDur >= 0.5 {
            return assetDur
        }
        
        // 3. Fallback: FFprobe duration (e.g. for MKV, WebM, AVI)
        if let probeDur = durationViaFFprobe(fileURL: fileURL), probeDur >= 0.5 {
            return probeDur
        }
        
        // 4. Default attempt via AVAudioFile (provides localized typed errors if unreadable)
        return try durationViaAudioFile(fileURL: fileURL)
    }
    
    private static func durationViaAudioFile(fileURL: URL) throws -> Double {
        do {
            let audioFile = try AVAudioFile(forReading: fileURL)
            let frames = audioFile.length
            let sampleRate = audioFile.processingFormat.sampleRate
            guard sampleRate > 0 else {
                throw AudioValidationError.unreadable("Geçersiz örnekleme frekansı (0 Hz).")
            }
            let duration = Double(frames) / sampleRate
            guard duration >= 0.5 else {
                throw AudioValidationError.tooShort(duration)
            }
            return duration
        } catch let err as AudioValidationError {
            throw err
        } catch {
            throw AudioValidationError.unreadable(error.localizedDescription)
        }
    }
    
    private static func durationViaFFprobe(fileURL: URL) -> Double? {
        let candidates = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]
        var probePath = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        if probePath == nil, let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.components(separatedBy: ":") {
                let candidate = (dir as NSString).appendingPathComponent("ffprobe")
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    probePath = candidate
                    break
                }
            }
        }
        guard let probe = probePath else { return nil }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: probe)
        process.arguments = ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", fileURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               let d = Double(str), d >= 0.5 {
                return d
            }
        } catch {
            return nil
        }
        return nil
    }
}
