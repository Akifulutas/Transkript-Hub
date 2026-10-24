import Foundation
import AVFoundation

public enum VideoExtractionError: Error, LocalizedError {
    case fileNotFound(URL)
    case extractionFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Video dosyası bulunamadı: \(url.path)"
        case .extractionFailed(let msg):
            return "Videodan ses ayıklanamadı: \(msg)"
        }
    }
}

public actor VideoAudioExtractor {
    public static let shared = VideoAudioExtractor()
    
    public init() {}
    
    /// Finds ffmpeg executable from common system paths or current environment PATH.
    public static func findFFmpeg() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return c
        }
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.components(separatedBy: ":") {
                let candidate = (dir as NSString).appendingPathComponent("ffmpeg")
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }
    
    /// Extracts audio track from any video or container into a standalone M4A or MP3 file.
    public func extractAudio(from fileURL: URL, destinationDirectory: URL) async throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            throw VideoExtractionError.fileNotFound(fileURL)
        }
        
        try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        
        let baseName = fileURL.deletingPathExtension().lastPathComponent
        let sanitizedBase = OutputWriter.sanitizeFilename(baseName)
        let uniqueID = UUID().uuidString.prefix(8)
        let outputM4A = destinationDirectory.appendingPathComponent("\(sanitizedBase)_\(uniqueID).m4a")
        
        // 1. Native AVAssetExportSession (Fastest hardware-accelerated AAC export for MP4, MOV, M4V)
        let ext = fileURL.pathExtension.lowercased()
        let isNativeAppleContainer = ["mp4", "mov", "m4v"].contains(ext)
        if isNativeAppleContainer {
            let asset = AVURLAsset(url: fileURL)
            if let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) {
                do {
                    if #available(macOS 15.0, *) {
                        try await exportSession.export(to: outputM4A, as: .m4a)
                    } else {
                        exportSession.outputURL = outputM4A
                        exportSession.outputFileType = .m4a
                        await withCheckedContinuation { continuation in
                            exportSession.exportAsynchronously {
                                continuation.resume()
                            }
                        }
                        if exportSession.status != .completed {
                            throw exportSession.error ?? VideoExtractionError.extractionFailed("AVAssetExportSession tamamlanamadı.")
                        }
                    }
                    
                    if fm.fileExists(atPath: outputM4A.path),
                       let attrs = try? fm.attributesOfItem(atPath: outputM4A.path),
                       (attrs[.size] as? Int64 ?? 0) > 0 {
                        Log.info("Extracted audio via AVAssetExportSession: \(outputM4A.lastPathComponent)")
                        return outputM4A
                    }
                } catch {
                    Log.info("AVAssetExportSession failed or timed out: \(error.localizedDescription). Trying FFmpeg fallback...")
                }
            }
        }
        
        // 2. FFmpeg Extraction (Handles MKV, WebM, AVI, FLV, TS, and any custom audio codecs)
        if let ffmpeg = Self.findFFmpeg() {
            let outputMP3 = destinationDirectory.appendingPathComponent("\(sanitizedBase)_\(uniqueID).mp3")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ffmpeg)
            process.arguments = [
                "-y",
                "-i", fileURL.path,
                "-vn",
                "-acodec", "libmp3lame",
                "-q:a", "2",
                outputMP3.path
            ]
            let errPipe = Pipe()
            process.standardError = errPipe
            
            do {
                try process.run()
                process.waitUntilExit()
                
                if process.terminationStatus == 0 && fm.fileExists(atPath: outputMP3.path),
                   let attrs = try? fm.attributesOfItem(atPath: outputMP3.path),
                   (attrs[.size] as? Int64 ?? 0) > 0 {
                    Log.info("Extracted audio via FFmpeg: \(outputMP3.lastPathComponent)")
                    return outputMP3
                }
            } catch {
                Log.error("FFmpeg execution error: \(error.localizedDescription)")
            }
        }
        
        // 3. Last-ditch native attempt for non-standard containers if AVAsset can read them
        if !isNativeAppleContainer {
            let asset = AVURLAsset(url: fileURL)
            if let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) {
                do {
                    if #available(macOS 15.0, *) {
                        try await exportSession.export(to: outputM4A, as: .m4a)
                    } else {
                        exportSession.outputURL = outputM4A
                        exportSession.outputFileType = .m4a
                        await withCheckedContinuation { continuation in
                            exportSession.exportAsynchronously {
                                continuation.resume()
                            }
                        }
                        if exportSession.status != .completed {
                            throw exportSession.error ?? VideoExtractionError.extractionFailed("Son çare AVAssetExportSession başarısız.")
                        }
                    }
                    if fm.fileExists(atPath: outputM4A.path),
                       let attrs = try? fm.attributesOfItem(atPath: outputM4A.path),
                       (attrs[.size] as? Int64 ?? 0) > 0 {
                        return outputM4A
                    }
                } catch {
                    // fall through
                }
            }
        }
        
        throw VideoExtractionError.extractionFailed("Video dosyasından geçerli bir ses izi elde edilemedi (\(fileURL.pathExtension)).")
    }
}
