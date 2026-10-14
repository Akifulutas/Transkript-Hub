import SwiftUI
import AppKit
import TranskriptHubCore

public struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Column 1: Sidebar
            SidebarView(viewModel: viewModel)
                .frame(minWidth: 170, idealWidth: 190, maxWidth: 240)
        } content: {
            // Column 2: Content List (Queue, History, Folder, Settings)
            Group {
                switch viewModel.selectedSection {
                case .queue:
                    QueueListView(viewModel: viewModel)
                case .history:
                    HistoryListView(viewModel: viewModel)
                case .watchedFolder:
                    WatchedFolderView(viewModel: viewModel)
                case .settings:
                    SettingsView(viewModel: viewModel)
                }
            }
            .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
        } detail: {
            // Column 3: Interactive Inspector & Reader Pane
            TranscriptDetailView(viewModel: viewModel)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .frame(minWidth: 850, minHeight: 560)
        .toolbar {
            mainToolbar
        }
        .searchable(text: $viewModel.searchQuery, prompt: "Transkriptlerde veya kuyrukta ara...")
    }
    
    // MARK: - Native macOS Unified Toolbar
    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            // Model Selector Dropdown
            Menu {
                Picker("Model", selection: $viewModel.selectedModel) {
                    Label("Tiny (75 MB - Yıldırım Hızlı)", systemImage: "bolt.fill").tag(WhisperModel.tiny)
                    Label("Base (142 MB - Standart)", systemImage: "hare.fill").tag(WhisperModel.base)
                    Label("Small (466 MB - Önerilen)", systemImage: "sparkles").tag(WhisperModel.small)
                    Label("Large-v3-Turbo (1.6 GB - En Yüksek Kalite)", systemImage: "crown.fill").tag(WhisperModel.largeV3Turbo)
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "cpu")
                        .foregroundColor(.secondary)
                    Text(viewModel.selectedModel.rawValue.capitalized)
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .help("Whisper Yapay Zeka Modelini Seçin")
        }
        
        ToolbarItem(placement: .automatic) {
            // Language Selector Dropdown
            Menu {
                Picker("Dil", selection: $viewModel.selectedLanguage) {
                    Text("🌐 Otomatik Algıla").tag("auto")
                    Text("🇹🇷 Türkçe").tag("tr")
                    Text("🇬🇧 İngilizce").tag("en")
                    Text("🇩🇪 Almanca").tag("de")
                    Text("🇫🇷 Fransızca").tag("fr")
                    Text("🇪🇸 İspanyolca").tag("es")
                    Text("🇷🇺 Rusça").tag("ru")
                    Text("🇸🇦 Arapça").tag("ar")
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                        .foregroundColor(.secondary)
                    Text(languageTitle(viewModel.selectedLanguage))
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .help("Transkript Edilecek Konuşma Dili")
        }
        
        ToolbarItem(placement: .automatic) {
            // Clipboard Monitor Toggle
            Toggle(isOn: $viewModel.isClipboardMonitoring) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(viewModel.isClipboardMonitoring ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text("Pano Takibi")
                        .font(.system(size: 12))
                }
            }
            .toggleStyle(.button)
            .help("Panoya kopyalanan tüm YouTube linklerini otomatik olarak kuyruğa ekler.")
        }
        
        ToolbarItem(placement: .primaryAction) {
            // Primary Action Button (⌘Return)
            Button(action: { viewModel.startProcessingQueue() }) {
                HStack(spacing: 6) {
                    if viewModel.isProcessing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    Text(viewModel.isProcessing ? "İşleniyor..." : "Transkripti Başlat")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.queueItems.isEmpty || viewModel.isProcessing)
            .keyboardShortcut(.defaultAction)
            .help("Kuyruktaki tüm videoları ve sesleri transkript etmeye başlar (⌘Return)")
        }
    }
    
    private func languageTitle(_ code: String) -> String {
        switch code {
        case "auto": return "Otomatik"
        case "tr": return "Türkçe"
        case "en": return "İngilizce"
        case "de": return "Almanca"
        case "fr": return "Fransızca"
        case "es": return "İspanyolca"
        default: return code.uppercased()
        }
    }
}
