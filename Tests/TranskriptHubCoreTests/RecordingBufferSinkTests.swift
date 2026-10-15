import Testing
import Foundation
import AVFoundation
@testable import TranskriptHubCore

@Suite("Recording Buffer Sink & Permission Mapping")
struct RecordingBufferSinkTests {
    private func sineBuffer(frames: AVAudioFrameCount, sampleRate: Double = 48_000, channels: AVAudioChannelCount = 2) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for ch in 0..<Int(channels) {
            let data = buffer.floatChannelData![ch]
            for i in 0..<Int(frames) {
                data[i] = 0.5 * sinf(2 * .pi * 440 * Float(i) / Float(sampleRate))
            }
        }
        return buffer
    }
    
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("sink_\(UUID().uuidString).m4a")
    }
    
    @Test("Writes a readable AAC file and reports meter levels from a background thread")
    func writesReadableFile() async throws {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let meterCount = MeterCounter()
        let sink = RecordingBufferSink(fileURL: url) { level, bands, _ in
            meterCount.record(level: level, bandCount: bands.count)
        }
        
        let buffer = sineBuffer(frames: 4800)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                for _ in 0..<20 { sink.consume(buffer) }
                cont.resume()
            }
        }
        sink.finish()
        
        #expect(sink.hasWrittenAudio)
        #expect(sink.totalFramesWritten == 20 * 4800)
        #expect(sink.writeError == nil)
        #expect(meterCount.calls == 20)
        #expect(meterCount.maxLevel > 0.5)
        #expect(meterCount.lastBandCount == 16)
        
        let file = try AVAudioFile(forReading: url)
        #expect(file.length > 0)
        #expect(file.fileFormat.channelCount == 2)
    }
    
    @Test("Paused or finished sinks drop buffers")
    func pausedAndFinishedDropBuffers() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let sink = RecordingBufferSink(fileURL: url)
        let buffer = sineBuffer(frames: 1024, channels: 1)
        
        sink.setPaused(true)
        sink.consume(buffer)
        #expect(!sink.hasWrittenAudio)
        
        sink.setPaused(false)
        sink.consume(buffer)
        #expect(sink.totalFramesWritten == 1024)
        
        sink.finish()
        sink.consume(buffer)
        #expect(sink.totalFramesWritten == 1024)
    }
    
    @Test("Permission errors name the exact privacy pane to open")
    func permissionMapping() {
        #expect(RecordingEngineError.permissionDenied.missingPermission == .microphone)
        #expect(RecordingEngineError.systemAudioPermissionDenied.missingPermission == .screenAndSystemAudio)
        #expect(RecordingEngineError.noAudioCaptured.missingPermission == nil)
        #expect(RecordingPermissionKind.microphone.settingsURL.absoluteString.hasSuffix("Privacy_Microphone"))
        #expect(RecordingPermissionKind.screenAndSystemAudio.settingsURL.absoluteString.hasSuffix("Privacy_ScreenCapture"))
        #expect(RecordingEngineError.systemAudioPermissionDenied.errorDescription?.contains("Ekran ve Sistem Sesi Kaydı") == true)
    }
}

private final class MeterCounter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls = 0
    private(set) var maxLevel: Float = 0
    private(set) var lastBandCount = 0
    
    func record(level: Float, bandCount: Int) {
        lock.lock(); defer { lock.unlock() }
        calls += 1
        maxLevel = max(maxLevel, level)
        lastBandCount = bandCount
    }
}
