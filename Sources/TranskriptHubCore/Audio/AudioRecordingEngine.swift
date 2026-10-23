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

/// Physical input the engine records from.
public enum RecordingInput: String, Sendable, Equatable {
    case microphone
    case systemAudio
}

/// Privacy pane the user must visit to grant a missing permission.
public enum RecordingPermissionKind: Sendable, Equatable {
    case microphone
    case screenAndSystemAudio
    
    public var settingsURL: URL {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        case .screenAndSystemAudio:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        }
    }
}

public enum RecordingEngineError: Error, LocalizedError, Equatable {
    case alreadyRecording
    case notRecording
    case invalidState(String)
    case permissionDenied
    case systemAudioPermissionDenied
    case bufferAllocationFailed
    case noAudioCaptured
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
            return "Mikrofon izni verilmemiş. Sistem Ayarları › Gizlilik ve Güvenlik › Mikrofon bölümünden Transkript Hub'ı açın."
        case .systemAudioPermissionDenied:
            return "Bilgisayar sesini kaydetmek için izin gerekli.\n\nSistem Ayarları › Gizlilik ve Güvenlik › Ekran ve Sistem Sesi Kaydı bölümünden Transkript Hub'ı açın.\n\n⚠️ Eğer izni zaten verdiyseniz: macOS güvenlik kuralı gereği ayarın geçerli olması için uygulamanın yeniden başlatılması gerekmektedir."
        case .bufferAllocationFailed:
            return "Ses tamponu tahsis edilemedi."
        case .noAudioCaptured:
            return "Kayıt sırasında hiç ses yakalanamadı."
        case .engineFailed(let msg):
            return "Ses motoru hatası: \(msg)"
        }
    }
    
    /// The privacy permission that resolves this error, if any.
    public var missingPermission: RecordingPermissionKind? {
        switch self {
        case .permissionDenied: return .microphone
        case .systemAudioPermissionDenied: return .screenAndSystemAudio
        default: return nil
        }
    }
}

public enum RecordingState: String, Sendable, Equatable {
    case idle
    case recording
    case paused
    case stopped
}

// MARK: - Native Audio Recording Engine (AVAudioEngine / ScreenCaptureKit + vDSP)

@MainActor
public final class AudioRecordingEngine: AudioRecordingControlling {
    @Published public private(set) var state: RecordingState = .idle
    @Published public private(set) var currentMeteringLevel: Float = 0.0
    @Published public private(set) var frequencyBands: [Float] = Array(repeating: 0.0, count: 16)
    @Published public private(set) var recordedDuration: Double = 0.0
    @Published public private(set) var currentOutputFileURL: URL?
    @Published public private(set) var activeInput: RecordingInput = .microphone
    
    public var isRecording: Bool { state == .recording }
    public var isPaused: Bool { state == .paused }
    
