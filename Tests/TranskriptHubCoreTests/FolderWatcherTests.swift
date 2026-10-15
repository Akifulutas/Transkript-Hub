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
}
