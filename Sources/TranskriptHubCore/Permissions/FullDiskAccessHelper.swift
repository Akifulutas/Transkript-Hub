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
    
    /// Checks if Full Disk Access is granted by attempting to inspect protected directories and files.
    public static func checkStatus() -> FullDiskAccessStatus {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        
        // 1. Time Machine preference check (Standard macOS FDA test):
        // File exists with world-readable POSIX permissions, but kernel strictly denies read
        // without TCC Full Disk Access (SystemPolicyAllFiles).
        let tmFd = open("/Library/Preferences/com.apple.TimeMachine.plist", O_RDONLY)
        if tmFd >= 0 {
            close(tmFd)
            return .granted
        }
        
        // 2. Voice Memos directory (the specific feature we need FDA for)
        let vmPath = voiceMemosDirectory.path
        if let dir = opendir(vmPath) {
            closedir(dir)
            return .granted
        }
        
        // 3. Safari Bookmarks check (Protected by SystemPolicySysAdminFiles / FDA)
        let safariBookmarks = home.appendingPathComponent("Library/Safari/Bookmarks.plist")
        let safariFd = open(safariBookmarks.path, O_RDONLY)
        if safariFd >= 0 {
            close(safariFd)
            return .granted
        }
        
        // 4. Mail directory check
        let mailDir = home.appendingPathComponent("Library/Mail")
        if let dir = opendir(mailDir.path) {
            closedir(dir)
            return .granted
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
