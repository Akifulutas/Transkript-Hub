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
    }
    
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.watchiCloudDrive")
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.watchiCloudRoot")
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.watchVoiceMemos")
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.watchCustomFolder")
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.customFolderPath")
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
        XCTAssertFalse(watcher.isWatching)
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
        XCTAssertTrue(activeDirs.contains(FolderWatcher.iCloudTranskriptDirectory))
        
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
    func testForceDownloadAllCloudItemsSafeExecution() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let watcher = FolderWatcher(watchedDirectory: tempDir)
        
        await watcher.forceDownloadAllCloudItems()
        // Verifies directory creation and safe execution without throwing
        XCTAssertTrue(FileManager.default.fileExists(atPath: FolderWatcher.iCloudTranskriptDirectory.path))
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
    }
}
