import SwiftUI
import AppKit
import TranskriptHubCore

public struct UnifiedStudioHubView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isDropTargeted: Bool = false
    @State private var isModelPickerPresented: Bool = false
    @State private var isLanguagePickerPresented: Bool = false
    @State private var studioTourTargets: [StudioTourStep: CGRect] = [:]
    
    // Dedicated 'i' Info Popover States
    @State private var isModelInfoPresented: Bool = false
    @State private var isLanguageInfoPresented: Bool = false
    @State private var isClipboardInfoPresented: Bool = false
    @State private var isRecordingInfoPresented: Bool = false
    @State private var isFolderInfoPresented: Bool = false
    @State private var isHistoryInfoPresented: Bool = false
    @State private var isQueueInfoPresented: Bool = false
    @State private var isSortPopoverPresented: Bool = false
    
    // Interactive Pull-to-Refresh State
    @State private var pullOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var currentScrollY: CGFloat = 0
    @State private var isRefreshing: Bool = false
    @State private var hasTriggeredInCurrentPull: Bool = false
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ZStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Offset tracking anchor
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: HubScrollOffsetPreferenceKey.self,
                                value: proxy.frame(in: .named("HubScrollViewCoordinateSpace")).minY
                            )
                        }
                        .frame(height: 0)
                        
                        // Interactive Pull-To-Refresh Rotating Indicator (GitHub-style)
                        PullRefreshIndicatorView(
                            effectiveOffset: max(0, max(pullOffset, dragOffset)),
                            isRefreshing: isRefreshing || viewModel.isPullRefreshing,
                            onTap: { executeRefresh() }
                        )
                        
                        VStack(spacing: 20) {
                            // 1. Top 6 Interactive Action Cards (Replaces static KPIs)
                            topActionCardsRow
                                .padding(.horizontal, 24)
                                .padding(.top, 14)
                            
                            // 2. Central Queue Section (Directly under the action cards)
                            centralQueueSection
                                .id(StudioTourStep.heroDropAndPaste.id)
                                .studioTourTarget(.heroDropAndPaste)
                                .padding(.horizontal, 24)
                                .padding(.bottom, 28)
                        }
                    }
                }
                .coordinateSpace(name: "HubScrollViewCoordinateSpace")
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { gesture in
                            guard !isRefreshing else { return }
                            // Only track downward drag if the scroll view is at the top (not scrolled down into list)
                            guard currentScrollY >= -5 else { return }
                            if gesture.translation.height > 0 {
                                dragOffset = gesture.translation.height
                            }
                        }
                        .onEnded { gesture in
                            guard !isRefreshing else { return }
                            guard currentScrollY >= -5 else {
                                dragOffset = 0
                                return
                            }
                            if dragOffset >= 48 && !hasTriggeredInCurrentPull {
                                hasTriggeredInCurrentPull = true
                                executeRefresh()
                            } else {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    dragOffset = 0
                                }
                            }
                        }
                )
                .onPreferenceChange(HubScrollOffsetPreferenceKey.self) { value in
                    currentScrollY = value
                    guard !isRefreshing else { return }
                    let positive = max(0, value)
                    pullOffset = positive
                    
                    // Reset latch when scroll returns near resting position
                    if positive < 10 {
                        hasTriggeredInCurrentPull = false
                    }
                    
                    // Trigger refresh when pulled beyond threshold (~50px)
                    if positive >= 48 && !hasTriggeredInCurrentPull {
                        hasTriggeredInCurrentPull = true
                        executeRefresh()
                    }
                }
                .onChange(of: viewModel.isPullRefreshing) { _, newValue in
                    if newValue && !isRefreshing {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isRefreshing = true
                        }
                    } else if !newValue && isRefreshing {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isRefreshing = false
                            dragOffset = 0
                            pullOffset = 0
                        }
                    }
                }
                .onDrop(of: [.fileURL, .url, .item, .content, .text], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers: providers)
                    return true
                }
                .onChange(of: viewModel.spotlightTourCurrentStep) { _, newStep in
                    if viewModel.isSpotlightTourActive {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            scrollProxy.scrollTo(newStep, anchor: .center)
                        }
                    }
                }
            }
            .onPreferenceChange(StudioTourTargetPreferenceKey.self) { targets in
                self.studioTourTargets = targets
            }
            
            // Interactive In-App Spotlight Guided Tour Overlay (Game-like walkthrough)
            if viewModel.isSpotlightTourActive {
                InteractiveSpotlightTourView(
                    viewModel: viewModel,
                    targetFrames: studioTourTargets
                )
                .transition(.opacity)
                .zIndex(999999)
            }
        }
        .coordinateSpace(name: "StudioTourCoordinateSpace")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
    
    private func executeRefresh() {
        guard !isRefreshing else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            isRefreshing = true
        }
        Task {
            await viewModel.triggerManualRefresh()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isRefreshing = false
                dragOffset = 0
                pullOffset = 0
            }
        }
    }
    
    // MARK: - 1. Top 6 Interactive Action Cards Row
    private var topActionCardsRow: some View {
        HStack(spacing: 10) {
            // Card 1: Model Selection (Floating Popover anchored under Card 1)
            ZStack(alignment: .topTrailing) {
                Button(action: {
                    isModelPickerPresented.toggle()
                }) {
                    StudioInteractiveCardView(
                        icon: "cpu.fill",
                        badgeColor: Color.Premium.champagneBronze,
                        caption: viewModel.t("hub_card_model"),
                        title: viewModel.selectedModelTitle,
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isModelPickerPresented, arrowEdge: .bottom) {
                    modelPickerPopover
                }
                .hoverHelpTooltip(
                    title: viewModel.t("hub_tooltip_model_title"),
                    description: viewModel.t("hub_tooltip_model_desc"),
                    icon: "cpu.fill",
                    status: viewModel.selectedModelTitle,
                    statusColor: Color.Premium.champagneBronze,
                    hint: viewModel.t("hub_tooltip_model_hint"),
                    placement: .bottomLeading
                )
                
                // Card 1 'i' Info Button
                Button(action: {
                    isModelInfoPresented.toggle()
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(isModelInfoPresented ? Color.Premium.champagneBronze : Color.secondary.opacity(0.45))
                        .padding(.trailing, 8)
                        .padding(.top, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isModelInfoPresented, arrowEdge: .bottom) {
                    StudioCompactInfoPopover(
                        title: viewModel.t("hub_tooltip_model_title"),
                        description: viewModel.t("hub_tooltip_model_desc"),
                        icon: "cpu.fill",
                        tintColor: Color.Premium.champagneBronze,
                        onDismiss: { isModelInfoPresented = false }
                    )
                }
            }
            .studioTourTarget(.modelSelection)
            .id(StudioTourStep.modelSelection.id)
            
            // Card 2: Language Selection (Floating Popover anchored under Card 2)
            ZStack(alignment: .topTrailing) {
                Button(action: {
                    isLanguagePickerPresented.toggle()
                }) {
                    StudioInteractiveCardView(
                        icon: "globe",
                        badgeColor: Color.Premium.slateAzure,
                        caption: viewModel.t("hub_card_speech_language"),
                        title: languageTitle(viewModel.selectedLanguage),
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isLanguagePickerPresented, arrowEdge: .bottom) {
                    languagePickerPopover
                }
                .hoverHelpTooltip(
                    title: viewModel.t("hub_tooltip_language_title"),
                    description: viewModel.t("hub_tooltip_language_desc"),
                    icon: "globe",
                    status: languageTitle(viewModel.selectedLanguage),
                    statusColor: Color.Premium.slateAzure,
                    hint: viewModel.t("hub_tooltip_language_hint"),
                    placement: .bottomLeading
                )
                
                // Card 2 'i' Info Button
                Button(action: {
                    isLanguageInfoPresented.toggle()
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(isLanguageInfoPresented ? Color.Premium.slateAzure : Color.secondary.opacity(0.45))
                        .padding(.trailing, 8)
                        .padding(.top, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isLanguageInfoPresented, arrowEdge: .bottom) {
                    StudioCompactInfoPopover(
                        title: viewModel.t("hub_tooltip_language_title"),
                        description: viewModel.t("hub_tooltip_language_desc"),
                        icon: "globe",
                        tintColor: Color.Premium.slateAzure,
                        onDismiss: { isLanguageInfoPresented = false }
                    )
                }
            }
            .studioTourTarget(.languageSelection)
            .id(StudioTourStep.languageSelection.id)
            
            // Card 3: Clipboard Monitoring (Toggle Button)
            ZStack(alignment: .topTrailing) {
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        viewModel.isClipboardMonitoring.toggle()
                    }
                }) {
                    StudioInteractiveCardView(
                        icon: viewModel.isClipboardMonitoring ? "doc.on.clipboard.fill" : "doc.on.clipboard",
                        badgeColor: viewModel.isClipboardMonitoring ? Color.Premium.emeraldMineral : .secondary,
                        caption: viewModel.t("hub_card_clipboard"),
                        title: viewModel.isClipboardMonitoring ? viewModel.t("hub_status_monitoring") : viewModel.t("hub_status_off"),
                        isPulseActive: viewModel.isClipboardMonitoring
                    )
                }
                .buttonStyle(.plain)
                .hoverHelpTooltip(
                    title: viewModel.t("hub_tooltip_clipboard_title"),
                    description: viewModel.t("hub_tooltip_clipboard_desc"),
                    icon: viewModel.isClipboardMonitoring ? "doc.on.clipboard.fill" : "doc.on.clipboard",
                    status: viewModel.isClipboardMonitoring ? viewModel.t("hub_status_monitoring") : viewModel.t("hub_status_off"),
                    statusColor: viewModel.isClipboardMonitoring ? Color.Premium.emeraldMineral : .secondary,
                    hint: viewModel.t("hub_tooltip_clipboard_hint"),
                    placement: .bottom
                )
                
                // Card 3 'i' Info Button
                Button(action: {
                    isClipboardInfoPresented.toggle()
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(isClipboardInfoPresented ? Color.Premium.emeraldMineral : Color.secondary.opacity(0.45))
                        .padding(.trailing, 8)
                        .padding(.top, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isClipboardInfoPresented, arrowEdge: .bottom) {
                    StudioCompactInfoPopover(
                        title: viewModel.t("hub_tooltip_clipboard_title"),
                        description: viewModel.t("hub_tooltip_clipboard_desc"),
                        icon: "doc.on.clipboard.fill",
                        tintColor: Color.Premium.emeraldMineral,
                        onDismiss: { isClipboardInfoPresented = false }
                    )
                }
            }
            .studioTourTarget(.clipboardMonitoring)
            .id(StudioTourStep.clipboardMonitoring.id)
            
            // Card 4: Live Audio Recording (Opens AudioRecordingSourceSheet)
            ZStack(alignment: .topTrailing) {
                Button(action: {
                    viewModel.isRecordingSourceSheetPresented = true
                }) {
                    StudioInteractiveCardView(
                        icon: viewModel.recordingSource == .microphone ? "mic.fill" : "display",
                        badgeColor: Color.Premium.crimsonVelvet,
                        caption: viewModel.t("hub_card_recording"),
                        title: viewModel.recordingSource == .microphone ? viewModel.t("record_source_mic") : viewModel.t("record_source_system"),
                        showsChevron: true
                    )
                }
                .buttonStyle(.plain)
                .hoverHelpTooltip(
                    title: viewModel.t("hub_tooltip_recording_title"),
                    description: viewModel.t("hub_tooltip_recording_desc"),
                    icon: viewModel.recordingSource == .microphone ? "mic.fill" : "display",
                    status: viewModel.recordingSource == .microphone ? viewModel.t("record_source_mic") : viewModel.t("record_source_system"),
                    statusColor: Color.Premium.crimsonVelvet,
                    hint: viewModel.t("hub_tooltip_recording_hint"),
                    placement: .bottom
                )
                
                // Card 4 'i' Info Button
                Button(action: {
                    isRecordingInfoPresented.toggle()
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(isRecordingInfoPresented ? Color.Premium.crimsonVelvet : Color.secondary.opacity(0.45))
                        .padding(.trailing, 8)
                        .padding(.top, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isRecordingInfoPresented, arrowEdge: .bottom) {
                    StudioCompactInfoPopover(
                        title: viewModel.t("hub_tooltip_recording_title"),
                        description: viewModel.t("hub_tooltip_recording_desc"),
                        icon: "mic.fill",
                        tintColor: Color.Premium.crimsonVelvet,
                        onDismiss: { isRecordingInfoPresented = false }
                    )
                }
            }
            .studioTourTarget(.audioRecording)
            .id(StudioTourStep.audioRecording.id)
            
            // Card 5: Watched Folder (Opens Native Sheet)
            ZStack(alignment: .topTrailing) {
                Button(action: {
                    viewModel.isWatchedFolderPresented = true
                }) {
                    let activeCount = [
                        viewModel.folderWatcher.watchiCloudDrive,
                        viewModel.folderWatcher.watchVoiceMemos,
                        viewModel.folderWatcher.watchCustomFolder
                    ].filter { $0 }.count
                    StudioInteractiveCardView(
                        icon: "folder.fill.badge.gearshape",
                        badgeColor: activeCount > 0 ? Color.Premium.obsidianTeal : .secondary,
                        caption: viewModel.t("hub_card_watched_folder"),
                        title: activeCount > 0 ? String(format: viewModel.t("hub_sources_active"), activeCount) : viewModel.t("hub_configure")
                    )
                }
                .buttonStyle(.plain)
                .hoverHelpTooltip(
                    title: viewModel.t("hub_tooltip_folder_title"),
                    description: viewModel.t("hub_tooltip_folder_desc"),
                    icon: "folder.fill.badge.gearshape",
                    statusColor: Color.Premium.obsidianTeal,
                    hint: viewModel.t("hub_tooltip_folder_hint"),
                    placement: .bottomTrailing
                )
                
                // Card 5 'i' Info Button
                Button(action: {
                    isFolderInfoPresented.toggle()
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(isFolderInfoPresented ? Color.Premium.obsidianTeal : Color.secondary.opacity(0.45))
                        .padding(.trailing, 8)
                        .padding(.top, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isFolderInfoPresented, arrowEdge: .bottom) {
                    StudioCompactInfoPopover(
                        title: viewModel.t("hub_tooltip_folder_title"),
                        description: viewModel.t("hub_tooltip_folder_desc"),
                        icon: "folder.fill.badge.gearshape",
                        tintColor: Color.Premium.obsidianTeal,
                        onDismiss: { isFolderInfoPresented = false }
                    )
                }
            }
            .studioTourTarget(.watchedFolders)
            .id(StudioTourStep.watchedFolders.id)
            
            // Card 6: History & Archive (Navigates to History Section)
            ZStack(alignment: .topTrailing) {
                Button(action: {
                    viewModel.selectedSection = .history
                }) {
                    StudioInteractiveCardView(
                        icon: "clock.arrow.circlepath",
                        badgeColor: Color.Premium.cashmereViolet,
                        caption: viewModel.t("hub_card_history"),
                        title: String(format: viewModel.t("hub_files_count"), viewModel.historyItems.count)
                    )
                }
                .buttonStyle(.plain)
                
                // Card 6 'i' Info Button
                Button(action: {
                    isHistoryInfoPresented.toggle()
                }) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(isHistoryInfoPresented ? Color.Premium.cashmereViolet : Color.secondary.opacity(0.45))
                        .padding(.trailing, 8)
                        .padding(.top, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isHistoryInfoPresented, arrowEdge: .bottom) {
                    StudioCompactInfoPopover(
                        title: viewModel.t("hub_tooltip_history_title"),
                        description: viewModel.t("hub_tooltip_history_desc"),
                        icon: "clock.arrow.circlepath",
                        tintColor: Color.Premium.cashmereViolet,
                        onDismiss: { isHistoryInfoPresented = false }
                    )
                }
            }
        }
    }
    
    // MARK: - Model Selection Popover (Card 1)
    private var modelPickerPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.Premium.champagneBronze)
                    Text(viewModel.t("hub_model_picker_title"))
                        .font(.system(size: 13, weight: .bold))
                }
                
                Spacer()
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
        .frame(width: 470)
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
                            Text(viewModel.t("hub_active_model"))
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.Premium.emeraldMineral))
                        .fixedSize(horizontal: true, vertical: false)
                    } else {
                        Button(viewModel.t("hub_select")) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                viewModel.selectedModel = spec.model
                                isModelPickerPresented = false
                            }
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .tint(Color.Premium.slateAzure)
                        .controlSize(.small)
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    
                    Button(role: .destructive) {
                        viewModel.deleteModelInSettings(spec.model)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.Premium.crimsonVelvet.opacity(0.8))
                            .padding(4)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.t("hub_delete_model_help"))
                    .accessibilityLabel(viewModel.t("hub_delete_model_help"))
                }
            } else if viewModel.downloadingModel == spec.model {
                HStack(spacing: 6) {
                    VStack(alignment: .trailing, spacing: 3) {
                        ProgressView(value: viewModel.modelDownloadFraction)
                            .progressViewStyle(.linear)
                            .frame(width: 80)
                        Text(viewModel.modelDownloadStatusText.isEmpty ? viewModel.t("hub_processing") : viewModel.modelDownloadStatusText)
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
                    .help(viewModel.t("hub_cancel_download_help"))
                    .accessibilityLabel(viewModel.t("hub_cancel_download_help"))
                }
                .fixedSize(horizontal: true, vertical: false)
            } else {
                Button(action: {
                    viewModel.downloadModelInSettings(spec.model)
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 10))
                        Text(viewModel.t("settings_download"))
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
                    .foregroundStyle(Color.Premium.slateAzure)
                    .font(.system(size: 12))
                Text(viewModel.t("hub_speech_language_title"))
                    .font(.system(size: 12, weight: .bold))
                Spacer()
            }
            .padding(.bottom, 2)
            
            Divider()
            
            VStack(spacing: 4) {
                languageOptionRow(code: "auto", flag: "🌐", name: viewModel.t("hub_lang_auto"), desc: viewModel.t("hub_lang_auto_desc"))
                languageOptionRow(code: "tr", flag: "🇹🇷", name: viewModel.t("hub_lang_tr"), desc: viewModel.t("hub_lang_tr_desc"))
                languageOptionRow(code: "en", flag: "🇬🇧", name: viewModel.t("hub_lang_en"), desc: viewModel.t("hub_lang_en_desc"))
                languageOptionRow(code: "de", flag: "🇩🇪", name: viewModel.t("hub_lang_de"), desc: viewModel.t("hub_lang_de_desc"))
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
            return ("flame.fill", Color.Premium.cashmereViolet)
        case .largeV3TurboQ5:
            return ("bolt.badge.automatic.fill", Color.Premium.obsidianTeal)
        case .small:
            return ("sparkles", Color.Premium.emeraldMineral)
        case .base:
            return ("hare.fill", Color.Premium.champagneBronze)
        case .tiny:
            return ("leaf.fill", Color.Premium.emeraldMineral)
        case .medium:
            return ("books.vertical.fill", Color.Premium.slateAzure)
        }
    }
    
    // MARK: - Compact Feature Info Popover
    public struct StudioCompactInfoPopover: View {
        let title: String
        let description: String
        let icon: String
        let tintColor: Color
        var onDismiss: (() -> Void)? = nil
        
        public init(
            title: String,
            description: String,
            icon: String,
            tintColor: Color = .accentColor,
            onDismiss: (() -> Void)? = nil
        ) {
            self.title = title
            self.description = description
            self.icon = icon
            self.tintColor = tintColor
            self.onDismiss = onDismiss
        }
        
        public var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(tintColor.opacity(0.18))
                            .frame(width: 20, height: 20)
                        Image(systemName: icon)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(tintColor)
                    }
                    
                    Text(title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.primary)
                    
                    Spacer(minLength: 4)
                    
                    if let onDismiss = onDismiss {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.secondary.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Text(description)
                    .font(.system(size: 11))
                    .lineSpacing(2)
                    .foregroundStyle(Color.primary.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(width: 270)
        }
    }
    
    // MARK: - Interactive Card View Builder
    private struct StudioInteractiveCardView: View {
        let icon: String
        let badgeColor: Color
        let caption: String
        let title: String
        var showsChevron: Bool = false
        var isPulseActive: Bool = false
        @State private var isHovered: Bool = false
        
        var body: some View {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(badgeColor.opacity(isHovered ? 0.28 : 0.16))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(badgeColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(caption)
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(isHovered ? Color.primary.opacity(0.85) : Color.secondary)
                        .lineLimit(1)
                    
                    Text(title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 16)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .overlay(alignment: .bottomTrailing) {
                if isPulseActive {
                    Circle()
                        .fill(Color.Premium.emeraldMineral)
                        .frame(width: 6, height: 6)
                        .shadow(color: Color.Premium.emeraldMineral.opacity(0.6), radius: 3)
                        .padding(.trailing, 8)
                        .padding(.bottom, 7)
                } else if showsChevron {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(0.65))
                        .padding(.trailing, 8)
                        .padding(.bottom, 6)
                }
            }
            .liquidGlass(cornerRadius: 12, glowColor: badgeColor.opacity(isHovered ? 0.6 : 0.35), material: .ultraThinMaterial)
            .scaleEffect(isHovered ? 1.018 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
        }
    }
    
    // MARK: - 2. Central Queue Section (Kuyruk & "Transkripte Yolla" Action)
    private var centralQueueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Queue Header & Actions
            HStack(alignment: .center) {
                HStack(spacing: 8) {
                    Image(systemName: "tray.full.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    
                    Text(viewModel.t("hub_queue_items"))
                        .font(.system(size: 14, weight: .bold))
                    
                    Button(action: {
                        isQueueInfoPresented.toggle()
                    }) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(isQueueInfoPresented ? Color.accentColor : Color.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $isQueueInfoPresented, arrowEdge: .bottom) {
                        StudioCompactInfoPopover(
                            title: viewModel.t("action_transcribe_queue"),
                            description: viewModel.t("hub_tooltip_queue_btn_ready"),
                            icon: "sparkles",
                            tintColor: .accentColor,
                            onDismiss: { isQueueInfoPresented = false }
                        )
                    }
                    
                    if !viewModel.queueItems.isEmpty {
                        Text("\(viewModel.queueItems.count)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                    }
                    
                    if viewModel.failedCount > 0 {
                        Text(String(format: viewModel.t("hub_failed_count"), viewModel.failedCount))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.Premium.terracotta)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.Premium.terracotta.opacity(0.14)))
                    }
                    
                    // Sort Icon Button: Fixed-size 24x24 icon-only button (⇅ ONLY, no wide bar, no right chevron)
                    if !viewModel.queueItems.isEmpty {
                        Button(action: {
                            isSortPopoverPresented.toggle()
                        }) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(isSortPopoverPresented ? Color.accentColor : Color.secondary.opacity(0.85))
                                .frame(width: 24, height: 24)
                                .background(
                                    Circle()
                                        .fill(isSortPopoverPresented ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                                )
                                .overlay(
                                    Circle()
                                        .stroke(isSortPopoverPresented ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.12), lineWidth: 0.5)
                                )
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(viewModel.t("queue_sort_title"))
                        .popover(isPresented: $isSortPopoverPresented, arrowEdge: .bottom) {
                            sortPopoverView
                        }
                    }
                }
                
                Spacer()
                
                // Secondary Actions: Retry Failed
                if !viewModel.queueItems.isEmpty && viewModel.failedCount > 0 {
                    Button(action: { viewModel.retryFailedItems() }) {
                        Text(viewModel.t("hub_retry_failed"))
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
                            Text(viewModel.t("hub_processing"))
                                .font(.system(size: 12, weight: .bold))
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .bold))
                            Text(viewModel.t("action_transcribe_queue"))
                                .font(.system(size: 12, weight: .bold))
                        }
                    }
                    .foregroundColor(viewModel.canStartQueue ? .white : Color.secondary.opacity(0.45))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        viewModel.canStartQueue
                            ? AnyShapeStyle(LinearGradient(colors: [Color.Premium.sapphirePro, Color.Premium.sapphireProDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.primary.opacity(0.04))
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(viewModel.canStartQueue ? Color.Premium.sapphirePro.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 1)
                    )
                    .shadow(color: viewModel.canStartQueue ? Color.Premium.sapphirePro.opacity(0.35) : Color.clear, radius: 5, x: 0, y: 2)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canStartQueue)
                .hoverHelpTooltip(
                    title: viewModel.t("action_transcribe_queue"),
                    description: viewModel.canStartQueue ? viewModel.t("hub_tooltip_queue_btn_ready") : viewModel.t("hub_tooltip_queue_btn_disabled"),
                    icon: viewModel.canStartQueue ? "sparkles" : "pause.circle",
                    status: viewModel.canStartQueue ? "\(viewModel.queueItems.count)" : viewModel.t("hub_status_off"),
                    statusColor: viewModel.canStartQueue ? .accentColor : .secondary,
                    placement: .topTrailing
                )
                .studioTourTarget(.queueAndTranscribe)
                .id(StudioTourStep.queueAndTranscribe.id)
            }
            .padding(.horizontal, 4)
            
            // Live Processing Progress Card
            if viewModel.isProcessing {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(viewModel.currentOperation.isEmpty ? viewModel.t("status_transcribing") : viewModel.currentOperation)
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
                    Text(viewModel.t("hub_empty_queue"))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .liquidGlass(cornerRadius: 12, glowColor: isDropTargeted ? Color.accentColor : .white.opacity(0.3), material: .ultraThinMaterial)
            } else {
                VStack(spacing: 8) {
                    ForEach(viewModel.queueItems) { item in
                        StudioQueueItemRow(viewModel: viewModel, item: item)
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
                        .help(viewModel.t("action_clear_queue"))
                        .accessibilityLabel(viewModel.t("action_clear_queue"))
                        Spacer()
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
    
    // MARK: - Local Audio Selection Helper
    private func selectLocalAudioFiles() {
        viewModel.promptForLocalAudioFiles()
    }
    
    private var sortPopoverView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(viewModel.t("queue_sort_title"))
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 4)
            
            Divider()
                .padding(.horizontal, 6)
                .padding(.bottom, 2)
            
            sortOptionRow(
                title: viewModel.t("queue_sort_newest_first"),
                icon: "arrow.down",
                order: .newestFirst
            )
            
            sortOptionRow(
                title: viewModel.t("queue_sort_oldest_first"),
                icon: "arrow.up",
                order: .oldestFirst
            )
            
            sortOptionRow(
                title: viewModel.t("queue_sort_alphabetical"),
                icon: "textformat",
                order: .title
            )
        }
        .padding(4)
        .frame(width: 195)
    }
    
    private func sortOptionRow(title: String, icon: String, order: AppViewModel.QueueSortOrder) -> some View {
        Button(action: {
            viewModel.sortQueue(by: order)
            isSortPopoverPresented = false
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(viewModel.currentSortOrder == order ? Color.accentColor : Color.secondary)
                    .frame(width: 14)
                
                Text(title)
                    .font(.system(size: 12, weight: viewModel.currentSortOrder == order ? .semibold : .regular))
                    .foregroundStyle(viewModel.currentSortOrder == order ? Color.accentColor : Color.primary)
                
                Spacer()
                
                if viewModel.currentSortOrder == order {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(viewModel.currentSortOrder == order ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        _ = viewModel.handleUniversalDrop(providers: providers)
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
        case "auto": return viewModel.t("hub_lang_auto")
        case "tr": return viewModel.t("hub_lang_tr")
        case "en": return viewModel.t("hub_lang_en")
        case "de": return viewModel.t("hub_lang_de")
        default: return code.uppercased()
        }
    }
}

// MARK: - Studio Queue Item Row (High-End Dynamic Liquid Glass Visual Hierarchy)
struct StudioQueueItemRow: View {
    @ObservedObject var viewModel: AppViewModel
    let item: QueueItem
    @State private var isCopied: Bool = false
    @State private var isHovered: Bool = false
    
    var isCompleted: Bool {
        item.state == .completed
    }
    
    var body: some View {
        Button(action: {
            viewModel.selectedItemID = item.id
        }) {
            HStack(spacing: 12) {
                // Media Type Icon / Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(item.isYouTube ? Color.Premium.crimsonVelvet.opacity(0.14) : Color.Premium.cashmereViolet.opacity(0.14))
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
                                    .foregroundStyle(item.isYouTube ? Color.Premium.crimsonVelvet : Color.Premium.cashmereViolet)
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
                            .foregroundStyle(item.isYouTube ? Color.Premium.crimsonVelvet : Color.Premium.cashmereViolet)
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
                
                // Status Badge & Inline Actions
                HStack(spacing: 6) {
                    stateBadge(for: item.state)
                    
                    if isCompleted {
                        // Quick Copy Transcript Content Button
                        Button(action: {
                            copyTranscriptContent()
                        }) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(isCopied ? Color.Premium.emeraldMineral : Color.accentColor)
                                .padding(5)
                                .background(
                                    Circle()
                                        .fill(isCopied ? Color.Premium.emeraldMineral.opacity(0.20) : Color.accentColor.opacity(0.12))
                                )
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(viewModel.t("action_copy_transcript"))
                        .hoverHelpTooltip(
                            title: viewModel.t("action_copy_transcript"),
                            description: viewModel.t("hub_tooltip_copy_transcript_desc"),
                            icon: isCopied ? "checkmark" : "doc.on.doc",
                            statusColor: isCopied ? Color.Premium.emeraldMineral : .accentColor,
                            placement: .topTrailing,
                            width: 220
                        )
                        
                        // Show in Finder Button
                        Button(action: {
                            viewModel.openItemOutputInFinder(item)
                        }) {
                            Image(systemName: "folder")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(5)
                                .background(Circle().fill(Color.accentColor.opacity(0.12)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(viewModel.t("action_open_finder"))
                        .hoverHelpTooltip(
                            title: viewModel.t("hub_tooltip_finder_title"),
                            description: viewModel.t("hub_tooltip_finder_desc"),
                            icon: "folder",
                            statusColor: .accentColor,
                            placement: .topTrailing,
                            width: 220
                        )
                    }
                    
                    Button(action: {
                        viewModel.removeItem(id: item.id)
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary.opacity(0.7))
                            .padding(4)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.t("action_remove_item"))
                    .accessibilityLabel(viewModel.t("action_remove_item"))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(rowBackground)
            .overlay(rowBorder)
            .shadow(
                color: isCompleted ? Color.Premium.emeraldMineral.opacity(0.12) : Color.black.opacity(0.04),
                radius: isCompleted ? 8 : 6,
                x: 0,
                y: isCompleted ? 3 : 2
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    // MARK: - Row Background (Tamamlananlar: Saydam Yeşil | Diğerleri: Blurlu, Renksiz)
    @ViewBuilder
    private var rowBackground: some View {
        if isCompleted {
            // Tamamlananlar: Sağdan sola arka planın tamamı hafif, opak olmayan zümrüt yeşilliğe sahip
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
                
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.Premium.emeraldMineral.opacity(isHovered ? 0.22 : 0.16), location: 0.0),
                                .init(color: Color.Premium.emeraldMineral.opacity(isHovered ? 0.14 : 0.09), location: 0.5),
                                .init(color: Color.Premium.emeraldMineral.opacity(isHovered ? 0.20 : 0.15), location: 1.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
        } else {
            // Diğerleri / Yapılacak olanlar: Daha blurlu, renksiz, nötr buzlu cam
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
                .opacity(isHovered ? 0.95 : 0.85)
        }
    }
    
    // MARK: - Row Border
    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    stops: isCompleted ? [
                        .init(color: Color.Premium.emeraldMineral.opacity(isHovered ? 0.55 : 0.40), location: 0.0),
                        .init(color: Color.Premium.emeraldMineral.opacity(isHovered ? 0.30 : 0.20), location: 0.5),
                        .init(color: Color.Premium.emeraldMineral.opacity(isHovered ? 0.45 : 0.30), location: 1.0)
                    ] : [
                        .init(color: Color.white.opacity(isHovered ? 0.22 : 0.14), location: 0.0),
                        .init(color: Color.white.opacity(isHovered ? 0.08 : 0.04), location: 0.6),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: isCompleted ? 1.0 : 0.75
            )
            .allowsHitTesting(false)
    }
    
    private func copyTranscriptContent() {
        viewModel.copyTranscriptContent(for: item)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = false
            }
        }
    }
    
    private func stateBadge(for state: QueueItemState) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(badgeColor(for: state))
                .frame(width: 6, height: 6)
            Text(localizedState(for: state))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(badgeColor(for: state))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(badgeColor(for: state).opacity(0.14)))
    }
    
    private func localizedState(for state: QueueItemState) -> String {
        switch state {
        case .queued: return viewModel.t("status_queued")
        case .fetching: return viewModel.t("status_fetching")
        case .transcribing: return viewModel.t("status_transcribing")
        case .completed: return viewModel.t("status_completed")
        case .failed: return viewModel.t("status_failed")
        }
    }
    
    private func badgeColor(for state: QueueItemState) -> Color {
        switch state {
        case .queued: return .secondary
        case .fetching: return Color.Premium.slateAzure
        case .transcribing: return Color.Premium.cashmereViolet
        case .completed: return Color.Premium.emeraldMineral
        case .failed: return Color.Premium.terracotta
        }
    }
}

private struct HubScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct PullRefreshIndicatorView: View {
    let effectiveOffset: CGFloat
    let isRefreshing: Bool
    let onTap: () -> Void
    
    @State private var isSpinning: Bool = false
    
    var body: some View {
        let isVisible = isRefreshing || effectiveOffset > 5
        let currentHeight: CGFloat = isRefreshing ? 38 : min(46, effectiveOffset)
        let progress = min(1.0, max(0.0, effectiveOffset / 48.0))
        let pullRotation = Double(effectiveOffset) * 3.6
        
        VStack(spacing: 0) {
            if isVisible {
                Button(action: onTap) {
                    ZStack {
                        Circle()
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .stroke(
                                        isRefreshing || progress >= 1.0
                                            ? Color.accentColor.opacity(0.5)
                                            : Color.primary.opacity(0.12),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                        
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isRefreshing || progress >= 1.0 ? Color.accentColor : Color.secondary)
                            .rotationEffect(.degrees(isRefreshing ? (isSpinning ? 360 : 0) : pullRotation))
                            .animation(
                                isRefreshing ? .linear(duration: 0.75).repeatForever(autoreverses: false) : .default,
                                value: isSpinning
                            )
                    }
                }
                .buttonStyle(.plain)
                .scaleEffect(isRefreshing ? 1.0 : min(1.0, max(0.4, progress)))
                .opacity(isRefreshing ? 1.0 : min(1.0, Double(effectiveOffset) / 20.0))
                .padding(.top, isRefreshing ? 8 : 4)
                .padding(.bottom, 4)
                .frame(height: currentHeight)
                .transition(.opacity.combined(with: .scale))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isVisible ? currentHeight : 0)
        .clipped()
        .onAppear {
            if isRefreshing { isSpinning = true }
        }
        .onChange(of: isRefreshing) { _, newValue in
            isSpinning = newValue
        }
    }
}
