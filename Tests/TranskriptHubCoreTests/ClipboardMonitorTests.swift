import Foundation
import Testing
import AppKit
@testable import TranskriptHubCore

@Suite("Pano İzleyici (ClipboardMonitor) Test Paketi")
struct ClipboardMonitorTests {
    
    @Test("İzleme durumu ve toggle geçişleri")
    @MainActor
    func testMonitoringStateTransitions() {
        var detected: [ParsedYouTubeVideo] = []
        let monitor = ClipboardMonitor { video in
            detected.append(video)
        }
        
        #expect(monitor.isMonitoring == false)
        
        // Başlat
        monitor.startMonitoring()
        #expect(monitor.isMonitoring == true)
        
        // Tekrar başlatma idempotent olmalı
        monitor.startMonitoring()
        #expect(monitor.isMonitoring == true)
        
        // Durdur
        monitor.stopMonitoring()
        #expect(monitor.isMonitoring == false)
        
        // Toggle ile aç
        monitor.toggle()
        #expect(monitor.isMonitoring == true)
        
        // Toggle ile kapat
        monitor.toggle()
        #expect(monitor.isMonitoring == false)
    }
}
