import SwiftUI
import AppKit
import TranskriptHubCore

struct QueueListView: View {
    @ObservedObject var viewModel: AppViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Actionable Status Header (First 2 Seconds Rule)
            actionableHeader
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
            
            Divider()
            
            // Quick Add Input Bar (Liquid Glass Capsule)
            quickAddBar
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 8)
            
            Divider()
            
            // Queue Content (Empty State or Grouped List)
            if viewModel.queueItems.isEmpty {
                emptyQueueView
            } else {
                List(selection: $viewModel.selectedItemIDs) {
                    // 1. Müdahale Gerekiyor Group (Pinned to Top with Amber Glow)
                    if !viewModel.failedItems.isEmpty {
                        Section {
                            ForEach(viewModel.failedItems) { item in
                                queueRow(for: item)
                                    .tag(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.selectedItemID = item.id
                                    }
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 11))
                                Text("MÜDAHALE GEREKİYOR (\(viewModel.failedItems.count))")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.orange)
                                Spacer()
                                Button("Tümünü Yeniden Dene") {
                                    viewModel.retryFailedItems()
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    // 2. İşleniyor ve Kuyrukta Olanlar
                    if !viewModel.activeOrQueuedItems.isEmpty {
                        Section {
                            ForEach(viewModel.activeOrQueuedItems) { item in
                                queueRow(for: item)
                                    .tag(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.selectedItemID = item.id
                                    }
                            }
                        } header: {
                            Text("İŞLENİYOR & KUYRUK (\(viewModel.activeOrQueuedItems.count))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        }
                    }
                    
                    // 3. Tamamlananlar (Sakin Nötr Tonlar)
                    if !viewModel.completedItems.isEmpty {
                        Section {
                            ForEach(viewModel.completedItems) { item in
                                queueRow(for: item)
                                    .tag(item.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.selectedItemID = item.id
                                    }
                            }
                        } header: {
                            Text("TAMAMLANANLAR (\(viewModel.completedItems.count))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 4)
                        }
                    }
                    
                    // 4. Kuyruğun Sonu: Kuyruğu Temizle & Tümünü Seç
                    Section {
                        HStack(spacing: 12) {
                            Spacer()
                            
                            Button(action: {
                                if viewModel.selectedItemIDs.count == viewModel.queueItems.count {
                                    viewModel.deselectAllQueueItems()
                                } else {
                                    viewModel.selectAllQueueItems()
                                }
                            }) {
                                Text(viewModel.selectedItemIDs.count == viewModel.queueItems.count ? "Seçimi Kaldır" : (viewModel.selectedItemIDs.count > 1 ? "\(viewModel.selectedItemIDs.count) Seçili" : "Tümünü Seç (⌘A)"))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            
                            Text("•")
                                .foregroundColor(.secondary.opacity(0.3))
                            
                            Button(action: { viewModel.clearQueueWithUndo() }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11))
                                    Text("Kuyruğu Temizle")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isProcessing)
                            
                            Spacer()
                        }
                        .padding(.vertical, 12)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Kuyruk")
        .onDrop(of: [.fileURL, .text], isTargeted: $viewModel.isDropTargetActive) { providers in
            handleUniversalDrop(providers: providers)
        }
    }
    
    // MARK: - Actionable Header (No AI Slop, First 2 Seconds Rule)
    private var actionableHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.isProcessing ? Color.purple : (viewModel.failedCount > 0 ? Color.orange : Color.green))
                .frame(width: 8, height: 8)
            
            Text(viewModel.actionableSummary)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer()
            
            if viewModel.failedCount > 0 {
                Button(action: { viewModel.retryFailedItems() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Yeniden Dene")
                    }
                    .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .foregroundColor(.orange)
            }
        }
    }
    
    // MARK: - Quick Add Bar (Liquid Glass Capsule)
    private var quickAddBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "link.badge.plus")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 13))
                
                TextField("YouTube linki veya ses dosyası...", text: $viewModel.quickInputText)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .liquidGlassCapsule(glowColor: .white.opacity(0.8), material: .ultraThinMaterial)
            
            // Quick Ingestion Pill Buttons (H / 2 Capsule Rule)
            HStack(spacing: 12) {
                Button(action: { viewModel.addFromClipboard() }) {
                    Label("Panodan (⌘V)", systemImage: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Button(action: { selectLocalAudioFiles() }) {
                    Label("Ses Dosyası...", systemImage: "waveform")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Row Dispatcher
    @ViewBuilder
    private func queueRow(for item: QueueItem) -> some View {
        StandardQueueRow(
            item: item,
            isSelected: viewModel.selectedItemID == item.id,
            onRemove: { viewModel.removeItem(id: item.id) }
        )
        .contextMenu { rowContextMenu(item: item) }
    }
    
    @ViewBuilder
    private func rowContextMenu(item: QueueItem) -> some View {
        if item.state == .failed {
            Button("Tekrar Dene") {
                viewModel.retryItem(id: item.id)
            }
        }
        if let transcript = item.transcript {
            Button("Metni Kopyala (⌘⇧C)") {
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
    
    // MARK: - Empty State (8-State Matrix)
    private var emptyQueueView: some View {
        VStack(spacing: 12) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 52, height: 52)
                
                Image(systemName: "tray")
                    .font(.system(size: 22))
                    .foregroundColor(.accentColor)
            }
            
            VStack(spacing: 3) {
                Text("Kuyruk Boş")
                    .font(.system(size: 14, weight: .semibold))
                
                Text("Panodaki linki almak için ⌘V tuşlayın veya dosyaları sağdaki stüdyo alanına sürükleyin.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 240)
                    .lineSpacing(2)
            }
            
            Spacer()
        }
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
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                    DispatchQueue.main.async {
                        viewModel.addAudioFiles([url])
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier("public.text") {
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

// MARK: - Standard View Row (Apple Studio Hierarchy)
struct StandardQueueRow: View {
    let item: QueueItem
    let isSelected: Bool
    var onRemove: (() -> Void)? = nil
    @State private var isHovered: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Video Thumbnail or Kind Icon
            thumbnailView
            
            // Text Details
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    if item.isNewlyDiscovered {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 6, height: 6)
                    }
                    
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if let err = item.errorMessage {
                        Text("• \(err)")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Hover action: quick delete button
            if isHovered && !item.isInProgress {
                Button(action: { onRemove?() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.secondary.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .help("Kuyruktan Çıkar")
                .transition(.opacity)
            }
            
            // Liquid Glass Status Pill
            LiquidStatusPill(state: item.state)
        }
        .padding(.vertical, 3)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }
    
    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbURL = item.effectiveThumbnailURL {
            AsyncImage(url: thumbURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .frame(width: 54, height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                        )
                case .failure, .empty:
                    fallbackIcon
                @unknown default:
                    fallbackIcon
                }
            }
            .frame(width: 54, height: 32)
        } else {
            fallbackIcon
        }
    }
    
    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(item.isYouTube ? Color.red.opacity(0.14) : Color.purple.opacity(0.14))
                .frame(width: 44, height: 30)
            
            Image(systemName: item.isYouTube ? "play.tv.fill" : "waveform")
                .foregroundColor(item.isYouTube ? .red : .purple)
                .font(.system(size: 13))
        }
    }
}

// MARK: - Liquid Glass Status Pill (Strict H / 2 Capsule Rule)
struct LiquidStatusPill: View {
    let state: QueueItemState
    var compact: Bool = false
    
    var body: some View {
        Group {
            switch state {
            case .queued:
                Text(state.rawValue)
                    .font(.system(size: compact ? 9 : 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, compact ? 5 : 8)
                    .padding(.vertical, compact ? 1 : 3)
                    .liquidGlassCapsule(glowColor: .secondary.opacity(0.4), material: .ultraThinMaterial)
                
            case .fetching:
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    if !compact {
                        Text(state.rawValue)
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .foregroundColor(.blue)
                .padding(.horizontal, compact ? 5 : 8)
                .padding(.vertical, compact ? 1 : 3)
                .liquidGlassCapsule(glowColor: .blue, material: .ultraThinMaterial)
                
            case .transcribing:
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    if !compact {
                        Text(state.rawValue)
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .foregroundColor(.purple)
                .padding(.horizontal, compact ? 5 : 8)
                .padding(.vertical, compact ? 1 : 3)
                .liquidGlassCapsule(glowColor: .purple, material: .ultraThinMaterial)
                
            case .completed:
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                    if !compact {
                        Text(state.rawValue)
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .foregroundColor(.green)
                .padding(.horizontal, compact ? 5 : 8)
                .padding(.vertical, compact ? 1 : 3)
                .liquidGlassCapsule(glowColor: .green, material: .ultraThinMaterial)
                
            case .failed:
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                    if !compact {
                        Text(state.rawValue)
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .foregroundColor(.orange)
                .padding(.horizontal, compact ? 5 : 8)
                .padding(.vertical, compact ? 1 : 3)
                .liquidGlassCapsule(glowColor: .orange, material: .ultraThinMaterial)
            }
        }
    }
}