    private let audioEngine = AVAudioEngine()
    private var sink: RecordingBufferSink?
    private var systemCapturer: SystemAudioCapturer?
    private var durationTimer: Timer?
    private let outputDirectory: URL
    public private(set) var capturedFramesCount: Int64 = 0
    
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
        try await startRecording(input: .microphone)
    }
    
    public func startRecording(input: RecordingInput) async throws -> URL {
        guard state == .idle || state == .stopped else {
            throw RecordingEngineError.alreadyRecording
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())
        let prefix = input == .microphone ? "Ses_Kaydi" : "Sistem_Sesi"
        let fileURL = outputDirectory.appendingPathComponent("\(prefix)_\(timestamp).m4a")
        
        let newSink = RecordingBufferSink(fileURL: fileURL, onMeter: Self.makeMeterHandler(for: self))
        
        switch input {
        case .microphone:
            try await startMicrophoneCapture(into: newSink)
        case .systemAudio:
            let capturer = SystemAudioCapturer(sink: newSink)
            try await capturer.start()
            systemCapturer = capturer
        }
        
        sink = newSink
        activeInput = input
        capturedFramesCount = 0
        recordedDuration = 0.0
        currentOutputFileURL = fileURL
        state = .recording
        startDurationTimer()
        return fileURL
    }
    
    private func startMicrophoneCapture(into sink: RecordingBufferSink) async throws {
        #if os(macOS)
        let authStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if authStatus == .denied || authStatus == .restricted {
            throw RecordingEngineError.permissionDenied
        }
        if authStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else { throw RecordingEngineError.permissionDenied }
        }
        #endif
        
        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            throw RecordingEngineError.engineFailed("Geçersiz ses giriş formatı (Mikrofon bağlı değil veya erişilemiyor).")
        }
        
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 2048, format: inputFormat, block: Self.makeTapBlock(sink: sink))
        
        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            throw RecordingEngineError.engineFailed("AVAudioEngine başlatılamadı: \(error.localizedDescription)")
        }
    }
    
    public func pauseRecording() throws {
        guard state == .recording else {
            throw RecordingEngineError.invalidState("Yalnızca kayıt aşamasında duraklatılabilir (Şu an: \(state.rawValue)).")
        }
        sink?.setPaused(true)
        if activeInput == .microphone { audioEngine.pause() }
        stopDurationTimer()
        state = .paused
    }
    
    public func resumeRecording() throws {
        guard state == .paused else {
            throw RecordingEngineError.invalidState("Yalnızca duraklatılmış kayıt devam ettirilebilir (Şu an: \(state.rawValue)).")
        }
        if activeInput == .microphone {
            do {
                try audioEngine.start()
            } catch {
                throw RecordingEngineError.engineFailed("Kayıt devam ettirilemedi: \(error.localizedDescription)")
            }
        }
        sink?.setPaused(false)
        startDurationTimer()
        state = .recording
    }
    
    public func stopRecording() async throws -> URL {
        guard state == .recording || state == .paused else {
            throw RecordingEngineError.notRecording
        }
        
        stopDurationTimer()
        await tearDownCapture()
        let capturedAudio = sink?.hasWrittenAudio ?? false
        sink?.finish()
        sink = nil
        resetMeters()
        
        guard let url = currentOutputFileURL else {
            state = .idle
            throw RecordingEngineError.invalidState("Çıktı dosyası URL'si bulunamadı.")
        }
        guard capturedAudio else {
            try? FileManager.default.removeItem(at: url)
            currentOutputFileURL = nil
            state = .idle
            throw RecordingEngineError.noAudioCaptured
        }
        
        state = .stopped
        return url
    }
    
    public func cancelRecording() {
        stopDurationTimer()
        let capturer = systemCapturer
        systemCapturer = nil
        if activeInput == .microphone {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        sink?.finish()
        sink = nil
        if let capturer {
            Task { await capturer.stop() }
        }
        
        if let url = currentOutputFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        currentOutputFileURL = nil
        resetMeters()
        recordedDuration = 0.0
        state = .idle
    }
    
    private func tearDownCapture() async {
        switch activeInput {
        case .microphone:
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        case .systemAudio:
            await systemCapturer?.stop()
            systemCapturer = nil
        }
    }
    
    private func resetMeters() {
        currentMeteringLevel = 0.0
        frequencyBands = Array(repeating: 0.0, count: 16)
    }
    
    // MARK: - Realtime callbacks (nonisolated by construction)
    
    /// Built in a nonisolated context so the closure does not inherit `@MainActor`
    /// isolation; otherwise Swift 6 traps when the tap fires on the audio thread.
    private nonisolated static func makeTapBlock(sink: RecordingBufferSink) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            sink.consume(buffer)
        }
    }
    
    private nonisolated static func makeMeterHandler(for engine: AudioRecordingEngine) -> RecordingBufferSink.MeterHandler {
        return { [weak engine] level, bands, frames in
            Task { @MainActor [weak engine] in
                guard let engine, engine.state == .recording else { return }
                engine.currentMeteringLevel = level
                engine.frequencyBands = bands
                engine.capturedFramesCount += Int64(frames)
            }
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
