import Foundation
import AVFoundation
import AppKit
import CoreGraphics
import ScreenCaptureKit

public enum AudioPermissionStatus: String, Sendable, Equatable {
    case authorized
    case notDetermined
    case denied
    case restricted
    
    public var isGranted: Bool {
        self == .authorized
    }
    
    public var needsRequest: Bool {
        self == .notDetermined
    }
}

public enum AudioPermissionHelper {
    // MARK: - Microphone Access
    
    public static func checkMicrophoneStatus() -> AudioPermissionStatus {
        #if os(macOS)
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .notDetermined
        }
        #else
        return .authorized
        #endif
    }
    
    public static func requestMicrophoneAccess() async -> Bool {
        #if os(macOS)
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        if status == .authorized { return true }
        if status == .notDetermined {
            return await AVCaptureDevice.requestAccess(for: .audio)
        }
        openMicrophoneSettings()
        return false
        #else
        return true
        #endif
    }
    
    public static func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
    
    // MARK: - System Audio Access (ScreenCaptureKit)
    
    public static func checkSystemAudioStatus() -> AudioPermissionStatus {
        #if os(macOS)
        if CGPreflightScreenCaptureAccess() {
            return .authorized
        }
        return .denied
        #else
        return .authorized
        #endif
    }
    
    public static func requestSystemAudioAccess() -> Bool {
        #if os(macOS)
        if CGPreflightScreenCaptureAccess() { return true }
        let requested = CGRequestScreenCaptureAccess()
        if !requested {
            openSystemAudioSettings()
        }
        return requested
        #else
        return true
        #endif
    }
    
    public static func openSystemAudioSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    public static func verifySystemAudioAccessAsync() async -> Bool {
        #if os(macOS)
        if CGPreflightScreenCaptureAccess() { return true }
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
        #else
        return true
        #endif
    }
    
    /// Cleanly relaunches the application so updated macOS TCC privacy permissions take effect immediately.
    public static func relaunchApp() {
        #if os(macOS)
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundlePath]
        try? task.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApplication.shared.terminate(nil)
        }
        #endif
    }
}
