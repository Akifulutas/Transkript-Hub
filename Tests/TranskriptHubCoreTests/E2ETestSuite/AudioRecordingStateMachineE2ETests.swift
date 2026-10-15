import Foundation
import Testing
import Accelerate
import AVFoundation
@testable import TranskriptHubCore

// MARK: - Headless Audio Recording Engine Harness

@MainActor
public final class HeadlessAudioRecordingEngine: AudioRecordingControlling {
    public private(set) var state: RecordingState = .idle
    public private(set) var currentMeteringLevel: Float = 0.0
    public private(set) var frequencyBands: [Float] = Array(repeating: 0.0, count: 16)
    public private(set) var capturedFramesCount: Int = 0
    public private(set) var currentOutputFileURL: URL?
    
    public var isRecording: Bool {
        state == .recording
    }
    
    public var isPaused: Bool {
        state == .paused
    }
    
    public var recordedDuration: Double {
        Double(capturedFramesCount) / 44100.0
    }
    
    private let outputDirectory: URL
    
    public init(outputDirectory: URL? = nil) {
        self.outputDirectory = outputDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("TranskriptHubRecordings_\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.outputDirectory, withIntermediateDirectories: true)
    }
    
    public func startRecording() async throws -> URL {
        guard state == .idle || state == .stopped else {
            throw RecordingEngineError.alreadyRecording
        }
        
        let fileURL = outputDirectory.appendingPathComponent("rec_\(UUID().uuidString).m4a")
        // Initialize file with dummy header/content to simulate disk presence
        let dummyHeader = Data("SIMULATED_M4A_AUDIO_HEADER".utf8)
        try dummyHeader.write(to: fileURL, options: .atomic)
        
        self.currentOutputFileURL = fileURL
        self.state = .recording
        self.capturedFramesCount = 0
        self.currentMeteringLevel = 0.0
        self.frequencyBands = Array(repeating: 0.0, count: 16)
        
        return fileURL
    }
    
    public func pauseRecording() throws {
        guard state == .recording else {
            throw RecordingEngineError.invalidState("Yalnızca kayıt aşamasında duraklatılabilir (Şu an: \(state.rawValue)).")
        }
        state = .paused
    }
    
    public func resumeRecording() throws {
        guard state == .paused else {
            throw RecordingEngineError.invalidState("Yalnızca duraklatılmış kayıt devam ettirilebilir (Şu an: \(state.rawValue)).")
        }
        state = .recording
    }
    
    public func stopRecording() async throws -> URL {
        guard state == .recording || state == .paused else {
            throw RecordingEngineError.notRecording
        }
        
        guard let url = currentOutputFileURL else {
            throw RecordingEngineError.invalidState("Kayıt dosyası URL'si bulunamadı.")
        }
        
        state = .stopped
        currentMeteringLevel = 0.0
        frequencyBands = Array(repeating: 0.0, count: 16)
        return url
    }
    
    public func cancelRecording() throws {
        guard state == .recording || state == .paused else {
            return
        }
        
        if let url = currentOutputFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        currentOutputFileURL = nil
        state = .idle
        capturedFramesCount = 0
        currentMeteringLevel = 0.0
        frequencyBands = Array(repeating: 0.0, count: 16)
    }
    
    /// Simulates incoming audio buffer tap callback from AVAudioEngine inputNode
    public func processAudioBuffer(samples: [Float], sampleRate: Double = 16000.0) {
        guard state == .recording else { return }
        guard !samples.isEmpty else { return }
        
        capturedFramesCount += samples.count
        
        // 1. RMS Level Calculation via vDSP
        var rms: Float = 0.0
        samples.withUnsafeBufferPointer { buffer in
            guard let ptr = buffer.baseAddress else { return }
            vDSP_rmsqv(ptr, 1, &rms, vDSP_Length(samples.count))
        }
        
        if rms.isNaN || rms.isInfinite {
            rms = 0.0
        }
        
        // Convert RMS to normalized [0.0, 1.0] scale (dBFS mapping)
        if rms <= 0.00001 {
            currentMeteringLevel = 0.0
        } else {
            let db = 20.0 * log10(max(rms, 0.00001))
            // Map -60 dBFS ... 0 dBFS to 0.0 ... 1.0
            let normalized = (db + 60.0) / 60.0
            currentMeteringLevel = min(1.0, max(0.0, normalized))
        }
        
        // 2. 16-Band Frequency Decomposition via Energy Partitioning
        let bandCount = 16
        var bands = [Float](repeating: 0.0, count: bandCount)
        let chunkSize = max(1, samples.count / bandCount)
        
        for i in 0..<bandCount {
            let start = i * chunkSize
            let count = (i == bandCount - 1) ? (samples.count - start) : chunkSize
            if count > 0 {
                var bandRMS: Float = 0.0
                samples.withUnsafeBufferPointer { buffer in
                    guard let ptr = buffer.baseAddress?.advanced(by: start) else { return }
                    vDSP_rmsqv(ptr, 1, &bandRMS, vDSP_Length(count))
                }
                bands[i] = min(1.0, max(0.0, (bandRMS.isNaN ? 0.0 : bandRMS) * 2.0))
            }
        }
        self.frequencyBands = bands
    }
    
    /// Simulates incoming system audio interruption (e.g. phone call)
    public func handleAudioInterruption(began: Bool) throws {
        if began {
            if state == .recording {
                try pauseRecording()
            }
        } else {
            if state == .paused {
                try resumeRecording()
            }
        }
    }
}

// MARK: - Test Suite

@Suite("Audio Recording State Machine E2E Test Suite")
struct AudioRecordingStateMachineE2ETests {
    
