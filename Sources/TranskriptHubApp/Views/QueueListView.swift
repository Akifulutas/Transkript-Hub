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
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.system(size: 11))
                                Text("\(viewModel.t("status_attention_required")) (\(viewModel.failedItems.count))")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.orange)
                                Spacer()
                                Button(viewModel.t("action_retry_all")) {
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
                            }
                        } header: {
                            Text("\(viewModel.t("status_processing_queue")) (\(viewModel.activeOrQueuedItems.count))")
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
                            }
                        } header: {
                            Text("\(viewModel.t("status_completed")) (\(viewModel.completedItems.count))")
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
                                Text(viewModel.selectedItemIDs.count == viewModel.queueItems.count ? viewModel.t("action_deselect") : (viewModel.selectedItemIDs.count > 1 ? "\(viewModel.selectedItemIDs.count) \(viewModel.t("hub_selected"))" : "\(viewModel.t("action_select_all")) (⌘A)"))
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
                                    Text(viewModel.t("action_clear_queue"))
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
        .navigationTitle(viewModel.t("section_queue"))
        .onDrop(of: [.fileURL, .url, .item, .content, .text], isTargeted: $viewModel.isDropTargetActive) { providers in
            handleUniversalDrop(providers: providers)
        }
    }
    
    // MARK: - Actionable Header (No AI Slop, First 2 Seconds Rule)
    private var actionableHeader: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(viewModel.isProcessing ? Color.Premium.cashmereViolet : (viewModel.failedCount > 0 ? Color.Premium.terracotta : Color.Premium.emeraldMineral))
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
                        Text(viewModel.t("action_retry"))
                    }
                    .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .foregroundColor(Color.Premium.terracotta)
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
                
                TextField(viewModel.t("action_quick_add_placeholder"), text: $viewModel.quickInputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit {
                        viewModel.addFromQuickInput()
                    }
                
                if !viewModel.quickInputText.isEmpty {
                    Button(action: { viewModel.addFromQuickInput() }) {
                        Text(viewModel.t("action_add"))
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
                    Label("\(viewModel.t("action_paste_clipboard")) (⌘V)", systemImage: "doc.on.clipboard")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .hoverHelpTooltip(
                    title: viewModel.t("hub_tooltip_paste_btn_title"),
                    description: viewModel.t("hub_tooltip_paste_btn_desc"),
                    icon: "doc.on.clipboard",
                    statusColor: .accentColor,
                    placement: .bottomLeading,
                    width: 240
                )
                
                Button(action: { selectLocalAudioFiles() }) {
                    Label(viewModel.t("action_audio_file"), systemImage: "waveform")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .hoverHelpTooltip(
                    title: viewModel.t("hub_tooltip_choose_file_title"),
                    description: viewModel.t("hub_tooltip_choose_file_desc"),
                    icon: "waveform",
                    statusColor: .secondary,
                    placement: .bottomLeading,
                    width: 240
                )
                
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
            statusTitle: viewModel.localizedState(item.state),
            onRemove: { viewModel.removeItem(id: item.id) },
            onCopyTranscript: { viewModel.copyTranscriptContent(for: item) },
            onOpenFinder: { viewModel.openItemOutputInFinder(item) }
        )
        .contextMenu { rowContextMenu(item: item) }
    }
    
    @ViewBuilder
    private func rowContextMenu(item: QueueItem) -> some View {
        if item.state == .failed {
            Button(viewModel.t("action_retry")) {
                viewModel.retryItem(id: item.id)
            }
        }
        if let transcript = item.transcript {
            Button("\(viewModel.t("action_copy")) (⌘⇧C)") {
                viewModel.copyTranscript(text: transcript)
            }
        }
        if let output = item.outputURL {
            Button(viewModel.t("action_open_finder")) {
                viewModel.openInFinder(path: output.path)
            }
        }
        if let url = item.canonicalURL {
            Button(viewModel.t("action_open_browser")) {
                viewModel.openInBrowser(url: url)
            }
        }
        Divider()
        Button(viewModel.t("action_remove_item"), role: .destructive) {
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
                Text(viewModel.t("action_empty_queue_title"))
                    .font(.system(size: 14, weight: .semibold))
                
                Text(viewModel.t("action_empty_queue_desc"))
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
        viewModel.handleUniversalDrop(providers: providers)
    }
}

// MARK: - Standard View Row (Apple Studio Hierarchy)
struct StandardQueueRow: View {
    let item: QueueItem
    let isSelected: Bool
    var statusTitle: String? = nil
    var onRemove: (() -> Void)? = nil
    var onCopyTranscript: (() -> Void)? = nil
    var onOpenFinder: (() -> Void)? = nil
    @State private var isHovered: Bool = false
    @State private var isCopied: Bool = false
    
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
                .help(L10n.tr("action_remove_item"))
                .transition(.opacity)
            }
            
            // Quick Copy Transcript for completed items
            if item.state == .completed {
                Button(action: {
                    onCopyTranscript?()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isCopied = true
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCopied = false
                        }
                    }
                }) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isCopied ? Color.Premium.emeraldMineral : .accentColor)
                        .padding(5)
                        .background(Circle().fill(isCopied ? Color.Premium.emeraldMineral.opacity(0.20) : Color.accentColor.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .hoverHelpTooltip(
                    title: L10n.tr("action_copy_transcript"),
                    description: L10n.tr("hub_tooltip_copy_transcript_desc"),
                    icon: isCopied ? "checkmark" : "doc.on.doc",
                    statusColor: isCopied ? Color.Premium.emeraldMineral : .accentColor,
                    placement: .topTrailing,
                    width: 220
                )
            }
            
            // Quick Open in Finder for completed items
            if item.state == .completed {
                Button(action: { onOpenFinder?() }) {
                    Image(systemName: "folder")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .padding(5)
                        .background(Circle().fill(Color.accentColor.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .hoverHelpTooltip(
                    title: L10n.tr("hub_tooltip_finder_title"),
                    description: L10n.tr("hub_tooltip_finder_desc"),
                    icon: "folder",
                    statusColor: .accentColor,
                    placement: .topTrailing,
                    width: 220
                )
            }
            
            // Liquid Glass Status Pill
            LiquidStatusPill(state: item.state, title: statusTitle)
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
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 60, height: 34)
                        .clipped()
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
            .frame(width: 60, height: 34)
        } else {
            fallbackIcon
        }
    }
    
    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(item.isYouTube ? Color.Premium.crimsonVelvet.opacity(0.14) : Color.Premium.cashmereViolet.opacity(0.14))
                .frame(width: 60, height: 34)
            
            Image(systemName: item.isYouTube ? "play.tv.fill" : "waveform")
                .foregroundColor(item.isYouTube ? Color.Premium.crimsonVelvet : Color.Premium.cashmereViolet)
                .font(.system(size: 13))
        }
    }
}

