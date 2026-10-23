import XCTest
import Foundation
@testable import TranskriptHubCore

final class FolderWatcherTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.watchiCloudDrive")
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.watchiCloudRoot")
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.watchVoiceMemos")
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.watchCustomFolder")
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.customFolderPath")
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.autoTranscribe")
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.processedPaths")
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.dismissedPaths")
    }
    
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.watchiCloudDrive")
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.watchiCloudRoot")
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.watchVoiceMemos")
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.watchCustomFolder")
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.customFolderPath")
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.autoTranscribe")
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.processedPaths")
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.dismissedPaths")
        super.tearDown()
    }
    
    @MainActor
    func testFolderWatcherInitialDefaults() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let watcher = FolderWatcher(watchedDirectory: tempDir)
        
        // Defaults check
        XCTAssertTrue(watcher.watchiCloudDrive)
        XCTAssertTrue(watcher.watchiCloudRoot)
        XCTAssertTrue(watcher.watchVoiceMemos)
        XCTAssertTrue(watcher.autoTranscribe)
        XCTAssertFalse(watcher.isWatching)
    }
    
    @MainActor
    func testAutoTranscribePersistenceAndCallback() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let watcher = FolderWatcher(watchedDirectory: tempDir)
        XCTAssertTrue(watcher.autoTranscribe)
        
        var callbackValues: [Bool] = []
        watcher.onAutoTranscribeChanged = { newValue in
            callbackValues.append(newValue)
        }
        
        watcher.autoTranscribe = false
        XCTAssertEqual(callbackValues, [false])
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "FolderWatcher.autoTranscribe"))
        
        let secondWatcher = FolderWatcher(watchedDirectory: tempDir)
        XCTAssertFalse(secondWatcher.autoTranscribe)
        
        watcher.autoTranscribe = true
        XCTAssertEqual(callbackValues, [false, true])
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "FolderWatcher.autoTranscribe"))
    }
    
    @MainActor
    func testActiveWatchedDirectoriesComposition() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let watcher = FolderWatcher(watchedDirectory: tempDir)
        
        watcher.watchiCloudDrive = true
        watcher.watchiCloudRoot = true
        watcher.watchCustomFolder = false
        watcher.customFolderURL = nil
        
        let activeDirs = watcher.activeWatchedDirectories
        XCTAssertTrue(activeDirs.contains(FolderWatcher.iCloudRootDirectory))
        XCTAssertFalse(activeDirs.contains(FolderWatcher.iCloudTranskriptDirectory))
        
        // If custom folder is enabled and set
        let customDir = FileManager.default.temporaryDirectory.appendingPathComponent("CustomWatchFolder", isDirectory: true)
        watcher.customFolderURL = customDir
        watcher.watchCustomFolder = true
        
        let updatedDirs = watcher.activeWatchedDirectories
        XCTAssertTrue(updatedDirs.contains(customDir))
    }
    
    @MainActor
    func testWatcherStartAndStopLifecycle() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let watcher = FolderWatcher(watchedDirectory: tempDir)
        watcher.watchiCloudDrive = false
        watcher.watchVoiceMemos = false
        
        XCTAssertFalse(watcher.isWatching)
        watcher.startWatching()
        XCTAssertTrue(watcher.isWatching)
        
        watcher.stopWatching()
        XCTAssertFalse(watcher.isWatching)
    }
    
    @MainActor
    func testTriggerImmediateScanWhenNotWatching() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let watcher = FolderWatcher(watchedDirectory: tempDir)
        watcher.watchiCloudDrive = false
        watcher.watchVoiceMemos = false
        XCTAssertFalse(watcher.isWatching)
        
        // Immediate scan must proceed even when watcher timer is not running
        watcher.triggerImmediateScan()
        // Should not crash and should remain false for isWatching
        XCTAssertFalse(watcher.isWatching)
    }
    
    @MainActor
    func testCustomWatchedFolderAudioDiscoveryAndReset() async throws {
        let customDir = FileManager.default.temporaryDirectory.appendingPathComponent("WatchedAudioTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: customDir) }
        
        let audioFile = customDir.appendingPathComponent("sample_note.wav")
        let wavData = Self.makeValidWAVData(durationSeconds: 1.0, sampleRate: 16_000)
        try wavData.write(to: audioFile)
        // Set modification date 10 seconds in the past so size is considered stable immediately
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-10)], ofItemAtPath: audioFile.path)
        
        let watcher = FolderWatcher(watchedDirectory: customDir)
        watcher.watchiCloudDrive = false
        watcher.watchVoiceMemos = false
        watcher.customFolderURL = customDir
        watcher.watchCustomFolder = true
        
        var discoveredURLs: [URL] = []
        watcher.onNewAudioDiscovered = { url in
            discoveredURLs.append(url)
        }
        
        watcher.triggerImmediateScan()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(discoveredURLs.map(\.standardizedFileURL.path), [audioFile.standardizedFileURL.path])
        
        // Second scan without reset should not duplicate discovery
        watcher.triggerImmediateScan()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(discoveredURLs.count, 1)
        
        // Resetting processed paths under customDir allows re-discovery
        watcher.resetProcessedPaths(under: customDir)
        watcher.triggerImmediateScan()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(discoveredURLs.count, 2)
    }
    
    private static func makeValidWAVData(durationSeconds: Double, sampleRate: Int) -> Data {
        let numSamples = Int(durationSeconds * Double(sampleRate))
        let dataSize = UInt32(numSamples * 2)
        let fileSize = UInt32(36) + dataSize
        var header = Data()
        header.append(contentsOf: "RIFF".utf8)
        withUnsafeBytes(of: fileSize.littleEndian) { header.append(contentsOf: $0) }
        header.append(contentsOf: "WAVE".utf8)
        header.append(contentsOf: "fmt ".utf8)
        withUnsafeBytes(of: UInt32(16).littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(1).littleEndian) { header.append(contentsOf: $0) } // PCM
        withUnsafeBytes(of: UInt16(1).littleEndian) { header.append(contentsOf: $0) } // Mono
        withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(2).littleEndian) { header.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(16).littleEndian) { header.append(contentsOf: $0) }
        header.append(contentsOf: "data".utf8)
        withUnsafeBytes(of: dataSize.littleEndian) { header.append(contentsOf: $0) }
        header.append(Data(count: Int(dataSize)))
        return header
    }
    
    @MainActor
    func testForceDownloadAllCloudItemsSafeExecution() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let watcher = FolderWatcher(watchedDirectory: tempDir)
        
        await watcher.forceDownloadAllCloudItems()
        // Verifies safe execution without throwing or crashing
        XCTAssertFalse(watcher.isWatching)
    }
    
    @MainActor
    func testSetupICloudTranskriptFolderCreation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let watcher = FolderWatcher(watchedDirectory: tempDir)
        let folder = try watcher.setupICloudTranskriptFolder()
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertTrue(watcher.isICloudTranskriptFolderReady)
    }
    
    @MainActor
    func testWatcherIgnoresNonAudioAndTranskriptSubdirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("WatcherIgnoreTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let pdfFile = tempDir.appendingPathComponent("document.pdf")
        try "fake pdf".data(using: .utf8)?.write(to: pdfFile)
        
        let txtFile = tempDir.appendingPathComponent("notes.txt")
        try "transcription".data(using: .utf8)?.write(to: txtFile)
        
        let audioFile = tempDir.appendingPathComponent("voice.m4a")
        let wavData = Self.makeValidWAVData(durationSeconds: 1.0, sampleRate: 16_000)
        try wavData.write(to: audioFile)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-10)], ofItemAtPath: audioFile.path)
        
        let watcher = FolderWatcher(watchedDirectory: tempDir)
        watcher.watchiCloudDrive = false
        watcher.watchVoiceMemos = false
        watcher.customFolderURL = tempDir
        watcher.watchCustomFolder = true
        
        var discoveredURLs: [URL] = []
        watcher.onNewAudioDiscovered = { url in
            discoveredURLs.append(url)
        }
        
        watcher.triggerImmediateScan()
        try await Task.sleep(nanoseconds: 250_000_000)
        
        XCTAssertEqual(discoveredURLs.count, 1)
        XCTAssertEqual(discoveredURLs.first?.lastPathComponent, "voice.m4a")
    }
    
    func testWhisperModelDisplayNames() {
        for model in WhisperModel.allCases {
            XCTAssertFalse(model.displayName.isEmpty)
        }
        XCTAssertEqual(WhisperModel.largeV3Turbo.displayName, "Large-v3-Turbo")
        XCTAssertEqual(WhisperModel.largeV3TurboQ5.displayName, "Large-v3-Turbo (Q5_0)")
        XCTAssertEqual(WhisperModel.small.displayName, "Small")
        XCTAssertEqual(WhisperModel.base.displayName, "Base")
        XCTAssertEqual(WhisperModel.tiny.displayName, "Tiny")
        XCTAssertEqual(WhisperModel.medium.displayName, "Medium")
    }
    
    func testWhisperModelCatalogSortedBySizeBytesAscending() {
        let models = WhisperModelCatalog.availableModels
        XCTAssertEqual(models.count, 6)
        for i in 0..<(models.count - 1) {
            XCTAssertLessThanOrEqual(
                models[i].sizeBytes,
                models[i + 1].sizeBytes,
                "Model \(models[i].displayName) sizeBytes (\(models[i].sizeBytes)) must be <= next model \(models[i+1].displayName) sizeBytes (\(models[i+1].sizeBytes))"
            )
        }
        XCTAssertEqual(models.first?.model, .tiny)
        XCTAssertEqual(models.last?.model, .largeV3Turbo)
        
        // Verify model descriptions are concise
        for spec in models {
            XCTAssertFalse(spec.summary.isEmpty)
            XCTAssertLessThanOrEqual(spec.summary.count, 40, "Model summary '\(spec.summary)' should be concise")
        }
    }
    
    func testWhisperModelBenchmarkTenPointScaleRatings() {
        let models = WhisperModelCatalog.availableModels
        
        guard let tiny = models.first(where: { $0.model == .tiny }),
              let base = models.first(where: { $0.model == .base }),
              let small = models.first(where: { $0.model == .small }),
              let turboQ5 = models.first(where: { $0.model == .largeV3TurboQ5 }),
              let medium = models.first(where: { $0.model == .medium }),
              let turbo = models.first(where: { $0.model == .largeV3Turbo }) else {
            XCTFail("Missing expected models in catalog")
            return
        }
        
        // Verified Empirical Benchmark Scale (out of 10)
        XCTAssertEqual(tiny.speedScore, 10.0, accuracy: 0.01)
        XCTAssertEqual(tiny.accuracyScore, 4.0, accuracy: 0.01)
        
        XCTAssertEqual(base.speedScore, 9.0, accuracy: 0.01)
        XCTAssertEqual(base.accuracyScore, 5.5, accuracy: 0.01)
        
        XCTAssertEqual(small.speedScore, 7.0, accuracy: 0.01)
        XCTAssertEqual(small.accuracyScore, 7.5, accuracy: 0.01)
        
        XCTAssertEqual(turboQ5.speedScore, 9.0, accuracy: 0.01)
        XCTAssertEqual(turboQ5.accuracyScore, 9.0, accuracy: 0.01)
        
        XCTAssertEqual(medium.speedScore, 5.0, accuracy: 0.01)
        XCTAssertEqual(medium.accuracyScore, 8.5, accuracy: 0.01)
        
        XCTAssertEqual(turbo.speedScore, 8.5, accuracy: 0.01)
        XCTAssertEqual(turbo.accuracyScore, 9.5, accuracy: 0.01)
        
        for spec in models {
            XCTAssertGreaterThanOrEqual(spec.speedScore, 1.0)
            XCTAssertLessThanOrEqual(spec.speedScore, 10.0)
            XCTAssertGreaterThanOrEqual(spec.accuracyScore, 1.0)
            XCTAssertLessThanOrEqual(spec.accuracyScore, 10.0)
        }
    }
    
    func testDynamicWhisperModelBenchmarkEvaluation() {
        // Test evaluation for a newly discovered / custom online model
        let newCustomTurbo = WhisperModelCatalog.evaluateBenchmarkScores(
            modelName: "whisper-large-v3-turbo-custom",
            sizeBytes: 1_600_000_000,
            isTurbo: true,
            isQuantized: false
        )
        XCTAssertEqual(newCustomTurbo.speed, 8.5, accuracy: 0.01)
        XCTAssertEqual(newCustomTurbo.accuracy, 9.5, accuracy: 0.01)
        
        let newCustomQuantized = WhisperModelCatalog.evaluateBenchmarkScores(
            modelName: "whisper-turbo-q4_k",
            sizeBytes: 520_000_000,
            isTurbo: true,
            isQuantized: true
        )
        XCTAssertEqual(newCustomQuantized.speed, 9.0, accuracy: 0.01)
        XCTAssertEqual(newCustomQuantized.accuracy, 9.0, accuracy: 0.01)
        
        let newUnknownCompact = WhisperModelCatalog.evaluateBenchmarkScores(
            modelName: "distil-whisper-mini",
            sizeBytes: 85_000_000,
            isTurbo: false,
            isQuantized: false
        )
        XCTAssertEqual(newUnknownCompact.speed, 10.0, accuracy: 0.01)
        XCTAssertEqual(newUnknownCompact.accuracy, 4.0, accuracy: 0.01)
    }
    
    @MainActor
    func testFolderWatcherProcessedPathsPersistence() {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sampleFile = tempDir.appendingPathComponent("note.m4a").path
        
        let watcher1 = FolderWatcher(watchedDirectory: tempDir)
        XCTAssertFalse(watcher1.isPathProcessed(sampleFile))
        
        watcher1.markPathsAsProcessed([sampleFile])
        XCTAssertTrue(watcher1.isPathProcessed(sampleFile))
        
        // A new watcher instance should load persisted processed paths from UserDefaults
        let watcher2 = FolderWatcher(watchedDirectory: tempDir)
        XCTAssertTrue(watcher2.isPathProcessed(sampleFile))
        
        // Resetting processed paths removes them
        watcher2.resetProcessedPaths()
        XCTAssertFalse(watcher2.isPathProcessed(sampleFile))
        
        let watcher3 = FolderWatcher(watchedDirectory: tempDir)
        XCTAssertFalse(watcher3.isPathProcessed(sampleFile))
    }
    
    @MainActor
    func testFolderWatcherDismissedPathsPersistenceAndScanFiltering() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DismissTest_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        let audioFile = tempDir.appendingPathComponent("dismissed_note.wav")
        let wavData = Self.makeValidWAVData(durationSeconds: 1.0, sampleRate: 16_000)
        try wavData.write(to: audioFile)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-10)], ofItemAtPath: audioFile.path)
        
        let watcher1 = FolderWatcher(watchedDirectory: tempDir)
        watcher1.watchiCloudDrive = false
        watcher1.watchVoiceMemos = false
        watcher1.customFolderURL = tempDir
        watcher1.watchCustomFolder = true
        
        // Mark path as dismissed (deleted by user from queue)
        watcher1.markPathsAsDismissed([audioFile.path])
        XCTAssertTrue(watcher1.isPathDismissed(audioFile.path))
        XCTAssertTrue(watcher1.isPathProcessed(audioFile.path))
        
        // A second instance across app restarts retains dismissed state
        let watcher2 = FolderWatcher(watchedDirectory: tempDir)
        XCTAssertTrue(watcher2.isPathDismissed(audioFile.path))
        
        var discoveredURLs: [URL] = []
        watcher2.onNewAudioDiscovered = { url in
            discoveredURLs.append(url)
        }
        
        // Trigger scan: dismissed file must NEVER be discovered
        watcher2.triggerImmediateScan()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(discoveredURLs.count, 0)
        
        // Resetting processed paths does NOT clear dismissed paths
        watcher2.resetProcessedPaths()
        XCTAssertTrue(watcher2.isPathDismissed(audioFile.path))
        
        watcher2.triggerImmediateScan()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(discoveredURLs.count, 0)
        
        // Explicitly unmarking dismissed path allows discovery
        watcher2.unmarkPathsAsDismissed([audioFile.path])
        XCTAssertFalse(watcher2.isPathDismissed(audioFile.path))
        
        watcher2.triggerImmediateScan()
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(discoveredURLs.count, 1)
    }
}