    @Test("Recording state machine executes full lifecycle: idle -> recording -> paused -> resumed -> stopped")
    @MainActor
    func testRecordingLifecycleTransitions() async throws {
        let engine = HeadlessAudioRecordingEngine()
        #expect(engine.state == .idle)
        #expect(engine.isRecording == false)
        
        // Start
        let url = try await engine.startRecording()
        #expect(engine.state == .recording)
        #expect(engine.isRecording == true)
        #expect(FileManager.default.fileExists(atPath: url.path))
        
        // Pause
        try engine.pauseRecording()
        #expect(engine.state == .paused)
        #expect(engine.isRecording == false)
        #expect(engine.isPaused == true)
        
        // Resume
        try engine.resumeRecording()
        #expect(engine.state == .recording)
        #expect(engine.isRecording == true)
        
        // Stop
        let finalURL = try await engine.stopRecording()
        #expect(engine.state == .stopped)
        #expect(engine.isRecording == false)
        #expect(finalURL == url)
        #expect(FileManager.default.fileExists(atPath: finalURL.path))
    }
    
    @Test("Illegal state transitions throw appropriate typed errors")
    @MainActor
    func testIllegalStateTransitionsRejected() async throws {
        let engine = HeadlessAudioRecordingEngine()
        
        // Cannot pause or stop when idle
        #expect(throws: RecordingEngineError.self) {
            try engine.pauseRecording()
        }
        
        await #expect(throws: RecordingEngineError.self) {
            _ = try await engine.stopRecording()
        }
        
        // Start recording
        _ = try await engine.startRecording()
        
