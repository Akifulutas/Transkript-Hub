import Foundation
import AVFoundation
import Accelerate

/// Thread-safe audio sink used by real-time capture callbacks (AVAudioEngine taps and
/// ScreenCaptureKit sample handlers). It is intentionally *not* actor-isolated: capture
/// callbacks fire on realtime/background threads, and touching `@MainActor` state from
/// there traps under Swift 6 dynamic isolation checks.
public final class RecordingBufferSink: @unchecked Sendable {
    public typealias MeterHandler = @Sendable (_ level: Float, _ bands: [Float], _ frames: Int) -> Void
    
    public let fileURL: URL
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var isActive = true
    private var isPaused = false
    private var framesWritten: Int64 = 0
    private var lastError: Error?
    private let onMeter: MeterHandler?
    
    public init(fileURL: URL, onMeter: MeterHandler? = nil) {
        self.fileURL = fileURL
        self.onMeter = onMeter
    }
    
    public var totalFramesWritten: Int64 {
        lock.lock(); defer { lock.unlock() }
        return framesWritten
    }
    
    public var hasWrittenAudio: Bool { totalFramesWritten > 0 }
    
    public var writeError: Error? {
        lock.lock(); defer { lock.unlock() }
        return lastError
    }
    
    public func setPaused(_ paused: Bool) {
        lock.lock(); isPaused = paused; lock.unlock()
    }
    
    /// Stops accepting buffers and closes (finalizes) the file.
    public func finish() {
        lock.lock()
        isActive = false
        file = nil
        lock.unlock()
    }
    
    /// Consumes a PCM buffer: lazily creates the AAC file matching the buffer format,
    /// appends the audio, and reports RMS / 16-band levels.
    public func consume(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        
        lock.lock()
        guard isActive, !isPaused else {
            lock.unlock()
            return
        }
        do {
            if file == nil {
                file = try Self.makeFile(at: fileURL, matching: buffer.format)
            }
            try file?.write(from: buffer)
            framesWritten += Int64(buffer.frameLength)
        } catch {
            lastError = error
        }
        lock.unlock()
        
        if let onMeter {
            let (level, bands) = Self.meter(buffer)
            onMeter(level, bands, Int(buffer.frameLength))
        }
    }
    
    private static func makeFile(at url: URL, matching format: AVAudioFormat) throws -> AVAudioFile {
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128_000
        ]
        return try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: format.commonFormat == .otherFormat ? .pcmFormatFloat32 : format.commonFormat,
            interleaved: format.isInterleaved
        )
    }
    
    /// RMS level (0...1) plus 16 time-sliced energy bands via vDSP.
    public static func meter(_ buffer: AVAudioPCMBuffer) -> (Float, [Float]) {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channelData = buffer.floatChannelData?[0] else {
            return (0, Array(repeating: 0, count: 16))
        }
        // Interleaved float buffers keep all channels in channel 0 with a stride.
        let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
        
        var rms: Float = 0
        vDSP_rmsqv(channelData, vDSP_Stride(stride), &rms, vDSP_Length(frameCount))
        let level = normalize(rms)
        
        var bands = [Float](repeating: level, count: 16)
        let chunk = frameCount / 16
        if chunk > 0 {
            for i in 0..<16 {
                var chunkRMS: Float = 0
                vDSP_rmsqv(channelData.advanced(by: i * chunk * stride), vDSP_Stride(stride), &chunkRMS, vDSP_Length(chunk))
                bands[i] = normalize(chunkRMS)
            }
        }
        return (level, bands)
    }
    
    private static func normalize(_ rms: Float) -> Float {
        let dB = 20.0 * log10f(max(rms, 1e-4))
        return max(0.0, min((dB + 50.0) / 50.0, 1.0))
    }
}
