import Foundation
import AppKit

public enum FullDiskAccessStatus: String, Sendable {
    case granted
    case notGranted
    
    public var isGranted: Bool {
        self == .granted
    }
}

public enum FullDiskAccessHelper {
    public static var voiceMemosDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings", isDirectory: true)
    }
    
    /// Checks if Full Disk Access is granted by attempting to inspect protected directories.
    public static func checkStatus() -> FullDiskAccessStatus {
        let fm = FileManager.default
        let path = voiceMemosDirectory.path
        
        // 1. Primary check: Voice Memos directory
        if fm.fileExists(atPath: path) {
            do {
                _ = try fm.contentsOfDirectory(atPath: path)
                return .granted
            } catch {
                return .notGranted
            }
        }
        
        // 2. Secondary check: Safari Bookmarks or Mail sandbox
        let safariBookmarks = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Safari/Bookmarks.plist")
        if fm.fileExists(atPath: safariBookmarks.path) {
            return fm.isReadableFile(atPath: safariBookmarks.path) ? .granted : .notGranted
        }
        
        // 3. Fallback check: Mail directory
        let mailDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mail")
        if fm.fileExists(atPath: mailDir.path) {
            do {
                _ = try fm.contentsOfDirectory(atPath: mailDir.path)
                return .granted
            } catch {
                return .notGranted
            }
        }
        
        return .notGranted
    }
    
    /// Deep-links directly to macOS System Settings > Privacy & Security > Full Disk Access.
    public static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}