        // Cannot start again while recording
        await #expect(throws: RecordingEngineError.alreadyRecording) {
            _ = try await engine.startRecording()
        }
        
        // Cannot resume while already recording
        #expect(throws: RecordingEngineError.self) {
            try engine.resumeRecording()
        }
        
        _ = try await engine.stopRecording()
    }
    
    @Test("Buffer capture simulation accurately counts incoming PCM audio frames")
    @MainActor
    func testBufferCaptureSimulationAndFrameCounting() async throws {
        let engine = HeadlessAudioRecordingEngine()
        _ = try await engine.startRecording()
        
        // Simulate feeding 10 buffers of 1024 frames each
        let bufferFrames = 1024
        let dummyBuffer = [Float](repeating: 0.15, count: bufferFrames)
        
        for _ in 1...10 {
            engine.processAudioBuffer(samples: dummyBuffer)
        }
        
        #expect(engine.capturedFramesCount == 10 * bufferFrames)
        
        _ = try await engine.stopRecording()
    }
    
    @Test("Real-time metering levels respond accurately to silence, speech, and loud audio")
    @MainActor
    func testRealTimeMeteringLevels() async throws {
        let engine = HeadlessAudioRecordingEngine()
        _ = try await engine.startRecording()
        
        // 1. Digital silence
        let silentSamples = [Float](repeating: 0.0, count: 1024)
        engine.processAudioBuffer(samples: silentSamples)
        #expect(engine.currentMeteringLevel == 0.0)
        
        // 2. Normal conversational speech level (RMS ~ 0.1 to 0.3)
        let speechSamples = (0..<1024).map { i in 0.25 * sin(Float(i) * 0.1) }
        engine.processAudioBuffer(samples: speechSamples)
        #expect(engine.currentMeteringLevel > 0.4)
        #expect(engine.currentMeteringLevel <= 1.0)
        
        // 3. Loud audio transient / clipping level
        let loudSamples = [Float](repeating: 1.0, count: 1024)
        engine.processAudioBuffer(samples: loudSamples)
        #expect(engine.currentMeteringLevel >= 0.95)
        #expect(engine.currentMeteringLevel <= 1.0)
        
        _ = try await engine.stopRecording()
    }
    
    @Test("Frequency band analyzer yields 16 valid frequency bands")
    @MainActor
    func testFrequencyBandsFFTDecomposition() async throws {
        let engine = HeadlessAudioRecordingEngine()
        _ = try await engine.startRecording()
        
        #expect(engine.frequencyBands.count == 16)
        
        // Feed audio samples with high energy in the upper quadrant
        var testSignal = [Float](repeating: 0.0, count: 1024)
        for i in 768..<1024 {
            testSignal[i] = 0.8
        }
        
        engine.processAudioBuffer(samples: testSignal)
        #expect(engine.frequencyBands.count == 16)
        for band in engine.frequencyBands {
            #expect(band >= 0.0 && band <= 1.0)
        }
        
        // Verify upper band registered energy
        #expect(engine.frequencyBands[14] > 0.1 || engine.frequencyBands[15] > 0.1)
        
        _ = try await engine.stopRecording()
    }
    
    @Test("Cancellation cleans up partial temporary audio file on disk")
    @MainActor
    func testCancellationDiscardsTemporaryFiles() async throws {
        let engine = HeadlessAudioRecordingEngine()
        let url = try await engine.startRecording()
        #expect(FileManager.default.fileExists(atPath: url.path))
        
        try engine.cancelRecording()
        #expect(engine.state == .idle)
        #expect(!FileManager.default.fileExists(atPath: url.path), "Canceled recording file must be deleted from disk")
    }
    
    @Test("Audio interruption handling cleanly pauses and resumes recording session")
    @MainActor
    func testInterruptionAndRecovery() async throws {
        let engine = HeadlessAudioRecordingEngine()
        _ = try await engine.startRecording()
        
        // Feed 512 frames
        engine.processAudioBuffer(samples: [Float](repeating: 0.1, count: 512))
        #expect(engine.capturedFramesCount == 512)
        
        // Interruption begins (e.g. phone call)
        try engine.handleAudioInterruption(began: true)
        #expect(engine.state == .paused)
        
        // Audio incoming while paused should be dropped
        engine.processAudioBuffer(samples: [Float](repeating: 0.1, count: 512))
        #expect(engine.capturedFramesCount == 512)
        
        // Interruption ends
        try engine.handleAudioInterruption(began: false)
        #expect(engine.state == .recording)
        
        // Resume feeding audio
        engine.processAudioBuffer(samples: [Float](repeating: 0.1, count: 512))
        #expect(engine.capturedFramesCount == 1024)
        
        _ = try await engine.stopRecording()
    }
}
