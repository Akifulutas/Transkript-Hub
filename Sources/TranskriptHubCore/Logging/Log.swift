import Foundation
import os

/// Defines logging utilities for TranskriptHub
public enum Log {
    private static let logger = Logger(subsystem: "com.akifulutas.TranskriptHub", category: "Core")
    
    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        #if DEBUG
        print("[INFO] \(message)")
        #endif
    }
    
    public static func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
        #if DEBUG
        print("[WARN] \(message)")
        #endif
    }
    
    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        #if DEBUG
        print("[ERROR] \(message)")
        #endif
    }
    
    public static func debug(_ message: String) {
        #if DEBUG
        logger.debug("\(message, privacy: .public)")
        print("[DEBUG] \(message)")
        #endif
    }
}
