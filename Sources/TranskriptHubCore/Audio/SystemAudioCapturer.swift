import Foundation
import AVFoundation
import CoreMedia
import ScreenCaptureKit

/// Captures system-wide output audio (Zoom, Meet, Teams, YouTube, …) through ScreenCaptureKit.
/// Requires the "Screen & System Audio Recording" privacy permission.
public final class SystemAudioCapturer: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let sink: RecordingBufferSink
    private let sampleQueue = DispatchQueue(label: "com.transkripthub.systemaudio", qos: .userInitiated)
    private var stream: SCStream?
    
    public init(sink: RecordingBufferSink) {
        self.sink = sink
        super.init()
    }
    
    public func start() async throws {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw RecordingEngineError.systemAudioPermissionDenied
        }
        guard let display = content.displays.first else {
            throw RecordingEngineError.engineFailed("Kayıt için bir ekran bulunamadı.")
        }
        
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        // Video is mandatory for SCStream; keep it as cheap as possible.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false
        
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        do {
            try await stream.startCapture()
        } catch {
            if (error as NSError).code == SCStreamError.userDeclined.rawValue {
                throw RecordingEngineError.systemAudioPermissionDenied
            }
            throw RecordingEngineError.engineFailed("Sistem sesi kaydı başlatılamadı: \(error.localizedDescription)")
        }
        self.stream = stream
    }
    
    public func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }
    
    // MARK: SCStreamOutput
    
    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, sampleBuffer.isValid,
              let pcm = Self.makePCMBuffer(from: sampleBuffer) else { return }
        sink.consume(pcm)
    }
    
    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        sink.finish()
    }
    
    private static func makePCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }
}
