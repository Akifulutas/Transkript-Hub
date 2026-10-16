import SwiftUI
import AppKit
import TranskriptHubCore

public struct FloatingSettingsSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var selectedTab: SettingsTab = .general
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        HStack(spacing: 0) {
            // Left Navigation Sidebar
            sidebarPane
                .frame(width: 220)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.85))
            
            Divider()
            
            // Right Content Pane
            VStack(spacing: 0) {
                // Modal Top Bar with Close (X) button
                topBar
                
                Divider()
                
                // Tab Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .general:
                            generalTab
                        case .models:
                            modelsTab
                        case .storage:
                            storageTab
                        case .automation:
                            automationTab
                        case .updates:
                            updatesTab
                        }
                    }
                    .padding(24)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
        }
        .frame(width: 780, height: 560)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
        .onAppear {
            selectedTab = viewModel.selectedSettingsTab
        }
    }
    
    // MARK: - Left Sidebar Pane
    private var sidebarPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                Text(viewModel.t("section_settings"))
                    .font(.system(size: 15, weight: .bold))
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)
            
            // Tab Items
            VStack(spacing: 2) {
                tabButton(.general, title: viewModel.t("tab_general"), icon: "gearshape")
                tabButton(.models, title: viewModel.t("tab_models"), icon: "cpu")
                tabButton(.storage, title: viewModel.t("tab_storage"), icon: "folder")
                tabButton(.automation, title: viewModel.t("tab_automation"), icon: "waveform.badge.magnifyingglass")
                tabButton(.updates, title: viewModel.t("tab_updates"), icon: "arrow.triangle.2.circlepath")
            }
            .padding(.horizontal, 10)
            
            Spacer()
            
            // App Footer
            VStack(alignment: .leading, spacing: 3) {
                Text("Transkript Hub")
                    .font(.system(size: 12, weight: .semibold))
                Text("v\(UpdateChecker.currentVersion)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(16)
        }
    }
    
    private func tabButton(_ tab: SettingsTab, title: String, icon: String) -> some View {
        let isSelected = selectedTab == tab
        return Button(action: {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selectedTab = tab
                viewModel.selectedSettingsTab = tab
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 18)
                
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
    
    // MARK: - Top Bar with Close Button
    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(tabTitle(selectedTab))
                    .font(.system(size: 16, weight: .bold))
                Text(tabSubtitle(selectedTab))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Modern Circular Close Button (X)
            Button(action: {
                viewModel.isSettingsPresented = false
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.secondary.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
    
    // MARK: - 1. General Tab
    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Language Selection
            cardSection(title: viewModel.t("settings_language"), icon: "globe") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.t("settings_language_desc"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $viewModel.appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            
            // Clipboard Automation
            cardSection(title: viewModel.t("settings_clipboard_auto"), icon: "doc.on.clipboard") {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(viewModel.t("settings_clipboard_auto_toggle"), isOn: $viewModel.isClipboardMonitoring)
                        .toggleStyle(.switch)
                    
                    Text(viewModel.t("settings_clipboard_auto_desc"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            // Spoken Audio Default Language
            cardSection(title: viewModel.t("settings_default_speech_lang"), icon: "waveform") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.t("settings_default_speech_lang_desc"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Picker(viewModel.t("hub_speech_language_title") + ":", selection: $viewModel.selectedLanguage) {
                        Text("🌐 \(viewModel.t("hub_lang_auto"))").tag("auto")
                        Text("🇹🇷 \(viewModel.t("hub_lang_tr"))").tag("tr")
                        Text("🇬🇧 \(viewModel.t("hub_lang_en"))").tag("en")
                        Text("🇩🇪 \(viewModel.t("hub_lang_de"))").tag("de")
                    }
                    .frame(maxWidth: 240)
                }
            }
        }
    }
    
    // MARK: - 2. Models Tab & Online Catalog Search
    private var modelsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Search and Online Check Bar
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                    
                    TextField(viewModel.t("settings_search_models_placeholder"), text: $viewModel.modelSearchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    
                    if !viewModel.modelSearchQuery.isEmpty {
                        Button(action: { viewModel.modelSearchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Divider().frame(height: 16)
                    
                    Button(action: { viewModel.checkOnlineModels() }) {
                        HStack(spacing: 4) {
                            if viewModel.isCheckingOnlineModels {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text(viewModel.t("settings_scan_new_models"))
                        }
                        .font(.system(size: 11, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isCheckingOnlineModels)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .liquidGlassCapsule(glowColor: .white.opacity(0.6), material: .ultraThinMaterial)
                
                if !viewModel.onlineModelStatusText.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                        Text(viewModel.onlineModelStatusText)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                }
            }
            
            // Filtered Models List
            let specs = WhisperModelCatalog.search(query: viewModel.modelSearchQuery)
            VStack(spacing: 12) {
                ForEach(specs) { spec in
                    catalogModelRow(spec: spec)
                    if spec != specs.last {
                        Divider()
                    }
                }
            }
            .padding(16)
            .liquidGlass(cornerRadius: 14, glowColor: .white.opacity(0.5), material: .ultraThinMaterial)
        }
    }
    
    private func catalogModelRow(spec: WhisperModelSpec) -> some View {
        let isDownloaded = viewModel.modelManager.isModelDownloaded(spec.model)
        let isActive = viewModel.selectedModel == spec.model
        
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(spec.displayName)
                            .font(.system(size: 13, weight: .bold))
                        
                        Text(spec.sizeDescription)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        
                        if let b = spec.badge {
                            Text(b)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.purple)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.purple.opacity(0.12)))
                                .lineLimit(1)
                        }
                        
                        if isActive {
                            Text(viewModel.t("settings_active"))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .liquidGlassCapsule(glowColor: .green, material: .ultraThinMaterial)
                        }
                    }
                    
                    Text(spec.summary)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Action Buttons
                if isDownloaded {
                    HStack(spacing: 8) {
                        if !isActive {
                            Button(viewModel.t("hub_select")) {
                                viewModel.selectedModel = spec.model
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        
                        Button(role: .destructive) {
                            viewModel.deleteModelInSettings(spec.model)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.red.opacity(0.8))
                                .padding(5)
                                .background(Color.red.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help(viewModel.t("hub_delete_model_help"))
                    }
                } else if viewModel.downloadingModel == spec.model {
                    HStack(spacing: 8) {
                        VStack(alignment: .trailing, spacing: 4) {
                            ProgressView(value: viewModel.modelDownloadFraction)
                                .progressViewStyle(.linear)
                                .frame(width: 120)
                            Text(viewModel.modelDownloadStatusText.isEmpty ? viewModel.t("hub_processing") : viewModel.modelDownloadStatusText)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Button(action: {
                            viewModel.cancelModelDownload()
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(viewModel.t("hub_cancel_download_help"))
                    }
                } else {
                    Button(viewModel.t("settings_download")) {
                        viewModel.downloadModelInSettings(spec.model)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    // MARK: - 3. Storage Tab
    private var storageTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            cardSection(title: viewModel.t("watched_output_title"), icon: "folder") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.t("watched_output_desc"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(viewModel.outputDirectoryURL.lastPathComponent)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(viewModel.isCustomOutputDirectory ? viewModel.t("watched_output_custom_badge") : viewModel.t("watched_output_default_badge"))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(viewModel.isCustomOutputDirectory ? .teal : .secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill((viewModel.isCustomOutputDirectory ? Color.teal : Color.secondary).opacity(0.12)))
                            }
                            Text(viewModel.outputDirectoryURL.path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        Spacer()
                        
                        Button(viewModel.isCustomOutputDirectory ? viewModel.t("watched_change_folder") : viewModel.t("watched_choose_folder")) {
                            viewModel.selectOutputDirectory()
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        
                        if viewModel.isCustomOutputDirectory {
                            Button(viewModel.t("watched_reset_folder")) {
                                viewModel.resetOutputDirectory()
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.plain)
                            .foregroundColor(.red.opacity(0.8))
                        }
                        
                        Button(viewModel.t("action_open_finder")) {
                            viewModel.openInFinder(path: viewModel.outputDirectoryURL.path)
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                }
            }
            
            cardSection(title: viewModel.t("settings_batch_format_title"), icon: "doc.on.doc") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.t("settings_save_format_question"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $viewModel.sessionSaveMode) {
                        Text(viewModel.t("settings_save_both_opt")).tag(SessionSaveMode.both)
                        Text(viewModel.t("settings_save_individual_opt")).tag(SessionSaveMode.individual)
                        Text(viewModel.t("settings_save_combined_opt")).tag(SessionSaveMode.combined)
                    }
                    .pickerStyle(.radioGroup)
                }
            }
        }
    }
    
    // MARK: - 4. Automation & Voice Memos Tab
    private var automationTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Folder Watching Toggle & Configurable Sources
            cardSection(title: viewModel.t("watched_title"), icon: "waveform.badge.magnifyingglass") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.isFolderWatching ? viewModel.t("watched_active") : viewModel.t("watched_inactive"))
                                .font(.system(size: 13, weight: .semibold))
                            Text(viewModel.t("watched_subtitle"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $viewModel.isFolderWatching)
                            .toggleStyle(.switch)
                    }
                    
                    Divider()
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.t("watched_auto_transcribe_title"))
                                .font(.system(size: 12, weight: .semibold))
                            Text(viewModel.t("watched_auto_transcribe_desc"))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: $viewModel.folderWatcher.autoTranscribe)
                            .toggleStyle(.switch)
                    }
                    
                    Divider()
                    
                    // Source 1: iCloud Drive
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(viewModel.t("watched_icloud_title"), systemImage: "icloud.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.blue)
                            Spacer()
                            Toggle("", isOn: $viewModel.folderWatcher.watchiCloudDrive)
                                .toggleStyle(.switch)
                        }
                        if viewModel.folderWatcher.watchiCloudDrive {
                            Toggle(viewModel.t("watched_icloud_root_opt"), isOn: $viewModel.folderWatcher.watchiCloudRoot)
                                .toggleStyle(.checkbox)
                                .font(.system(size: 11))
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                    
                    // Source 2: Apple Voice Memos
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(viewModel.t("watched_voicememos_title"), systemImage: "waveform")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.orange)
                            Spacer()
                            Toggle("", isOn: $viewModel.folderWatcher.watchVoiceMemos)
                                .toggleStyle(.switch)
                        }
                        if viewModel.folderWatcher.watchVoiceMemos {
                            HStack {
                                Text(viewModel.folderWatcher.isVoiceMemosDirectlyAccessible ? viewModel.t("watched_status_accessible") : viewModel.t("watched_status_fda_needed"))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(viewModel.folderWatcher.isVoiceMemosDirectlyAccessible ? .green : .orange)
                                Spacer()
                                if !viewModel.folderWatcher.isVoiceMemosDirectlyAccessible {
                                    Button(viewModel.t("watched_open_settings")) {
                                        viewModel.openFullDiskAccessSettings()
                                    }
                                    .font(.system(size: 10))
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.mini)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                    
                    // Source 3: Custom Folder
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(viewModel.t("watched_custom_title"), systemImage: "folder.badge.plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.purple)
                            Spacer()
                            Toggle("", isOn: $viewModel.folderWatcher.watchCustomFolder)
                                .toggleStyle(.switch)
                        }
                        HStack {
                            if let customURL = viewModel.folderWatcher.customFolderURL {
                                Text(customURL.path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .lineLimit(1)
                                Spacer()
                                Button(viewModel.t("watched_change_folder")) {
                                    viewModel.selectCustomWatchedFolder()
                                }
                                .font(.system(size: 10))
                                .buttonStyle(.bordered)
                                .controlSize(.mini)
                                
                                Button(viewModel.t("watched_reset_folder")) {
                                    viewModel.resetCustomWatchedFolder()
                                }
                                .font(.system(size: 10))
                                .buttonStyle(.plain)
                                .foregroundColor(.red.opacity(0.8))
                            } else {
                                Text(viewModel.t("watched_no_custom_selected"))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(viewModel.t("watched_choose_folder")) {
                                    viewModel.selectCustomWatchedFolder()
                                }
                                .font(.system(size: 10, weight: .semibold))
                                .buttonStyle(.borderedProminent)
                                .controlSize(.mini)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                    
                    HStack {
                        Button(viewModel.t("watched_scan_now")) {
                            viewModel.triggerFolderScan()
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button(viewModel.t("watched_scan_cloud")) {
                            viewModel.triggerCloudScan()
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Spacer()
                    }
                }
            }
            
            // WhatsApp & Cloud Integration Guide
            cardSection(title: viewModel.t("settings_whatsapp_title"), icon: "message.fill") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.t("settings_whatsapp_step_intro"))
                        .font(.system(size: 12, weight: .medium))
                    
                    Text(viewModel.t("settings_whatsapp_step_1"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(viewModel.t("settings_whatsapp_step_2"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(viewModel.t("settings_whatsapp_step_3"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text(viewModel.t("settings_whatsapp_step_4"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            
            // Full Disk Access (FDA) Permission Card
            cardSection(title: viewModel.t("settings_fda_title"), icon: "lock.shield") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(viewModel.fullDiskAccessStatus.isGranted ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                            Text(viewModel.fullDiskAccessStatus.isGranted ? viewModel.t("settings_fda_granted") : viewModel.t("settings_fda_pending"))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(viewModel.fullDiskAccessStatus.isGranted ? .green : .orange)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(viewModel.fullDiskAccessStatus.isGranted ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                        .cornerRadius(6)
                        
                        Spacer()
                        
                        Button(viewModel.t("settings_fda_recheck")) {
                            viewModel.checkFullDiskAccess()
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button(viewModel.t("watched_open_settings")) {
                            viewModel.openFullDiskAccessSettings()
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    
                    Text(viewModel.t("settings_fda_voice_memos_desc"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    if !viewModel.fullDiskAccessStatus.isGranted {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.t("settings_fda_how_to"))
                                .font(.system(size: 11, weight: .bold))
                            Text(viewModel.t("settings_fda_how_to_steps"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
            }
            
            // Apple Watch & iPhone Voice Memos Guide
            cardSection(title: viewModel.t("tab_automation"), icon: "applewatch") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(viewModel.t("settings_voice_memos_options_title"))
                        .font(.system(size: 12, weight: .medium))
                    
                    Text(viewModel.t("settings_voice_memos_method_a"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text(viewModel.t("settings_voice_memos_method_b"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text(viewModel.t("settings_voice_memos_method_c"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - 5. Updates Tab
    private var updatesTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            cardSection(title: viewModel.t("settings_updates_title"), icon: "arrow.triangle.2.circlepath") {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Transkript Hub")
                                .font(.system(size: 15, weight: .bold))
                            Text(String(format: viewModel.t("settings_current_version"), UpdateChecker.currentVersion))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: { viewModel.checkForUpdates() }) {
                            HStack(spacing: 5) {
                                if viewModel.isCheckingUpdates {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text(viewModel.t("settings_updates_check_now"))
                            }
                            .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(viewModel.isCheckingUpdates)
                    }
                    
                    Divider()
                    
                    // Update check status result box
                    if !viewModel.updateCheckStatusText.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: viewModel.updateInfo?.isNewerThanCurrent == true ? "sparkles" : "checkmark.seal.fill")
                                .font(.system(size: 16))
                                .foregroundColor(viewModel.updateInfo?.isNewerThanCurrent == true ? .purple : .green)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewModel.updateCheckStatusText)
                                    .font(.system(size: 12, weight: .semibold))
                                if let info = viewModel.updateInfo, info.isNewerThanCurrent {
                                    Text(info.releaseNotes)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }
                            }
                            
                            Spacer()
                            
                            if let info = viewModel.updateInfo, info.isNewerThanCurrent {
                                Button(viewModel.t("settings_download_github")) {
                                    viewModel.openInBrowser(url: info.htmlURL)
                                }
                                .font(.system(size: 11, weight: .bold))
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(12)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(10)
                    }
                    
                    Toggle(viewModel.t("settings_auto_check_updates"), isOn: $viewModel.autoCheckUpdates)
                        .toggleStyle(.switch)
                }
            }
            
            cardSection(title: viewModel.t("settings_opensource_repo"), icon: "link") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.t("settings_github_repo"))
                            .font(.system(size: 12, weight: .semibold))
                        Text("https://github.com/Akifulutas/Transkript-Hub")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(viewModel.t("settings_open_repo")) {
                        viewModel.openInBrowser(url: "https://github.com/Akifulutas/Transkript-Hub")
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
    
    // MARK: - Helper Views & Functions
    private func cardSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .font(.system(size: 12))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
            }
            
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(cornerRadius: 12, glowColor: .white.opacity(0.5), material: .ultraThinMaterial)
        }
    }
    
    private func tabTitle(_ tab: SettingsTab) -> String {
        switch tab {
        case .general: return viewModel.t("settings_general_title")
        case .models: return viewModel.t("settings_models_title")
        case .storage: return viewModel.t("settings_storage_title")
        case .automation: return viewModel.t("settings_automation_title")
        case .updates: return viewModel.t("settings_updates_title")
        }
    }
    
    private func tabSubtitle(_ tab: SettingsTab) -> String {
        switch tab {
        case .general: return viewModel.t("settings_general_subtitle")
        case .models: return viewModel.t("settings_models_subtitle")
        case .storage: return viewModel.t("settings_storage_subtitle")
        case .automation: return viewModel.t("settings_automation_subtitle")
        case .updates: return viewModel.t("settings_updates_subtitle")
        }
    }
}
