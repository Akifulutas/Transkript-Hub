import SwiftUI
import AppKit

@main
struct TranskriptHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var viewModel = AppViewModel()
    
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            
            CommandGroup(replacing: .appSettings) {
                Button("Ayarlar...") {
                    viewModel.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            
            CommandMenu("Bölümler") {
                Button("Kuyruk") {
                    viewModel.selectedSection = .queue
                    viewModel.bringMainWindowToFront()
                }
                .keyboardShortcut("1", modifiers: .command)
                
                Button("Geçmiş") {
                    viewModel.selectedSection = .history
                    viewModel.bringMainWindowToFront()
                }
                .keyboardShortcut("2", modifiers: .command)
                
                Button("İzlenen Klasör") {
                    viewModel.selectedSection = .watchedFolder
                    viewModel.bringMainWindowToFront()
                }
                .keyboardShortcut("3", modifiers: .command)
            }
            
            CommandMenu("İşlemler") {
                Button(viewModel.isProcessing ? "Transkript İşleniyor..." : "Transkripte Yolla") {
                    viewModel.requestStartQueue()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(viewModel.queueItems.isEmpty || viewModel.isProcessing)
                
                Button(viewModel.isClipboardMonitoring ? "Pano İzlemeyi Durdur" : "Pano İzlemeyi Başlat") {
                    viewModel.isClipboardMonitoring.toggle()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])
                
                Divider()
                
                Button("Panodan Bağlantı Ekle") {
                    viewModel.addFromClipboard()
                }
                .keyboardShortcut("v", modifiers: .command)
                
                Button("Ses / Video Dosyası Ekle...") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = true
                    panel.canChooseDirectories = false
                    panel.allowedContentTypes = [.audio, .movie]
                    if panel.runModal() == .OK {
                        viewModel.addAudioFiles(panel.urls)
                    }
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Divider()
                
                Button("Kuyruğu Temizle") {
                    viewModel.clearQueueWithUndo()
                }
                .disabled(viewModel.queueItems.isEmpty)
                
                Button("Tümünü Seç") {
                    viewModel.selectAllQueueItems()
                }
                .keyboardShortcut("a", modifiers: .command)
            }
        }
        
        MenuBarExtra("Transkript Hub", systemImage: "waveform.badge.magnifyingglass") {
            MenuBarMiniWindow(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            for window in NSApp.windows {
                if !(window is NSPanel) {
                    window.titlebarAppearsTransparent = true
                    window.isOpaque = false
                    window.backgroundColor = .clear
                }
            }
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Pencere kapansa bile arka planda devam eder, çıkmaz
        return false
    }
}
