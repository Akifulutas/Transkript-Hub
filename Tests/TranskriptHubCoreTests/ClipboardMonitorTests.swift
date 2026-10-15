import Foundation
import Testing
import AppKit
@testable import TranskriptHubCore

@Suite("ClipboardMonitor Test Suite")
struct ClipboardMonitorTests {
    
    @Test("Monitoring state and toggle transitions")
    @MainActor
    func testMonitoringStateTransitions() {
        var detected: [ParsedYouTubeVideo] = []
        let monitor = ClipboardMonitor { video in
            detected.append(video)
        }
        
        #expect(monitor.isMonitoring == false)
        
        // Start monitoring
        monitor.startMonitoring()
        #expect(monitor.isMonitoring == true)
        
        // Re-starting must be idempotent
        monitor.startMonitoring()
        #expect(monitor.isMonitoring == true)
        
        // Stop monitoring
        monitor.stopMonitoring()
        #expect(monitor.isMonitoring == false)
        
        // Toggle on
        monitor.toggle()
        #expect(monitor.isMonitoring == true)
        
        // Toggle off
        monitor.toggle()
        #expect(monitor.isMonitoring == false)
    }
}
