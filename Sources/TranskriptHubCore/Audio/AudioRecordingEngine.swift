import Foundation
import AVFoundation
import Accelerate

// MARK: - Protocols & Types

@MainActor
public protocol AudioRecordingControlling: AnyObject, ObservableObject {
    var isRecording: Bool { get }
    var isPaused: Bool { get }
    var currentMeteringLevel: Float { get } // 0.0 to 1.0 (RMS dB scaled)
    var frequencyBands: [Float] { get }      // 16 bands via vDSP
    var recordedDuration: Double { get }
    var currentOutputFileURL: URL? { get }
    
    func startRecording() async throws -> URL
    func pauseRecording() throws
    func resumeRecording() throws
    func stopRecording() async throws -> URL
    func cancelRecording() throws
}

public enum RecordingEngineError: Error, LocalizedError, Equatable {
    case alreadyRecording
    case notRecording
    case invalidState(String)
    case permissionDenied
    case bufferAllocationFailed
    case engineFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "Kayıt zaten aktif durumda."
        case .notRecording:
            return "Aktif kayıt bulunmuyor."
        case .invalidState(let msg):
            return "Geçersiz kayıt durumu: \(msg)"
        case .permissionDenied:
            return "Mikrofon izni reddedildi veya erişilemiyor."
        case .bufferAllocationFailed:
            return "Ses tamponu tahsis edilemedi."
        case .engineFailed(let msg):
            return "Ses motoru hatası: \(msg)"
        }
    }
}

public enum RecordingState: String, Sendable, Equatable {
    case idle
    case recording
    case paused
    case stopped
}

// MARK: - Native Audio Recording Engine (AVAudioEngine + vDSP)

@MainActor
public final class AudioRecordingEngine: AudioRecordingControlling {
    @Published public private(set) var state: RecordingState = .idle
    @Published public private(set) var currentMeteringLevel: Float = 0.0
    @Published public private(set) var frequencyBands: [Float] = Array(repeating: 0.0, count: 16)
    @Published public private(set) var recordedDuration: Double = 0.0
    @Published public private(set) var currentOutputFileURL: URL?
    
    public var isRecording: Bool { state == .recording }
    public var isPaused: Bool { state == .paused }
    
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var durationTimer: Timer?
    private let outputDirectory: URL
    public private(set) var capturedFramesCount: Int64 = 0
    private var sampleRate: Double = 44100.0
    
    public init(outputDirectory: URL? = nil) {
        if let customDir = outputDirectory {
            self.outputDirectory = customDir
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            self.outputDirectory = appSupport.appendingPathComponent("TranskriptHub/Recordings", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: self.outputDirectory, withIntermediateDirectories: true)
    }
    
    deinit {
        audioEngine.stop()
    }
    
    public func startRecording() async throws -> URL {
        guard state == .idle || state == .stopped else {
            throw RecordingEngineError.alreadyRecording
        }
        
        #if os(macOS)
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if authStatus == .denied || authStatus == .restricted {
            throw RecordingEngineError.permissionDenied
        }
        if authStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                throw RecordingEngineError.permissionDenied
            }
        }
        #endif
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let fileURL = outputDirectory.appendingPathComponent("Ses_Kaydi_\(timestamp).m4a")
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            throw RecordingEngineError.engineFailed("Geçersiz ses giriş formatı (Mikrofon bağlı değil veya erişilemiyor).")
        }
        
        self.sampleRate = inputFormat.sampleRate
        self.capturedFramesCount = 0
        self.recordedDuration = 0.0
        
        // High quality AAC audio encoding settings
        let recordSettings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: inputFormat.sampleRate,
            AVNumberOfChannelsKey: min(inputFormat.channelCount, 2),
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128_000
        ]
        
        do {
            self.audioFile = try AVAudioFile(forWriting: fileURL, settings: recordSettings)
        } catch {
            throw RecordingEngineError.engineFailed("Ses dosyası oluşturulamadı: \(error.localizedDescription)")
        }
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, when in
            guard let self = self else { return }
            
            let currentState = self.state
            guard currentState == .recording else { return }
            
            if let file = self.audioFile {
                do {
                    try file.write(from: buffer)
                } catch {
                    // Buffer drop on disk full or write error
                }
            }
            
            self.processAudioBuffer(buffer)
        }
        
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            self.audioFile = nil
            throw RecordingEngineError.engineFailed("AVAudioEngine başlatılamadı: \(error.localizedDescription)")
        }
        
        self.currentOutputFileURL = fileURL
        self.state = .recording
        startDurationTimer()
        
        return fileURL
    }
    
    public func pauseRecording() throws {
        guard state == .recording else {
            throw RecordingEngineError.invalidState("Yalnızca kayıt aşamasında duraklatılabilir (Şu an: \(state.rawValue)).")
        }
        audioEngine.pause()
        stopDurationTimer()
        state = .paused
    }
    
    public func resumeRecording() throws {
        guard state == .paused else {
            throw RecordingEngineError.invalidState("Yalnızca duraklatılmış kayıt devam ettirilebilir (Şu an: \(state.rawValue)).")
        }
        do {
            try audioEngine.start()
        } catch {
            throw RecordingEngineError.engineFailed("Kayıt devam ettirilemedi: \(error.localizedDescription)")
        }
        startDurationTimer()
        state = .recording
    }
    
    public func stopRecording() async throws -> URL {
        guard state == .recording || state == .paused else {
            throw RecordingEngineError.notRecording
        }
        
        stopDurationTimer()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        self.audioFile = nil
        
        guard let url = currentOutputFileURL else {
            state = .idle
            throw RecordingEngineError.invalidState("Çıktı dosyası URL'si bulunamadı.")
        }
        
        state = .stopped
        currentMeteringLevel = 0.0
        frequencyBands = Array(repeating: 0.0, count: 16)
        return url
    }
    
    public func cancelRecording() {
        stopDurationTimer()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        self.audioFile = nil
        
        if let url = currentOutputFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        currentOutputFileURL = nil
        currentMeteringLevel = 0.0
        frequencyBands = Array(repeating: 0.0, count: 16)
        recordedDuration = 0.0
        state = .idle
    }
    
    // MARK: - DSP Metering & Spectral Analysis
    
    private nonisolated func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }
        
        // 1. RMS level via vDSP
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameCount))
        let dB = 20.0 * log10f(max(rms, 1e-4))
        let normalizedLevel = max(0.0, min((dB + 50.0) / 50.0, 1.0))
        
        // 2. 16 frequency bands via energy distribution
        var bands = [Float](repeating: 0.0, count: 16)
        let chunkSize = frameCount / 16
        if chunkSize > 0 {
            for i in 0..<16 {
                var chunkRMS: Float = 0.0
                vDSP_rmsqv(channelData.advanced(by: i * chunkSize), 1, &chunkRMS, vDSP_Length(chunkSize))
                let chunkDB = 20.0 * log10f(max(chunkRMS, 1e-4))
                bands[i] = max(0.0, min((chunkDB + 50.0) / 50.0, 1.0))
            }
        } else {
            bands = Array(repeating: normalizedLevel, count: 16)
        }
        
        Task { @MainActor [weak self] in
            guard let self = self, self.state == .recording else { return }
            self.currentMeteringLevel = normalizedLevel
            self.frequencyBands = bands
            self.capturedFramesCount += Int64(frameCount)
        }
    }
    
    // MARK: - Duration Timer
    
    private func startDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.state == .recording else { return }
                self.recordedDuration += 0.1
            }
        }
    }
    
    private func stopDurationTimer() {
        durationTimer?.invalidate()
        durationTimer = nil
    }
}
