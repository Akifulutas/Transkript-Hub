import SwiftUI
import AppKit
import TranskriptHubCore

public struct UnifiedStudioHubView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var quickLinkText: String = ""
    @State private var isDropTargeted: Bool = false
    @State private var isModelAccordionExpanded: Bool = false
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Top 6 Interactive Action Cards (Replaces static KPIs)
                topActionCardsRow
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                
                // Model Selection Accordion (smooth downward expansion)
                if isModelAccordionExpanded {
                    modelAccordionSection
                        .padding(.horizontal, 24)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                }
                
                // 2. Central Floating Hero Card: Drop & Paste Zone
                centralHeroCard
                    .padding(.horizontal, 24)
                
                // 3. Central Queue Section (Kuyruk & "Transkripte Yolla" Action)
                centralQueueSection
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
    
    // MARK: - 1. Top 6 Interactive Action Cards Row
    private var topActionCardsRow: some View {
        HStack(spacing: 10) {
            // Card 1: Model Selection (Interactive Accordion Toggle)
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    isModelAccordionExpanded.toggle()
                }
            }) {
                interactiveCard(
                    icon: "cpu.fill",
                    badgeColor: .orange,
                    caption: "YAPAY ZEKA MODELİ",
                    title: viewModel.selectedModelTitle,
                    subtitle: isModelAccordionExpanded ? "Listeyi Kapat" : "Modeli Değiştir",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            
            // Card 2: Language Selection (Clickable Menu)
            Menu {
                languageMenuButton(code: "auto", title: "🌐 Otomatik Algıla")
                Divider()
                languageMenuButton(code: "tr", title: "🇹🇷 Türkçe")
                languageMenuButton(code: "en", title: "🇬🇧 İngilizce")
                languageMenuButton(code: "de", title: "🇩🇪 Almanca")
            } label: {
                interactiveCard(
                    icon: "globe",
                    badgeColor: .blue,
                    caption: "KONUŞMA DİLİ",
                    title: languageTitle(viewModel.selectedLanguage),
                    subtitle: "Dili Seç",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            
            // Card 3: Clipboard Monitoring (Toggle Button)
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    viewModel.isClipboardMonitoring.toggle()
                }
            }) {
                interactiveCard(
                    icon: viewModel.isClipboardMonitoring ? "doc.on.clipboard.fill" : "doc.on.clipboard",
                    badgeColor: viewModel.isClipboardMonitoring ? .green : .secondary,
                    caption: "PANO İZLEME",
                    title: viewModel.isClipboardMonitoring ? "İzleniyor" : "Kapalı",
                    subtitle: "Otomatik Link",
                    isPulseActive: viewModel.isClipboardMonitoring
                )
            }
            .buttonStyle(.plain)
            
            // Card 4: Live Audio Recording (Dual Mode: Microphone & System Audio)
            Menu {
                Button {
                    Task {
                        await viewModel.startRecording(source: .microphone)
                    }
                } label: {
                    Label("🎙️ Canlı Mikrofon", systemImage: "mic.fill")
                }
                
                Button {
                    Task {
                        await viewModel.startRecording(source: .systemAudio)
                    }
                } label: {
                    Label("🖥️ Bilgisayar / Zoom Sesi", systemImage: "display")
                }
            } label: {
                interactiveCard(
                    icon: viewModel.recordingSource == .microphone ? "mic.fill" : "display",
                    badgeColor: .red,
                    caption: "SES KAYDI",
                    title: viewModel.recordingSource == .microphone ? "Mikrofon" : "Sistem Sesi",
                    subtitle: "Mod Seç (⌘R)",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            
            // Card 5: Watched Folder (Opens Native Sheet)
            Button(action: {
                viewModel.isWatchedFolderPresented = true
            }) {
                interactiveCard(
                    icon: "folder.badge.gearshape.fill",
                    badgeColor: viewModel.isFolderWatching ? .teal : .secondary,
                    caption: "KLASÖR İZLEME",
                    title: viewModel.isFolderWatching ? "1 Klasör Aktif" : "Yapılandır",
                    subtitle: "Otomatik Alma"
                )
            }
            .buttonStyle(.plain)
            
            // Card 6: History & Archive (Navigates to History Section)
            Button(action: {
                viewModel.selectedSection = .history
            }) {
                interactiveCard(
                    icon: "clock.arrow.circlepath",
                    badgeColor: .purple,
                    caption: "GEÇMİŞ & ARŞİV",
                    title: "\(viewModel.historyItems.count) Dosya",
                    subtitle: "Kayıtları Gör"
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Model Selection Accordion Section
    private var modelAccordionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    Text("Whisper Yapay Zeka Modelleri")
                        .font(.system(size: 13, weight: .bold))
                    Text("• \(WhisperModelCatalog.availableModels.count) Model")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        isModelAccordionExpanded = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Text("Kapat")
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            VStack(spacing: 8) {
                ForEach(WhisperModelCatalog.availableModels) { spec in
                    accordionModelRow(spec: spec)
                    if spec.id != WhisperModelCatalog.availableModels.last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: 16, glowColor: .orange.opacity(0.3), material: .ultraThinMaterial)
    }
    
    private func accordionModelRow(spec: WhisperModelSpec) -> some View {
        let isDownloaded = viewModel.modelManager.isModelDownloaded(spec.model)
        let isActive = viewModel.selectedModel == spec.model
        let visuals = modelSpecVisuals(spec)
        
        return HStack(spacing: 12) {
            // Colorful Model Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(visuals.color.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: visuals.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(visuals.color)
            }
            
            // Model Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(spec.displayName)
                        .font(.system(size: 13, weight: .bold))
                    
                    Text(spec.sizeDescription)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    if let badge = spec.badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(visuals.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(visuals.color.opacity(0.12)))
                    }
                    
                    if isActive {
                        Text("Aktif")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .liquidGlassCapsule(glowColor: .accentColor, material: .ultraThinMaterial)
                    }
                }
                
                Text(spec.summary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Inline Action Buttons: Seç, İndir, Sil
            if isDownloaded {
                HStack(spacing: 8) {
                    if !isActive {
                        Button("Seç") {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                viewModel.selectedModel = spec.model
                                isModelAccordionExpanded = false
                            }
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    
                    Button(role: .destructive) {
                        viewModel.deleteModelInSettings(spec.model)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                            Text("Sil")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.red.opacity(0.85))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Model dosyasını diskten sil")
                }
            } else if viewModel.downloadingModel == spec.model {
                VStack(alignment: .trailing, spacing: 4) {
                    ProgressView(value: viewModel.modelDownloadFraction)
                        .progressViewStyle(.linear)
                        .frame(width: 120)
                    Text(viewModel.modelDownloadStatusText.isEmpty ? "İndiriliyor..." : viewModel.modelDownloadStatusText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            } else {
                Button(action: {
                    viewModel.downloadModelInSettings(spec.model)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 11))
                        Text("İndir")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func modelSpecVisuals(_ spec: WhisperModelSpec) -> (icon: String, color: Color) {
        switch spec.model {
        case .largeV3Turbo:
            return ("rocket.fill", .purple)
        case .largeV3TurboQ5:
            return ("bolt.badge.automatic.fill", .cyan)
        case .small:
            return ("sparkles", .green)
        case .base:
            return ("hare.fill", .orange)
        case .tiny:
            return ("leaf.fill", .mint)
        case .medium:
            return ("books.vertical.fill", .blue)
        }
    }
    
    // MARK: - Interactive Card View Builder
    private func interactiveCard(
        icon: String,
        badgeColor: Color,
        caption: String,
        title: String,
        subtitle: String,
        showsChevron: Bool = false,
        isPulseActive: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(badgeColor.opacity(0.16))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(badgeColor)
                }
                
                Spacer()
                
                if isPulseActive {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .shadow(color: Color.green.opacity(0.8), radius: 3)
                } else if showsChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.secondary.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: 14, glowColor: badgeColor.opacity(0.4), material: .ultraThinMaterial)
    }
    
    // MARK: - 2. Central Floating Hero Card: Drop & Paste Zone
    private var centralHeroCard: some View {
        VStack(spacing: 16) {
            // Icon & Explanatory Text
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "arrow.down.doc")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                
                Text("YouTube Bağlantısı Yapıştırın veya Ses Dosyası Bırakın")
                    .font(.system(size: 15, weight: .bold))
            }
            
            // Integrated URL Input Field
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                
                TextField("YouTube linki veya ses dosyası yolu yapıştırın...", text: $quickLinkText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        submitQuickLink()
                    }
                
                if !quickLinkText.isEmpty {
                    Button("Ekle") {
                        submitQuickLink()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .frame(maxWidth: 500)
            
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
                        Text("Ses Dosyası Seç... (⌘O)")
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .liquidGlass(cornerRadius: 18, glowColor: isDropTargeted ? Color.accentColor : Color.white.opacity(0.5), material: .ultraThinMaterial)
        .onDrop(of: [.fileURL, .url], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
    }
    
    // MARK: - 3. Central Queue Section (Kuyruk & "Transkripte Yolla" Action)
    private var centralQueueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Queue Header & Actions
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    
                    Text("Kuyruktaki Öğeler")
                        .font(.system(size: 14, weight: .bold))
                    
                    if !viewModel.queueItems.isEmpty {
                        Text("\(viewModel.queueItems.count)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                    }
                    
                    if viewModel.failedCount > 0 {
                        Text("\(viewModel.failedCount) Hatalı")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.14)))
                    }
                }
                
                Spacer()
                
                // Secondary Actions: Clear & Retry
                if !viewModel.queueItems.isEmpty {
                    if viewModel.failedCount > 0 {
                        Button(action: { viewModel.retryFailedItems() }) {
                            Text("Hatalıları Yeniden Dene")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    Button(action: { viewModel.clearQueueWithUndo() }) {
                        Text("Kuyruğu Temizle")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isProcessing)
                }
                
                // Primary Action Button: "Transkripte Yolla (⌘Return)"
                Button(action: {
                    viewModel.requestStartQueue()
                }) {
                    HStack(spacing: 6) {
                        if viewModel.isProcessing {
                            ProgressView()
                                .controlSize(.small)
                            Text("İşleniyor...")
                                .font(.system(size: 12, weight: .bold))
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .bold))
                            Text("Transkripte Yolla (⌘Return)")
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(viewModel.queueItems.isEmpty || viewModel.isProcessing)
            }
            .padding(.horizontal, 4)
            
            // Live Processing Progress Card
            if viewModel.isProcessing {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(viewModel.currentOperation.isEmpty ? "Deşifre ediliyor..." : viewModel.currentOperation)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.primary)
                        Spacer()
                        Text("%\(Int(viewModel.progressFraction * 100))")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                    }
                    ProgressView(value: viewModel.progressFraction)
                        .progressViewStyle(.linear)
                }
                .padding(12)
                .liquidGlass(cornerRadius: 12, glowColor: Color.accentColor.opacity(0.4), material: .ultraThinMaterial)
            }
            
            // Queue Content: Empty State or Cards List
            if viewModel.queueItems.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                    Text("Kuyruk şu an boş. Yukarıdaki alana link yapıştırabilir veya ses dosyası bırakabilirsiniz.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .liquidGlass(cornerRadius: 12, glowColor: .white.opacity(0.3), material: .ultraThinMaterial)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.queueItems) { item in
                        queueItemRow(item: item)
                    }
                }
            }
        }
    }
    
    // MARK: - Queue Item Row
    private func queueItemRow(item: QueueItem) -> some View {
        Button(action: {
            viewModel.selectedItemID = item.id
        }) {
            HStack(spacing: 12) {
                // Media Type Icon / Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(item.isYouTube ? Color.red.opacity(0.14) : Color.purple.opacity(0.14))
                        .frame(width: 38, height: 38)
                    
                    Image(systemName: item.isYouTube ? "play.rectangle.fill" : "waveform")
                        .font(.system(size: 16))
                        .foregroundStyle(item.isYouTube ? Color.red : Color.purple)
                }
                
                // Title and Subtitle
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 6) {
                        Text(item.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondary)
                        
                        if let dur = item.durationSec {
                            Text("• \(AudioPlayerController.formatTime(dur))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // Status Badge
                HStack(spacing: 6) {
                    stateBadge(for: item.state)
                    
                    Button(action: {
                        viewModel.removeItem(id: item.id)
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .help("Kuyruktan kaldır")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .liquidGlass(cornerRadius: 12, glowColor: .white.opacity(0.3), material: .ultraThinMaterial)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helper Views & Actions
    
    private func stateBadge(for state: QueueItemState) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(badgeColor(for: state))
                .frame(width: 6, height: 6)
            Text(state.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(badgeColor(for: state))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(badgeColor(for: state).opacity(0.14)))
    }
    
    private func badgeColor(for state: QueueItemState) -> Color {
        switch state {
        case .queued: return .secondary
        case .fetching: return .blue
        case .transcribing: return .purple
        case .completed: return .green
        case .failed: return .orange
        }
    }
    
    private func formatChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
    }
    
    private func submitQuickLink() {
        let trimmed = quickLinkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.quickInputText = trimmed
        viewModel.addFromQuickInput()
        quickLinkText = ""
    }
    
    private func selectLocalAudioFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .movie]
        if panel.runModal() == .OK {
            viewModel.addAudioFiles(panel.urls)
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url = url else { return }
                DispatchQueue.main.async {
                    if url.isFileURL {
                        self.viewModel.addAudioFiles([url])
                    } else {
                        self.viewModel.quickInputText = url.absoluteString
                        self.viewModel.addFromQuickInput()
                    }
                }
            }
        }
    }
    
    private func modelDisplayName(_ model: WhisperModel) -> String {
        switch model {
        case .tiny: return "Tiny (75 MB)"
        case .base: return "Base (142 MB)"
        case .small: return "Small (466 MB)"
        case .medium: return "Medium (1.5 GB)"
        case .largeV3Turbo: return "Large-v3-Turbo (1.6 GB)"
        case .largeV3TurboQ5: return "Large-v3-Turbo Q5 (547 MB)"
        }
    }
    
    private func modelSystemIcon(_ model: WhisperModel) -> String {
        switch model {
        case .tiny: return "bolt.fill"
        case .base: return "hare.fill"
        case .small: return "sparkles"
        case .medium: return "waveform"
        case .largeV3Turbo, .largeV3TurboQ5: return "crown.fill"
        }
    }
    
    private func languageTitle(_ code: String) -> String {
        switch code {
        case "auto": return "Otomatik"
        case "tr": return "Türkçe"
        case "en": return "İngilizce"
        case "de": return "Almanca"
        default: return code.uppercased()
        }
    }
    
    private func languageMenuButton(code: String, title: String) -> some View {
        Button {
            viewModel.selectedLanguage = code
        } label: {
            HStack {
                Text(title)
                if viewModel.selectedLanguage == code {
                    Image(systemName: "checkmark")
                }
            }
        }
    }
}
