import SwiftUI
import AppKit
import TranskriptHubCore

public struct UnifiedStudioHubView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var quickLinkText: String = ""
    @State private var isDropTargeted: Bool = false
    @State private var isModelPickerPresented: Bool = false
    @State private var isLanguagePickerPresented: Bool = false
    
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
            // Card 1: Model Selection (Floating Popover anchored under Card 1)
            Button(action: {
                isModelPickerPresented.toggle()
            }) {
                interactiveCard(
                    icon: "cpu.fill",
                    badgeColor: .orange,
                    caption: "YAPAY ZEKA MODELİ",
                    title: viewModel.selectedModelTitle,
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isModelPickerPresented, arrowEdge: .bottom) {
                modelPickerPopover
            }
            
            // Card 2: Language Selection (Floating Popover anchored under Card 2)
            Button(action: {
                isLanguagePickerPresented.toggle()
            }) {
                interactiveCard(
                    icon: "globe",
                    badgeColor: .blue,
                    caption: "KONUŞMA DİLİ",
                    title: languageTitle(viewModel.selectedLanguage),
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isLanguagePickerPresented, arrowEdge: .bottom) {
                languagePickerPopover
            }
            
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
                    isPulseActive: viewModel.isClipboardMonitoring
                )
            }
            .buttonStyle(.plain)
            
            // Card 4: Live Audio Recording (Opens AudioRecordingSourceSheet)
            Button(action: {
                viewModel.isRecordingSourceSheetPresented = true
            }) {
                interactiveCard(
                    icon: viewModel.recordingSource == .microphone ? "mic.fill" : "display",
                    badgeColor: .red,
                    caption: "SES KAYDI",
                    title: viewModel.recordingSource == .microphone ? "Mikrofon" : "Sistem Sesi",
                    showsChevron: true
                )
            }
            .buttonStyle(.plain)
            
            // Card 5: Watched Folder (Opens Native Sheet)
            Button(action: {
                viewModel.isWatchedFolderPresented = true
            }) {
                interactiveCard(
                    icon: "folder.fill.badge.gearshape",
                    badgeColor: viewModel.isFolderWatching ? .teal : .secondary,
                    caption: "KLASÖR İZLEME",
                    title: viewModel.isFolderWatching ? "1 Klasör Aktif" : "Yapılandır"
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
                    title: "\(viewModel.historyItems.count) Dosya"
                )
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Model Selection Popover (Card 1)
    private var modelPickerPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                    Text("Whisper Modelleri")
                        .font(.system(size: 13, weight: .bold))
                }
                
                Spacer()
                
                Text("Boyuta göre sıralı")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 2)
            
            Divider()
            
            VStack(spacing: 6) {
                ForEach(WhisperModelCatalog.availableModels) { spec in
                    popoverModelRow(spec: spec)
                    if spec.id != WhisperModelCatalog.availableModels.last?.id {
                        Divider().opacity(0.3)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 500)
    }
    
    private func popoverModelRow(spec: WhisperModelSpec) -> some View {
        let isDownloaded = viewModel.modelManager.isModelDownloaded(spec.model)
        let isActive = viewModel.selectedModel == spec.model
        let visuals = modelSpecVisuals(spec)
        
        return HStack(spacing: 8) {
            // Colorful Model Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(visuals.color.opacity(0.18))
                    .frame(width: 28, height: 28)
                Image(systemName: visuals.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(visuals.color)
            }
            
            // Model Info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(spec.displayName)
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    
                    Text(spec.sizeDescription)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    
                    if let badge = spec.badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(visuals.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(visuals.color.opacity(0.12)))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                
                Text(spec.summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 8)
            
            // Inline Action Buttons & Status Badges
            if isDownloaded {
                HStack(spacing: 6) {
                    if isActive {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                            Text("Aktif Model")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green))
                        .fixedSize(horizontal: true, vertical: false)
                    } else {
                        Button("Seç") {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                viewModel.selectedModel = spec.model
                                isModelPickerPresented = false
                            }
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .controlSize(.small)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    
                    Button(role: .destructive) {
                        viewModel.deleteModelInSettings(spec.model)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.red.opacity(0.8))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help("Model dosyasını diskten sil")
                    .accessibilityLabel("Model dosyasını diskten sil")
                }
            } else if viewModel.downloadingModel == spec.model {
                HStack(spacing: 6) {
                    VStack(alignment: .trailing, spacing: 3) {
                        ProgressView(value: viewModel.modelDownloadFraction)
                            .progressViewStyle(.linear)
                            .frame(width: 80)
                        Text(viewModel.modelDownloadStatusText.isEmpty ? "İndiriliyor..." : viewModel.modelDownloadStatusText)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    
                    Button(action: {
                        viewModel.cancelModelDownload()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.secondary.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help("İndirmeyi iptal et")
                    .accessibilityLabel("İndirmeyi iptal et")
                }
                .fixedSize(horizontal: true, vertical: false)
            } else {
                Button(action: {
                    viewModel.downloadModelInSettings(spec.model)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 10))
                        Text("İndir")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(.rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - Language Selection Popover (Card 2)
    private var languagePickerPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "globe")
                    .foregroundStyle(.blue)
                    .font(.system(size: 12))
                Text("Konuşma Dili")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
            }
            .padding(.bottom, 2)
            
            Divider()
            
            VStack(spacing: 4) {
                languageOptionRow(code: "auto", flag: "🌐", name: "Otomatik Algıla", desc: "Konuşulan dili ses kaydından otomatik tespit eder")
                languageOptionRow(code: "tr", flag: "🇹🇷", name: "Türkçe", desc: "Türkçe konuşmalar için optimize")
                languageOptionRow(code: "en", flag: "🇬🇧", name: "İngilizce", desc: "İngilizce toplantı ve kayıtlar")
                languageOptionRow(code: "de", flag: "🇩🇪", name: "Almanca", desc: "Almanca kayıtlar ve sesli notlar")
            }
        }
        .padding(12)
        .frame(width: 280)
    }
    
    private func languageOptionRow(code: String, flag: String, name: String, desc: String) -> some View {
        let isSelected = viewModel.selectedLanguage == code
        return Button(action: {
            viewModel.selectedLanguage = code
            isLanguagePickerPresented = false
        }) {
            HStack(spacing: 10) {
                Text(flag)
                    .font(.system(size: 18))
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))
                    Text(desc)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .font(.system(size: 13))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func modelSpecVisuals(_ spec: WhisperModelSpec) -> (icon: String, color: Color) {
        switch spec.model {
        case .largeV3Turbo:
            return ("flame.fill", .purple)
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
        showsChevron: Bool = false,
        isPulseActive: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(badgeColor.opacity(0.16))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(badgeColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                
                Text(title)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 2)
            
            if isPulseActive {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                    .shadow(color: Color.green.opacity(0.8), radius: 3)
            } else if showsChevron {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .liquidGlass(cornerRadius: 12, glowColor: badgeColor.opacity(0.35), material: .ultraThinMaterial)
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
                
                Text(isDropTargeted ? "Dosyaları Buraya Bırakın" : "Ses Dosyası veya Bağlantı Ekleyin")
                    .font(.system(size: 15, weight: .bold))
            }
            
            // Integrated URL Input Field
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                
                TextField("YouTube bağlantısı yapıştırın...", text: $quickLinkText)
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
                
                // Secondary Actions: Retry Failed
                if !viewModel.queueItems.isEmpty && viewModel.failedCount > 0 {
                    Button(action: { viewModel.retryFailedItems() }) {
                        Text("Hatalıları Yeniden Dene")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                // Primary Action Button: "Transkripte Yolla"
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
                            Text("Transkripte Yolla")
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
                    
                    // Bottom Circular Clear Queue Button (Icon-only)
                    HStack {
                        Spacer()
                        Button(action: {
                            viewModel.clearQueueWithUndo()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Color.secondary.opacity(0.55))
                                .padding(6)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isProcessing)
                        .help("Kuyruğu Temizle")
                        .accessibilityLabel("Kuyruğu Temizle")
                        Spacer()
                    }
                    .padding(.top, 2)
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
                        .frame(width: 48, height: 36)
                    
                    if let thumbURL = item.thumbnailURL {
                        AsyncImage(url: thumbURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 48, height: 36)
                                    .clipped()
                            case .failure:
                                Image(systemName: item.isYouTube ? "play.rectangle.fill" : "waveform")
                                    .font(.system(size: 16))
                                    .foregroundStyle(item.isYouTube ? Color.red : Color.purple)
                            case .empty:
                                ProgressView()
                                    .controlSize(.mini)
                            @unknown default:
                                EmptyView()
                            }
                        }
                        .frame(width: 48, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Image(systemName: item.isYouTube ? "play.rectangle.fill" : "waveform")
                            .font(.system(size: 16))
                            .foregroundStyle(item.isYouTube ? Color.red : Color.purple)
                    }
                }
                .frame(width: 48, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                )
                
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
                    .accessibilityLabel("Kuyruktan kaldır")
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
}
