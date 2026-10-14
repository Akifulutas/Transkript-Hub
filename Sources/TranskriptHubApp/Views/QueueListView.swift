import SwiftUI
import AppKit
import TranskriptHubCore

struct QueueListView: View {
    @ObservedObject var viewModel: AppViewModel
    
    var filteredItems: [QueueItem] {
        if viewModel.searchQuery.isEmpty {
            return viewModel.queueItems
        }
        return viewModel.queueItems.filter {
            $0.title.localizedCaseInsensitiveContains(viewModel.searchQuery) ||
            $0.subtitle.localizedCaseInsensitiveContains(viewModel.searchQuery)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Quick Add Input Box
            quickAddBar
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)
            
            Divider()
            
            // Queue List or Empty State
            if viewModel.queueItems.isEmpty {
                emptyQueueView
            } else {
                List(selection: $viewModel.selectedItemID) {
                    ForEach(filteredItems) { item in
                        QueueItemRow(item: item, isSelected: viewModel.selectedItemID == item.id)
                            .tag(item.id)
                            .contextMenu {
                                if let transcript = item.transcript {
                                    Button("Metni Kopyala") {
                                        viewModel.copyTranscript(text: transcript)
                                    }
                                }
                                if let output = item.outputURL {
                                    Button("Finder'da Göster") {
                                        viewModel.openInFinder(path: output.path)
                                    }
                                }
                                if let url = item.canonicalURL {
                                    Button("Tarayıcıda Aç") {
                                        viewModel.openInBrowser(url: url)
                                    }
                                }
                                Divider()
                                Button("Kuyruktan Çıkar", role: .destructive) {
                                    viewModel.removeItem(id: item.id)
                                }
                            }
                    }
                }
                .listStyle(.inset)
                
                Divider()
                
                // Bottom Queue Summary Bar
                HStack {
                    Text("\(viewModel.queueItems.count) İşlem Kuyrukta")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Tümünü Temizle") {
                        viewModel.clearQueue()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .disabled(viewModel.isProcessing)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .navigationTitle("Kuyruk")
        .onDrop(of: [.fileURL, .text], isTargeted: $viewModel.isDropTargetActive) { providers in
            handleUniversalDrop(providers: providers)
        }
    }
    
    // MARK: - Quick Add Bar
    private var quickAddBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 14))
                
                TextField("YouTube linki veya yerel ses dosyası ekleyin...", text: $viewModel.quickInputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        viewModel.addFromQuickInput()
                    }
                
                if !viewModel.quickInputText.isEmpty {
                    Button(action: { viewModel.addFromQuickInput() }) {
                        Text("Ekle")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            
            // Quick Action Buttons
            HStack(spacing: 12) {
                Button(action: { viewModel.addFromClipboard() }) {
                    Label("Panodan Yapıştır", systemImage: "doc.on.clipboard")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Button(action: { selectLocalAudioFiles() }) {
                    Label("Ses Dosyası Seç...", systemImage: "waveform")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: { viewModel.addSampleYouTube() }) {
                    Label("Örnek Link", systemImage: "sparkles")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Empty Queue View
    private var emptyQueueView: some View {
        VStack(spacing: 14) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.08))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 34))
                    .foregroundColor(.accentColor)
            }
            
            Text("Kuyruk Boş")
                .font(.system(size: 15, weight: .semibold))
            
            Text("YouTube linklerini buraya yapıştırabilir veya bilgisayarınızdaki ses dosyalarını pencereye sürükleyip bırakabilirsiniz.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
                .lineSpacing(2)
            
            HStack(spacing: 12) {
                Button("Ses Dosyası Seç...") {
                    selectLocalAudioFiles()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button("Örnek Video Ekle") {
                    viewModel.addSampleYouTube()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 4)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
    
    // MARK: - Helpers
    private func selectLocalAudioFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.audio, .movie]
        if panel.runModal() == .OK {
            viewModel.addAudioFiles(panel.urls)
        }
    }
    
    private func handleUniversalDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            // Check for file URLs
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        viewModel.addAudioFiles([url])
                    }
                }
            }
            // Check for plain text (URLs)
            else if provider.hasItemConformingToTypeIdentifier("public.text") {
                provider.loadItem(forTypeIdentifier: "public.text", options: nil) { item, _ in
                    guard let str = item as? String else { return }
                    DispatchQueue.main.async {
                        let parsed = URLParser.parseBulk(str)
                        for p in parsed {
                            viewModel.addYouTubeVideo(p)
                        }
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Row View
struct QueueItemRow: View {
    let item: QueueItem
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(item.isYouTube ? Color.red.opacity(0.12) : Color.purple.opacity(0.12))
                    .frame(width: 32, height: 32)
                
                Image(systemName: item.isYouTube ? "play.tv.fill" : "waveform")
                    .foregroundColor(item.isYouTube ? .red : .purple)
                    .font(.system(size: 14))
            }
            
            // Text Info
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Status Pill
            statusPill(state: item.state)
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func statusPill(state: QueueItemState) -> some View {
        switch state {
        case .queued:
            Text(state.rawValue)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .foregroundColor(.secondary)
                .clipShape(Capsule())
        case .fetching:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(state.rawValue)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.14))
            .foregroundColor(.blue)
            .clipShape(Capsule())
        case .transcribing:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text(state.rawValue)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.purple.opacity(0.14))
            .foregroundColor(.purple)
            .clipShape(Capsule())
        case .completed:
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                Text(state.rawValue)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.green.opacity(0.14))
            .foregroundColor(.green)
            .clipShape(Capsule())
        case .failed:
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 9))
                Text(state.rawValue)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.14))
            .foregroundColor(.red)
            .clipShape(Capsule())
        }
    }
}
