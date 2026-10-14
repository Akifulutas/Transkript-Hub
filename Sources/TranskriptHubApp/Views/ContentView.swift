import SwiftUI
import AppKit
import TranskriptHubCore

public struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var selectedTab: Int = 0
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar
            
            Divider()
            
            // Tab Content
            Group {
                switch selectedTab {
                case 0:
                    youtubeLinksView
                case 1:
                    localAudioFilesView
                case 2:
                    watchedFolderView
                default:
                    youtubeLinksView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            Divider()
            
            // Bottom Action & Control Bar
            bottomControlBar
        }
        .frame(minWidth: 720, minHeight: 560)
        .sheet(item: $viewModel.previewData) { preview in
            TranscriptPreviewSheet(preview: preview)
        }
    }
    
    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(spacing: 16) {
            // App Branding
            HStack(spacing: 8) {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.accentColor)
                Text("Transkript Hub")
                    .font(.system(size: 15, weight: .bold))
            }
            
            Spacer()
            
            // Tab Picker
            Picker("", selection: $selectedTab) {
                Text("📺 YouTube (\(viewModel.sessionVideos.count))").tag(0)
                Text("🎙️ Ses Dosyaları (\(viewModel.localAudioFiles.count))").tag(1)
                Text("📁 İzlenen Klasör").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 360)
            
            Spacer()
            
            // Clipboard Monitor Switch
            Toggle(isOn: $viewModel.isClipboardMonitoring) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.isClipboardMonitoring ? Color.green : Color.gray.opacity(0.6))
                        .frame(width: 8, height: 8)
                    Text("Panoyu İzle")
                        .font(.system(size: 12, weight: .medium))
                }
            }
            .toggleStyle(.switch)
            .help("Açık olduğunda panoya kopyaladığınız YouTube linkleri otomatik olarak listeye eklenir.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - YouTube Links View
    private var youtubeLinksView: some View {
        VStack(spacing: 12) {
            // Input Area Card
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.bulkText)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 52)
                        .padding(4)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                        )
                    
                    if viewModel.bulkText.isEmpty {
                        Text("YouTube video, shorts veya canlı yayın linklerini buraya yapıştırın...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.7))
                            .padding(.top, 10)
                            .padding(.leading, 10)
                            .allowsHitTesting(false)
                    }
                }
                
                HStack {
                    Button(action: { viewModel.addFromClipboard() }) {
                        Label("Panodan Yapıştır", systemImage: "doc.on.clipboard")
                            .font(.system(size: 12))
                    }
                    
                    Button(action: { viewModel.addSampleLink() }) {
                        Label("Örnek Link", systemImage: "sparkles")
                            .font(.system(size: 12))
                    }
                    
                    Spacer()
                    
                    Button(action: { viewModel.addBulkPastedText() }) {
                        Label("Listeye Ekle", systemImage: "plus.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.bulkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(10)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
            // Video List or Empty State
            if viewModel.sessionVideos.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary.opacity(0.7))
                    Text("Kuyrukta Henüz Video Yok")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Yukarıdaki kutuya YouTube linklerini yapıştırabilir veya 'Panoyu İzle'yi açıp internette gezinebilirsiniz.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    
                    Button("Örnek Video Ekle (Me at the zoo)") {
                        viewModel.addSampleLink()
                    }
                    .font(.system(size: 12))
                    .padding(.top, 4)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("\(viewModel.sessionVideos.count) Video Hazır")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Tümünü Temizle") {
                            viewModel.clearAllVideos()
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .disabled(viewModel.isProcessing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    
                    List {
                        ForEach(Array(viewModel.sessionVideos.enumerated()), id: \.element.videoID) { index, video in
                            HStack(spacing: 12) {
                                // Index badge
                                Text("\(index + 1)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(width: 22, alignment: .leading)
                                
                                // YouTube Icon
                                Image(systemName: "play.tv.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 16))
                                
                                // Details
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(video.canonicalURL)
                                        .font(.system(size: 13, weight: .medium))
                                        .lineLimit(1)
                                    
                                    HStack(spacing: 8) {
                                        Text("ID: \(video.videoID)")
                                            .font(.system(size: 10, design: .monospaced))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.secondary.opacity(0.12))
                                            .cornerRadius(4)
                                        
                                        // Status badge
                                        if let status = viewModel.videoStatuses[video.videoID] {
                                            statusBadge(status: status)
                                        }
                                    }
                                }
                                
                                Spacer()
                                
                                // Browser preview button
                                Button(action: { viewModel.openInBrowser(url: video.canonicalURL) }) {
                                    Image(systemName: "arrow.up.right.square")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Videoyu tarayıcıda aç")
                                
                                // Delete button
                                Button(action: { viewModel.removeVideo(id: video.videoID) }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.secondary.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                                .disabled(viewModel.isProcessing)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: viewModel.removeVideo)
                    }
                    .listStyle(.inset)
                }
            }
        }
    }
    
    // MARK: - Local Audio Files View
    private var localAudioFilesView: some View {
        VStack(spacing: 12) {
            // Drag and Drop Area
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundColor(.accentColor.opacity(0.5))
                    .background(Color.accentColor.opacity(0.04))
                    .cornerRadius(12)
                
                VStack(spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 38))
                        .foregroundColor(.accentColor)
                    
                    Text("Ses Dosyalarını Buraya Sürükleyin")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text("M4A, MP3, WAV, AAC, CAF formatları desteklenir")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Button("Dosya Seç...") {
                        selectLocalFiles()
                    }
                    .font(.system(size: 12))
                    .padding(.top, 2)
                }
                .padding(16)
            }
            .frame(height: 130)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers: providers)
            }
            
            // List of Local Files
            if viewModel.localAudioFiles.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "waveform")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("Henüz Yerel Ses Dosyası Eklenmedi")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    Text("Mac'inizdeki veya iPhone'unuzdaki ses kayıtlarını buraya sürükleyip doğrudan GPU ile metne çevirebilirsiniz.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 380)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("\(viewModel.localAudioFiles.count) Dosya Seçildi")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Tümünü Temizle") {
                            viewModel.clearAllLocalFiles()
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .disabled(viewModel.isProcessing)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    
                    List {
                        ForEach(viewModel.localAudioFiles, id: \.self) { url in
                            HStack(spacing: 12) {
                                Image(systemName: "music.note")
                                    .foregroundColor(.purple)
                                    .font(.system(size: 16))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent)
                                        .font(.system(size: 13, weight: .medium))
                                    Text(url.path)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                Text(url.pathExtension.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(4)
                                
                                Button(action: { viewModel.removeLocalFile(url) }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.secondary.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                                .disabled(viewModel.isProcessing)
                            }
                            .padding(.vertical, 4)
                        }
                        .onDelete(perform: viewModel.removeLocalFile)
                    }
                    .listStyle(.inset)
                }
            }
        }
    }
    
    // MARK: - Watched Folder View
    private var watchedFolderView: some View {
        VStack(spacing: 20) {
            Spacer()
            
            VStack(spacing: 16) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 50))
                    .foregroundColor(.accentColor)
                
                Text("Otomatik Klasör ve iCloud Takibi")
                    .font(.system(size: 18, weight: .bold))
                
                Text("iCloud Drive veya yerel klasörünüze yeni bir ses kaydı düştüğünde (örneğin iPhone Sesli Notlar eşzamanlandığında), uygulama arka planda sesi otomatik olarak algılar ve GPU ile transkriptini oluşturur.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
                
                // Status Box
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(viewModel.isFolderWatching ? Color.green : Color.gray)
                            .frame(width: 10, height: 10)
                        
                        Text(viewModel.isFolderWatching ? "Otomatik Takip Açık (Aktif)" : "Otomatik Takip Kapalı")
                            .font(.system(size: 13, weight: .semibold))
                        
                        Spacer()
                        
                        Toggle("", isOn: $viewModel.isFolderWatching)
                            .toggleStyle(.switch)
                    }
                    
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("İzlenen Dizin:")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            Text(viewModel.watchedDirectoryPath)
                                .font(.system(size: 11, design: .monospaced))
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        Button("Finder'da Aç") {
                            let url = URL(fileURLWithPath: viewModel.watchedDirectoryPath)
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                        }
                        .font(.system(size: 11))
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
                .frame(maxWidth: 520)
            }
            
            Spacer()
        }
        .padding(20)
    }
    
    // MARK: - Bottom Control Bar
    private var bottomControlBar: some View {
        VStack(spacing: 10) {
            // Options Row
            HStack(spacing: 16) {
                // Model Picker
                Picker("Model:", selection: $viewModel.selectedModel) {
                    Text("⚡ tiny (75 MB - Yıldırım Hızlı)").tag(WhisperModel.tiny)
                    Text("🚀 base (142 MB - Standart)").tag(WhisperModel.base)
                    Text("🎯 small (466 MB - Dengeli & Hassas)").tag(WhisperModel.small)
                    Text("💎 large-v3-turbo (1.6 GB - En Yüksek Kalite)").tag(WhisperModel.largeV3Turbo)
                }
                .frame(width: 290)
                
                // Language Picker
                Picker("Dil:", selection: $viewModel.selectedLanguage) {
                    Text("🌐 Otomatik").tag("auto")
                    Text("🇹🇷 Türkçe").tag("tr")
                    Text("🇬🇧 İngilizce").tag("en")
                    Text("🇩🇪 Almanca").tag("de")
                    Text("🇫🇷 Fransızca").tag("fr")
                    Text("🇪🇸 İspanyolca").tag("es")
                }
                .frame(width: 150)
                
                Spacer()
                
                // Primary Action Button
                if selectedTab == 0 {
                    Button(action: { viewModel.startBatchTranscription() }) {
                        HStack(spacing: 6) {
                            if viewModel.isProcessing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(viewModel.isProcessing ? "İşleniyor..." : "\(viewModel.sessionVideos.count) Videoyu Transkript Et")
                                .bold()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.sessionVideos.isEmpty || viewModel.isProcessing)
                } else if selectedTab == 1 {
                    Button(action: { viewModel.startLocalAudioTranscription() }) {
                        HStack(spacing: 6) {
                            if viewModel.isProcessing {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "waveform")
                            }
                            Text(viewModel.isProcessing ? "İşleniyor..." : "\(viewModel.localAudioFiles.count) Sesi Transkript Et")
                                .bold()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.localAudioFiles.isEmpty || viewModel.isProcessing)
                }
            }
            .padding(.horizontal, 16)
            
            // Progress Bar (when processing)
            if viewModel.isProcessing {
                ProgressView(value: viewModel.progressFraction)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 16)
            }
            
            // Status and Completed Action Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.statusMessage)
                        .font(.system(size: 12, weight: .semibold))
                    if !viewModel.currentJobProgress.isEmpty {
                        Text(viewModel.currentJobProgress)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Completed Export Actions
                if let output = viewModel.lastOutputURL {
                    HStack(spacing: 8) {
                        Button(action: { viewModel.showPreview() }) {
                            Label("Önizle", systemImage: "doc.text.magnifyingglass")
                                .font(.system(size: 12))
                        }
                        
                        Button(action: { viewModel.copyTranscriptToClipboard() }) {
                            Label(viewModel.copiedToast ? "Kopyalandı! ✓" : "Metni Kopyala", systemImage: "doc.on.doc")
                                .font(.system(size: 12))
                        }
                        
                        Button(action: { NSWorkspace.shared.activateFileViewerSelecting([output]) }) {
                            Label("Finder'da Göster", systemImage: "folder")
                                .font(.system(size: 12))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .padding(.top, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Helpers
    @ViewBuilder
    private func statusBadge(status: String) -> some View {
        switch status {
        case "fetching":
            Text("İndiriliyor...")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.blue.opacity(0.2))
                .foregroundColor(.blue)
                .cornerRadius(3)
        case "transcribing":
            Text("Yazıya Çevriliyor...")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.purple.opacity(0.2))
                .foregroundColor(.purple)
                .cornerRadius(3)
        case "completed":
            Text("Tamamlandı ✓")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.green.opacity(0.2))
                .foregroundColor(.green)
                .cornerRadius(3)
        case "failed":
            Text("Hata ⚠️")
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(Color.red.opacity(0.2))
                .foregroundColor(.red)
                .cornerRadius(3)
        default:
            EmptyView()
        }
    }
    
    private func selectLocalFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.audio, .movie]
        
        if panel.runModal() == .OK {
            viewModel.addLocalFiles(panel.urls)
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async {
                    viewModel.addLocalFiles([url])
                }
            }
        }
        return true
    }
}

// MARK: - Transcript Preview Sheet
struct TranscriptPreviewSheet: View {
    let preview: PreviewData
    @Environment(\.dismiss) private var dismiss
    @State private var copied: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.title)
                        .font(.system(size: 15, weight: .bold))
                    Text("\(preview.text.split(separator: " ").count) kelime • \(preview.text.components(separatedBy: "\n").count) satır")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(preview.text, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                }) {
                    Label(copied ? "Kopyalandı! ✓" : "Panoya Kopyala", systemImage: "doc.on.doc")
                }
                
                Button("Kapat") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Text Content
            ScrollView {
                Text(preview.text)
                    .font(.system(size: 13, design: .serif))
                    .lineSpacing(4)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .background(Color(NSColor.textBackgroundColor))
        }
        .frame(minWidth: 600, minHeight: 450)
    }
}
