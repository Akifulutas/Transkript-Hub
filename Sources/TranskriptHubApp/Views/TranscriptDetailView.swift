import SwiftUI
import AppKit
import TranskriptHubCore

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
            if viewModel.selectedItemIDs.count > 1 || viewModel.showCombinedSessionTranscript {
                combinedSessionView
            } else if let item = activeItem {
                contentForItem(item)
            } else if let history = activeHistoryItem {
                contentForHistory(history)
            } else {
                studioWelcomeView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
    
    // MARK: - Queue Item View
    @ViewBuilder
    private func contentForItem(_ item: QueueItem) -> some View {
        VStack(spacing: 0) {
            // Liquid Glass Inspector Header
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
                failedStateView(item: item)
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
        let fileExists = FileManager.default.fileExists(atPath: history.outputPath)
        
        VStack(spacing: 0) {
            inspectorHeader(
                title: history.title,
                subtitle: "Arşiv Transkripti • \(history.outputPath)",
                duration: nil,
                transcript: content.isEmpty ? nil : content,
                outputURL: fileExists ? url : nil,
                browserURL: nil
            )
            
            Divider()
            
            if fileExists && !content.isEmpty {
                transcriptReader(text: content)
            } else {
                missingHistoryFileView(history: history)
            }
        }
    }
    
    // MARK: - Missing History File View
    private func missingHistoryFileView(history: HistoryItem) -> some View {
        VStack(spacing: 16) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 70, height: 70)
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 6) {
                Text("Arşiv Dosyası Bulunamadı")
                    .font(.system(size: 16, weight: .bold))
                
                Text("Bu kayıt veritabanında mevcut ancak dosya taşınmış veya silinmiş olabilir:\n\(history.outputPath)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            
            if !history.snippet.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Kayıtlı Özet Parça:")
                        .font(.system(size: 11, weight: .semibold))
                    Text(history.snippet)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .frame(maxWidth: 420)
                .liquidGlass(cornerRadius: 12, glowColor: .white.opacity(0.4), material: .ultraThinMaterial)
            }
            
            Spacer()
        }
        .padding(24)
    }
    
    // MARK: - Liquid Glass Inspector Header
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
                
                // Quick Action Capsule Buttons (H / 2 Capsule Rule)
                HStack(spacing: 8) {
                    // Session Combined View Toggle
                    if viewModel.completedCount > 1 {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                viewModel.showCombinedSessionTranscript.toggle()
                            }
                        }) {
                            Label(
                                viewModel.showCombinedSessionTranscript ? "Tekil Video" : "Birleşik Oturum (\(viewModel.completedCount))",
                                systemImage: viewModel.showCombinedSessionTranscript ? "doc.plaintext" : "rectangle.stack.fill"
                            )
                            .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(viewModel.showCombinedSessionTranscript ? .accentColor : .primary)
                    }
                    
                    // Copy
                    Button(action: { viewModel.copyTranscript(text: transcript) }) {
                        Label(viewModel.copiedToast ? "Kopyalandı!" : "Kopyala (⌘⇧C)", systemImage: viewModel.copiedToast ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
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
            
            // Metadata chips and search in text
            if let text = transcript, !text.isEmpty {
                HStack(spacing: 12) {
                    let wordCount = text.split(separator: " ").count
                    let charCount = text.count
                    
                    Text("\(wordCount) kelime")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Text("\(charCount) karakter")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Search in text field
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                        TextField("Metinde ara...", text: $searchInText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .frame(width: 130)
                        
                        if !searchInText.isEmpty {
                            Button(action: { searchInText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .liquidGlassCapsule(glowColor: .white.opacity(0.6), material: .ultraThinMaterial)
                    
                    // Kinetic Typography Scale Buttons
                    HStack(spacing: 3) {
                        Button(action: { viewModel.transcriptFontSize = max(11, viewModel.transcriptFontSize - 1) }) {
                            Text("A-").font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                        
                        Button(action: { viewModel.transcriptFontSize = min(22, viewModel.transcriptFontSize + 1) }) {
                            Text("A+").font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .liquidGlassCapsule(glowColor: .white.opacity(0.4), material: .ultraThinMaterial)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Combined Session View
    private var combinedSessionView: some View {
        let text = viewModel.combinedTranscript
        let completedCount = viewModel.selectedItemIDs.count > 1
            ? viewModel.queueItems.filter { viewModel.selectedItemIDs.contains($0.id) && $0.state == .completed }.count
            : viewModel.completedItems.count
        
        return VStack(spacing: 0) {
            inspectorHeader(
                title: "Toplu Oturum Transkripti (\(completedCount) Video)",
                subtitle: viewModel.selectedItemIDs.count > 1 ? "\(viewModel.selectedItemIDs.count) video seçildi ve birleştirildi" : "Kuyruktaki tüm videolar tek bir transkript olarak birleştirildi",
                duration: nil,
                transcript: text.isEmpty ? nil : text,
                outputURL: viewModel.lastOutputURL,
                browserURL: nil
            )
            
            Divider()
            
            if !text.isEmpty {
                transcriptReader(text: text)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("Henüz tamamlanan transkript bulunmuyor.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Native Kinetic Transcript Reader (Full ⌘A, ⌘C, Smooth Scaling)
    private func transcriptReader(text: String) -> some View {
        NativeTranscriptTextView(
            text: text,
            fontSize: CGFloat(viewModel.transcriptFontSize),
            searchHighlight: searchInText
        )
    }
    
    // MARK: - Active Processing State (Loading in 8-State Matrix)
    private func activeProcessingCard(title: String, state: QueueItemState) -> some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(state == .fetching ? Color.blue.opacity(0.12) : Color.purple.opacity(0.12))
                    .frame(width: 80, height: 80)
                
                Image(systemName: state == .fetching ? "arrow.down.circle.fill" : "waveform.circle.fill")
                    .font(.system(size: 42))
                    .foregroundColor(state == .fetching ? .blue : .purple)
            }
            
            VStack(spacing: 6) {
                Text(state == .fetching ? "Video Sesi Çözümleniyor..." : "Yapay Zeka Metne Çeviriyor...")
                    .font(.system(size: 16, weight: .bold))
                
                Text(viewModel.currentOperation.isEmpty ? "Apple Silicon Metal GPU hızlandırması devrede." : viewModel.currentOperation)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: viewModel.progressFraction)
                .progressViewStyle(.linear)
                .frame(maxWidth: 320)
            
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 11))
                Text("Metal GPU • whisper.cpp v1.9.2")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .liquidGlassCapsule(glowColor: .purple.opacity(0.5), material: .ultraThinMaterial)
            
            Spacer()
        }
        .padding(24)
    }
    
    // MARK: - Ready State
    private func readyToTranscribeView(title: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "play.circle")
                .font(.system(size: 38))
                .foregroundColor(.accentColor.opacity(0.8))
            
            Text("İşleme Hazır")
                .font(.system(size: 15, weight: .semibold))
            
            Text("Transkript işlemini başlatmak için ⌘Return tuşlayabilir veya araç çubuğundaki butona basabilirsiniz.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            
            Button("Şimdi Başlat (⌘Return)") {
                viewModel.startProcessingQueue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.top, 4)
            
            Spacer()
        }
        .padding(20)
    }
    
    // MARK: - Failed State (Error in 8-State Matrix)
    private func failedStateView(item: QueueItem) -> some View {
        VStack(spacing: 16) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 72, height: 72)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 6) {
                Text("İndirme / Transkript Hatası")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.orange)
                
                Text(item.errorMessage ?? "Video veya ses kaynağına erişilemedi.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            
            // Actionable Resolution Box
            VStack(alignment: .leading, spacing: 6) {
                Text("Önerilen Çözüm:")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                Text("• Bağlantının gizli veya üyelere özel olmadığını doğrulayın.\n• Bağlantıyı tarayıcıda açarak videonun erişilebilir olduğunu kontrol edin.\n• Aşağıdaki butona tıklayarak işlemi tek adımda yeniden deneyin.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
            }
            .padding(12)
            .frame(maxWidth: 380)
            .liquidGlass(cornerRadius: 10, glowColor: .orange.opacity(0.5), material: .ultraThinMaterial)
            
            Button("Tek Tıkla Yeniden Dene") {
                viewModel.retryItem(id: item.id)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.top, 4)
            
            Spacer()
        }
        .padding(24)
    }
    
    // MARK: - Liquid Glass Studio Welcome Hub (Replacing empty black void)
    private var studioWelcomeView: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 20)
                
                // Hero Header with Glowing Liquid Glass Waveform
                VStack(spacing: 12) {
                    ZStack {
                        // Ambient Halo
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color.accentColor.opacity(0.25), Color.purple.opacity(0.15), Color.clear],
                                    center: .center,
                                    startRadius: 10,
                                    endRadius: 60
                                )
                            )
                            .frame(width: 100, height: 100)
                        
                        // Glass Orb
                        Circle()
                            .fill(.ultraThinMaterial)
                            .frame(width: 72, height: 72)
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            stops: [
                                                .init(color: .white.opacity(0.6), location: 0),
                                                .init(color: .white.opacity(0.1), location: 0.5),
                                                .init(color: .clear, location: 0.8)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            )
                            .shadow(color: Color.accentColor.opacity(0.3), radius: 14, x: 0, y: 6)
                        
                        Image(systemName: "waveform.badge.magnifyingglass")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.accentColor, Color.purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(spacing: 6) {
                        Text("Transkript Hub")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.primary, .primary.opacity(0.8)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        
                        Text("YouTube videolarını ve yerel ses kayıtlarını Apple Silicon Metal GPU ile sıfır temasla transkript edin.")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 440)
                            .lineSpacing(3)
                    }
                }
                
                // Interactive Liquid Glass Drop Zone
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 28))
                            .foregroundColor(.accentColor.opacity(0.8))
                        
                        Text("YouTube Bağlantısı Yapıştırın veya Ses Dosyası Bırakın")
                            .font(.system(size: 14, weight: .semibold))
                        
                        Text("Panodaki bir linki almak için doğrudan ⌘V tuşlayabilir veya dosyaları buraya sürükleyebilirsiniz.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 380)
                    }
                    
                    // Format Chips (H / 2 Capsule Rule)
                    HStack(spacing: 6) {
                        formatChip("YouTube")
                        formatChip("M4A")
                        formatChip("MP3")
                        formatChip("WAV")
                        formatChip("Sesli Notlar")
                        formatChip("iCloud")
                    }
                    
                    // Quick Action Buttons
                    HStack(spacing: 12) {
                        Button(action: { viewModel.addFromClipboard() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.clipboard")
                                Text("Panodan Yapıştır (⌘V)")
                            }
                            .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        
                        Button(action: { selectLocalAudioFiles() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                Text("Ses Dosyası Seç...")
                            }
                            .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: 520)
                .liquidGlass(cornerRadius: 18, glowColor: .accentColor.opacity(0.5), material: .ultraThinMaterial)
                
                // 3 Hero Value Pillars (Clean Horizontal Glass Cards)
                HStack(spacing: 14) {
                    pillarCard(
                        icon: "cpu",
                        color: .purple,
                        title: "Metal GPU Hızlandırma",
                        desc: "whisper.cpp doğrudan M serisi çipin grafik çekirdeklerini kullanır; tamamen yerel ve gizlidir."
                    )
                    
                    pillarCard(
                        icon: "folder.badge.gearshape",
                        color: .green,
                        title: "Otomatik Klasör İzleme",
                        desc: "iCloud Drive veya Sesli Notlar klasörüne yeni bir kayıt düştüğünde arka planda yazıya dökülür."
                    )
                    
                    pillarCard(
                        icon: "sparkles",
                        color: .blue,
                        title: "Akıllı Halüsinasyon Filtresi",
                        desc: "Tekrar döngüleri, alkış ve gürültü etiketleri temizlenerek pürüzsüz metin çıktısı üretilir."
                    )
                }
                .frame(maxWidth: 560)
                
                Spacer(minLength: 20)
            }
            .padding(24)
        }
    }
    
    private func formatChip(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .liquidGlassCapsule(glowColor: .white.opacity(0.3), material: .ultraThinMaterial)
    }
    
    private func pillarCard(icon: String, color: Color, title: String, desc: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
            
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.primary)
            
            Text(desc)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineSpacing(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 12, glowColor: .white.opacity(0.3), material: .ultraThinMaterial)
    }
    
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
}
