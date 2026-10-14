import SwiftUI
import AppKit
import TranskriptHubCore

public struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @State private var selectedTab: Int = 0
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header / Tab Picker
            HStack {
                Picker("", selection: $selectedTab) {
                    Text("YouTube Linkleri").tag(0)
                    Text("Ses Dosyaları").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
                
                Spacer()
                
                // Clipboard Monitor Toggle
                Toggle(isOn: $viewModel.isClipboardMonitoring) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(viewModel.isClipboardMonitoring ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text("Panoyu İzle")
                            .font(.system(size: 13, weight: .medium))
                    }
                }
                .toggleStyle(.switch)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Tab Content
            if selectedTab == 0 {
                linksView
            } else {
                filesView
            }
            
            Divider()
            
            // Bottom Status & Action Bar
            statusBar
        }
        .frame(minWidth: 640, minHeight: 520)
    }
    
    // MARK: - Links View
    private var linksView: some View {
        VStack(spacing: 12) {
            // Bulk Paste Input
            HStack(alignment: .top, spacing: 8) {
                TextEditor(text: $viewModel.bulkText)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 54)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                
                Button("Listeye Ekle") {
                    viewModel.addBulkPastedText()
                }
                .frame(height: 54)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            
            // List of Added Videos
            if viewModel.sessionVideos.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "play.rectangle.on.rectangle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("Henüz video eklenmedi")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("Yukarıdaki alana YouTube linkleri yapıştırın veya 'Panoyu İzle'yi açıp link kopyalayın.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(viewModel.sessionVideos.enumerated()), id: \.element.videoID) { index, video in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.secondary)
                                .frame(width: 24, alignment: .leading)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(video.canonicalURL)
                                    .font(.system(size: 13, weight: .medium))
                                    .lineLimit(1)
                                Text("ID: \(video.videoID)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button(action: { viewModel.removeVideo(id: video.videoID) }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: viewModel.removeVideo)
                }
                .listStyle(.inset)
            }
        }
    }
    
    // MARK: - Files View
    private var filesView: some View {
        VStack(spacing: 16) {
            // Drag and Drop Zone
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundColor(.secondary.opacity(0.5))
                
                VStack(spacing: 8) {
                    Image(systemName: "waveform.circle")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("Ses Dosyalarını Buraya Sürükleyin")
                        .font(.headline)
                    Text("M4A, MP3, WAV, AAC, CAF formatları desteklenir")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Dosya Seç...") {
                        selectLocalFiles()
                    }
                    .padding(.top, 4)
                }
            }
            .frame(height: 140)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                handleDrop(providers: providers)
            }
            
            // List of Local Files
            if viewModel.localAudioFiles.isEmpty {
                Spacer()
                Text("Henüz yerel ses dosyası eklenmedi.")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(viewModel.localAudioFiles, id: \.self) { url in
                        HStack {
                            Image(systemName: "music.note")
                                .foregroundColor(.secondary)
                            Text(url.lastPathComponent)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                            Text(url.pathExtension.uppercased())
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.2))
                                .cornerRadius(4)
                        }
                    }
                    .onDelete(perform: viewModel.removeLocalFile)
                }
                .listStyle(.inset)
            }
        }
    }
    
    // MARK: - Status and Action Bar
    private var statusBar: some View {
        VStack(spacing: 10) {
            // Options row
            HStack(spacing: 16) {
                Picker("Model:", selection: $viewModel.selectedModel) {
                    Text("tiny (75 MB, En Hızlı)").tag(WhisperModel.tiny)
                    Text("base (142 MB, Standart)").tag(WhisperModel.base)
                    Text("small (466 MB, Dengeli)").tag(WhisperModel.small)
                    Text("large-v3-turbo (1.6 GB, En Yüksek)").tag(WhisperModel.largeV3Turbo)
                }
                .frame(width: 240)
                
                Picker("Dil:", selection: $viewModel.selectedLanguage) {
                    Text("Otomatik").tag("auto")
                    Text("Türkçe").tag("tr")
                    Text("İngilizce").tag("en")
                    Text("Almanca").tag("de")
                }
                .frame(width: 140)
                
                Spacer()
                
                if selectedTab == 0 && !viewModel.sessionVideos.isEmpty {
                    Button("Listeyi Temizle") {
                        viewModel.clearAllVideos()
                    }
                    .disabled(viewModel.isProcessing)
                }
                
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.sessionVideos.isEmpty || viewModel.isProcessing)
                }
            }
            .padding(.horizontal, 16)
            
            // Progress details row
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
                
                if let output = viewModel.lastOutputURL {
                    Button("Finder'da Göster") {
                        NSWorkspace.shared.activateFileViewerSelecting([output])
                    }
                    .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
        .padding(.top, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    // MARK: - Helpers
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