// MARK: - Liquid Glass Status Pill (Strict H / 2 Capsule Rule)
struct LiquidStatusPill: View {
    let state: QueueItemState
    var title: String? = nil
    var compact: Bool = false
    
    private var displayTitle: String {
        title ?? state.rawValue
    }
    
    var body: some View {
        Group {
            switch state {
            case .queued:
                Text(displayTitle)
                    .font(.system(size: compact ? 9 : 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, compact ? 5 : 8)
                    .padding(.vertical, compact ? 1 : 3)
                    .liquidGlassCapsule(glowColor: .secondary.opacity(0.4), material: .ultraThinMaterial)
                
            case .fetching:
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    if !compact {
                        Text(displayTitle)
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .foregroundColor(Color.Premium.slateAzure)
                .padding(.horizontal, compact ? 5 : 8)
                .padding(.vertical, compact ? 1 : 3)
                .liquidGlassCapsule(glowColor: Color.Premium.slateAzure, material: .ultraThinMaterial)
                
            case .transcribing:
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    if !compact {
                        Text(displayTitle)
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .foregroundColor(Color.Premium.cashmereViolet)
                .padding(.horizontal, compact ? 5 : 8)
                .padding(.vertical, compact ? 1 : 3)
                .liquidGlassCapsule(glowColor: Color.Premium.cashmereViolet, material: .ultraThinMaterial)
                
            case .completed:
                HStack(spacing: 3) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                    if !compact {
                        Text(displayTitle)
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .foregroundColor(Color.Premium.emeraldMineral)
                .padding(.horizontal, compact ? 5 : 8)
                .padding(.vertical, compact ? 1 : 3)
                .liquidGlassCapsule(glowColor: Color.Premium.emeraldMineral, material: .ultraThinMaterial)
                
            case .failed:
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                    if !compact {
                        Text(displayTitle)
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .foregroundColor(Color.Premium.terracotta)
                .padding(.horizontal, compact ? 5 : 8)
                .padding(.vertical, compact ? 1 : 3)
                .liquidGlassCapsule(glowColor: Color.Premium.terracotta, material: .ultraThinMaterial)
            }
        }
    }
}
