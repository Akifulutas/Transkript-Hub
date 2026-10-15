import SwiftUI
import AppKit
import TranskriptHubCore

public struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    
    public init(viewModel: AppViewModel = AppViewModel()) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ZStack {
            NavigationSplitView {
                // Column 1: Content List (Queue, History, Folder, Settings)
                Group {
                    switch viewModel.selectedSection {
                    case .queue:
                        QueueListView(viewModel: viewModel)
                    case .history:
                        HistoryListView(viewModel: viewModel)
                    case .watchedFolder:
                        WatchedFolderView(viewModel: viewModel)
                    case .settings:
                        SettingsView(viewModel: viewModel)
                    }
                }
                .frame(minWidth: 320, idealWidth: 360, maxWidth: 460)
            } detail: {
                // Column 2: Interactive Studio Canvas & Inspector Pane
                TranscriptDetailView(viewModel: viewModel)
            }
            .navigationSplitViewStyle(.prominentDetail)
            .frame(minWidth: 900, minHeight: 600)
            .toolbar {
                mainToolbar
            }
            .searchable(text: $viewModel.searchQuery, prompt: "Transkriptlerde veya kuyrukta ara...")
            .sheet(item: $viewModel.pendingBatchIngestion) { pending in
                PlaylistIngestionSheet(viewModel: viewModel, pending: pending)
            }
            .sheet(isPresented: $viewModel.isSaveModePromptPresented) {
                SessionSaveModeSheet(
                    viewModel: viewModel,
                    itemCount: viewModel.queueItems.filter { $0.state == .queued || $0.state == .failed }.count,
                    onConfirm: { mode in
                        viewModel.isSaveModePromptPresented = false
                        viewModel.startProcessingQueue(saveMode: mode)
                    },
                    onCancel: {
                        viewModel.isSaveModePromptPresented = false
                    }
                )
            }
            
            // Floating 5-Second Undo Toast (Confirmation State in 8-State Matrix)
            if viewModel.showUndoToast {
                VStack {
                    Spacer()
                    LiquidUndoToast(
                        message: viewModel.undoToastMessage,
                        undoAction: { viewModel.performUndo() },
                        dismissAction: { viewModel.dismissUndoToast() }
                    )
                }
            }
            
            // Floating ⌘K Command Palette Overlay
            if viewModel.isCommandPalettePresented {
                CommandPaletteView(
                    isPresented: $viewModel.isCommandPalettePresented,
                    searchText: $viewModel.commandPaletteSearch,
                    onPasteClipboard: { viewModel.addFromClipboard() },
                    onSelectAudioFile: {
                        let panel = NSOpenPanel()
                        panel.allowsMultipleSelection = true
                        panel.canChooseDirectories = false
                        panel.allowedContentTypes = [.audio, .movie]
                        if panel.runModal() == .OK {
                            viewModel.addAudioFiles(panel.urls)
                        }
                    },
                    onStartQueue: { viewModel.startProcessingQueue() },
                    onClearQueue: { viewModel.clearQueueWithUndo() },
                    onCopyCurrentTranscript: { viewModel.copySelectedTranscript() },
                    onToggleFolderWatch: { viewModel.isFolderWatching.toggle() }
                )
            }
        }
        // Real macOS Liquid Glass Translucency & Specular Ambiance
        .background(
            WindowAccessor { window in
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarAppearsTransparent = true
            }
        )
        .background(
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .overlay(
            LinearGradient(
                stops: [
                    .init(color: Color.blue.opacity(0.06), location: 0.0),
                    .init(color: Color.purple.opacity(0.04), location: 0.35),
                    .init(color: .clear, location: 0.75)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
        // Global Keyboard Ergonomics
        .background(
            KeyboardShortcutsView(
                onCommandK: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        viewModel.isCommandPalettePresented.toggle()
                    }
                },
                onCommandV: {
                    viewModel.addFromClipboard()
                },
                onCommandShiftC: {
                    viewModel.copySelectedTranscript()
                },
                onCommandA: {
                    viewModel.selectAllQueueItems()
                }
            )
        )
    }
    
    // MARK: - Native macOS Unified Toolbar (Liquid Glass Capsules)
    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Picker("", selection: $viewModel.selectedSection) {
                Label(viewModel.queueItems.isEmpty ? "Kuyruk" : "Kuyruk (\(viewModel.queueItems.count))", systemImage: "tray.full.fill")
                    .tag(SidebarSection.queue)
                Label(viewModel.historyItems.isEmpty ? "Geçmiş" : "Geçmiş (\(viewModel.historyItems.count))", systemImage: "clock.arrow.circlepath")
                    .tag(SidebarSection.history)
                Label("İzlenen Klasör", systemImage: "folder.badge.gearshape")
                    .tag(SidebarSection.watchedFolder)
                Label("Ayarlar", systemImage: "gearshape")
                    .tag(SidebarSection.settings)
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)
            .frame(maxWidth: 430)
        }
        
        ToolbarItem(placement: .automatic) {
            // Model Selector Dropdown (Only downloaded models shown)
            Menu {
                if viewModel.downloadedModels.isEmpty {
                    Text("İndirilmiş Model Yok")
                } else {
                    ForEach(viewModel.downloadedModels, id: \.self) { model in
                        Button {
                            viewModel.selectedModel = model
                        } label: {
                            HStack {
                                Label(modelDisplayName(model), systemImage: modelSystemIcon(model))
                                if viewModel.selectedModel == model { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
                
                Divider()
                
                Button {
                    viewModel.selectedSection = .settings
                } label: {
                    Label("Model İndir / Yönet... (Ayarlar)", systemImage: "gearshape")
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "cpu")
                        .foregroundColor(.secondary)
                    Text(viewModel.selectedModelTitle)
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .liquidGlassCapsule(glowColor: .white.opacity(0.4), material: .ultraThinMaterial)
            }
            .buttonStyle(.plain)
            .help("İndirilen Whisper Yapay Zeka Modelini Seçin")
        }
        
        ToolbarItem(placement: .automatic) {
            // Language Selector Dropdown (Instant single-click, no submenu)
            Menu {
                languageMenuButton(code: "auto", title: "🌐 Otomatik Algıla")
                Divider()
                languageMenuButton(code: "tr", title: "🇹🇷 Türkçe")
                languageMenuButton(code: "en", title: "🇬🇧 İngilizce")
                languageMenuButton(code: "de", title: "🇩🇪 Almanca")
                languageMenuButton(code: "fr", title: "🇫🇷 Fransızca")
                languageMenuButton(code: "es", title: "🇪🇸 İspanyolca")
                languageMenuButton(code: "ru", title: "🇷🇺 Rusça")
                languageMenuButton(code: "ar", title: "🇸🇦 Arapça")
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "globe")
                        .foregroundColor(.secondary)
                    Text(languageTitle(viewModel.selectedLanguage))
                        .font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .liquidGlassCapsule(glowColor: .white.opacity(0.4), material: .ultraThinMaterial)
            }
            .buttonStyle(.plain)
            .help("Transkript Edilecek Konuşma Dili")
        }
        
        ToolbarItem(placement: .automatic) {
            // Distinct Interactive Clipboard Monitor Toggle
            Button(action: {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                    viewModel.isClipboardMonitoring.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.isClipboardMonitoring ? "doc.on.clipboard.fill" : "doc.on.clipboard")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(viewModel.isClipboardMonitoring ? .accentColor : .secondary)
                    
                    Text(viewModel.isClipboardMonitoring ? "Pano İzleniyor" : "Pano İzle: Kapalı")
                        .font(.system(size: 11, weight: viewModel.isClipboardMonitoring ? .semibold : .medium))
                        .foregroundColor(viewModel.isClipboardMonitoring ? .primary : .secondary)
                    
                    Circle()
                        .fill(viewModel.isClipboardMonitoring ? Color.green : Color.gray.opacity(0.4))
                        .frame(width: 6, height: 6)
                        .shadow(color: viewModel.isClipboardMonitoring ? Color.green.opacity(0.7) : Color.clear, radius: 3)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(viewModel.isClipboardMonitoring ? Color.accentColor.opacity(0.14) : Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(viewModel.isClipboardMonitoring ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("Panoya kopyalanan YouTube video bağlantılarını otomatik yakalama")
        }
        
        ToolbarItem(placement: .automatic) {
            // ⌘K Quick Button in Toolbar
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    viewModel.isCommandPalettePresented.toggle()
                }
            }) {
                Image(systemName: "command")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .liquidGlassCapsule(glowColor: .white.opacity(0.3), material: .ultraThinMaterial)
            }
            .buttonStyle(.plain)
            .help("Hızlı Komut Paleti (⌘K)")
        }
        
        ToolbarItem(placement: .primaryAction) {
            // Primary Action Button (⌘Return)
            Button(action: { viewModel.requestStartQueue() }) {
                HStack(spacing: 6) {
                    if viewModel.isProcessing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                            .font(.system(size: 10))
                    }
                    Text(viewModel.isProcessing ? "İşleniyor..." : "Transkripte Yolla")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.queueItems.isEmpty || viewModel.isProcessing)
            .keyboardShortcut(.defaultAction)
            .help("Kuyruktaki tüm videoları ve sesleri transkript etmeye başlar (⌘Return)")
        }
    }
    
    private func modelDisplayName(_ model: WhisperModel) -> String {
        switch model {
        case .tiny: return "Tiny (75 MB - Hızlı)"
        case .base: return "Base (142 MB - Standart)"
        case .small: return "Small (466 MB - Dengeli)"
        case .medium: return "Medium (1.5 GB)"
        case .largeV3Turbo: return "Large-v3-Turbo (1.6 GB - En İyi)"
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
        case "fr": return "Fransızca"
        case "es": return "İspanyolca"
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

// MARK: - Global Invisible Keyboard Event Listener
private struct KeyboardShortcutsView: NSViewRepresentable {
    let onCommandK: () -> Void
    let onCommandV: () -> Void
    let onCommandShiftC: () -> Void
    let onCommandA: () -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyInterceptingView()
        view.onCommandK = onCommandK
        view.onCommandV = onCommandV
        view.onCommandShiftC = onCommandShiftC
        view.onCommandA = onCommandA
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class KeyInterceptingView: NSView {
    var onCommandK: (() -> Void)?
    var onCommandV: (() -> Void)?
    var onCommandShiftC: (() -> Void)?
    var onCommandA: (() -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        
        if flags == .command && chars == "k" {
            onCommandK?()
            return true
        }
        if flags == [.command, .shift] && chars == "c" {
            onCommandShiftC?()
            return true
        }
        if flags == .command && chars == "a" {
            // If user is focused on a text view / text editor, let the text view select its text
            if let responder = window?.firstResponder, responder is NSTextView {
                return super.performKeyEquivalent(with: event)
            }
            onCommandA?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
