import Foundation

/// Defines logging utilities for TranskriptHub
public enum Log {
    public static func info(_ message: String) {
        print("[INFO] \(message)")
    }
    
    public static func warning(_ message: String) {
        print("[WARN] \(message)")
    }
    
    public static func error(_ message: String) {
        print("[ERROR] \(message)")
    }
    
    public static func debug(_ message: String) {
        #if DEBUG
        print("[DEBUG] \(message)")
        #endif
    }
}
