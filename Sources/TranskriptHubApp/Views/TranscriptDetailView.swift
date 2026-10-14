import SwiftUI
import AppKit

struct TranscriptDetailView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var searchInText: String = ""
    
    var activeItem: QueueItem? {
        viewModel.selectedItem
    }
    
    var activeHistoryItem: HistoryItem? {
        viewModel.selectedHistoryItem
    }
    
    var body: some View {
        Group {
            if let item = activeItem {
                contentForItem(item)
            } else if let history = activeHistoryItem {
                contentForHistory(history)
            } else {
                emptyDetailView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.textBackgroundColor))
    }
    
    // MARK: - Queue Item View
    @ViewBuilder
    private func contentForItem(_ item: QueueItem) -> some View {
        VStack(spacing: 0) {
            // Inspector Header
            inspectorHeader(
                title: item.title,
                subtitle: item.subtitle,
                duration: item.durationSec,
                transcript: item.transcript,
                outputURL: item.outputURL,
                browserURL: item.canonicalURL
            )
            
            Divider()
            
            // Body: Processing Card or Full Transcript
            if item.state == .transcribing || item.state == .fetching {
                activeProcessingCard(title: item.title, state: item.state)
            } else if let transcript = item.transcript, !transcript.isEmpty {
                transcriptReader(text: transcript)
            } else if item.state == .failed {
                failedStateView(error: item.errorMessage ?? "Bilinmeyen bir hata meydana geldi.")
            } else {
                readyToTranscribeView(title: item.title)
            }
        }
    }
    
    // MARK: - History Item View
    @ViewBuilder
    private func contentForHistory(_ history: HistoryItem) -> some View {
        let content = (try? String(contentsOfFile: history.outputPath, encoding: .utf8)) ?? history.snippet
        let url = URL(fileURLWithPath: history.outputPath)
        
        VStack(spacing: 0) {
            inspectorHeader(
                title: history.title,
                subtitle: "Arşiv Transkripti • \(history.outputPath)",
                duration: nil,
                transcript: content,
                outputURL: url,
                browserURL: nil
            )
            
            Divider()
            
            transcriptReader(text: content)
        }
    }
    
    // MARK: - Inspector Header
    private func inspectorHeader(
        title: String,
        subtitle: String,
        duration: Double?,
        transcript: String?,
        outputURL: URL?,
        browserURL: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(2)
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Quick Actions
                HStack(spacing: 6) {
                    // Copy
                    Button(action: { viewModel.copyTranscript(text: transcript) }) {
                        Label(viewModel.copiedToast ? "Kopyalandı!" : "Kopyala", systemImage: viewModel.copiedToast ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(transcript == nil || transcript!.isEmpty)
                    
                    // Finder
                    if let output = outputURL {
                        Button(action: { viewModel.openInFinder(path: output.path) }) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Finder'da Göster")
                    }
                    
                    // Browser
                    if let browser = browserURL {
                        Button(action: { viewModel.openInBrowser(url: browser) }) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Tarayıcıda Aç")
                    }
                }
            }
            
            // Metadata chips and search bar
            if let text = transcript, !text.isEmpty {
                HStack(spacing: 12) {
                    let wordCount = text.split(separator: " ").count
                    let charCount = text.count
                    
                    Text("\(wordCount) kelime")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Text("\(charCount) karakter")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Search in text field
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                        TextField("Metin içinde ara...", text: $searchInText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .frame(width: 140)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    
                    // Font Size Controls
                    HStack(spacing: 2) {
                        Button(action: { viewModel.transcriptFontSize = max(11, viewModel.transcriptFontSize - 1) }) {
                            Text("A-").font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { viewModel.transcriptFontSize = min(22, viewModel.transcriptFontSize + 1) }) {
                            Text("A+").font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Transcript Reader
    private func transcriptReader(text: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                let paragraphs = text.components(separatedBy: "\n\n")
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    if !paragraph.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(paragraph)
                            .font(.system(size: CGFloat(viewModel.transcriptFontSize), design: .serif))
                            .lineSpacing(5)
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Active Processing Card
    private func activeProcessingCard(title: String, state: QueueItemState) -> some View {
        VStack(spacing: 18) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 84, height: 84)
                
                Image(systemName: state == .fetching ? "arrow.down.circle.fill" : "waveform.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(state == .fetching ? .blue : .purple)
            }
            
            VStack(spacing: 6) {
                Text(state == .fetching ? "Video Sesi İndiriliyor..." : "Yapay Zeka ile Metne Çevriliyor...")
                    .font(.system(size: 16, weight: .bold))
                
                Text(viewModel.currentOperation.isEmpty ? "Apple Silicon GPU Metal hızlandırması devrede." : viewModel.currentOperation)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: viewModel.progressFraction)
                .progressViewStyle(.linear)
                .frame(maxWidth: 320)
            
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 11))
                Text("Metal Hızlandırma • whisper.cpp v1.9.2")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.secondary)
            .padding(.top, 4)
            
            Spacer()
        }
        .padding(20)
    }
    
    // MARK: - Ready to Transcribe View
    private func readyToTranscribeView(title: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "play.circle")
                .font(.system(size: 40))
                .foregroundColor(.accentColor.opacity(0.8))
            
            Text("İşleme Hazır")
                .font(.system(size: 15, weight: .semibold))
            
            Text("Bu kaydı transkript etmek için üst menüdeki 'Transkripti Başlat' düğmesine basabilir veya ⌘Return tuşlayabilirsiniz.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            
            Button("Şimdi Başlat") {
                viewModel.startProcessingQueue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.top, 4)
            
            Spacer()
        }
        .padding(20)
    }
    
    // MARK: - Failed State View
    private func failedStateView(error: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.red)
            
            Text("İşlem Başarısız Oldu")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.red)
            
            Text(error)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            
            Button("Tekrar Dene") {
                viewModel.startProcessingQueue()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 6)
            
            Spacer()
        }
        .padding(20)
    }
    
    // MARK: - Empty Detail View
    private var emptyDetailView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.4))
            
            Text("Transkript Seçilmedi")
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.secondary)
            
            Text("Soldaki listeden bir videoya veya ses dosyasına tıklayarak metnini burada görüntüleyebilirsiniz.")
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            
            Spacer()
        }
        .padding(20)
    }
}
