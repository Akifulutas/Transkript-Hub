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
            Group {
                if viewModel.selectedItem != nil || viewModel.selectedHistoryItem != nil {
                    TranscriptDetailView(viewModel: viewModel)
                } else {
                    switch viewModel.selectedSection {
                    case .queue:
                        UnifiedStudioHubView(viewModel: viewModel)
                    case .history:
                        VStack(spacing: 0) {
                            navigationBackBar(title: "Geçmiş & Arşiv")
                            HistoryListView(viewModel: viewModel)
                        }
                    case .watchedFolder:
                        VStack(spacing: 0) {
                            navigationBackBar(title: "İzlenen Klasör")
                            WatchedFolderView(viewModel: viewModel)
                        }
                    case .settings:
                        VStack(spacing: 0) {
                            navigationBackBar(title: "Ayarlar")
                            SettingsView(viewModel: viewModel)
                        }
                    }
                }
            }
            .frame(minWidth: 900, minHeight: 600)
            .toolbar {
                mainToolbar
            }
            .sheet(item: $viewModel.pendingBatchIngestion) { pending in
                PlaylistIngestionSheet(viewModel: viewModel, pending: pending)
            }
            .sheet(isPresented: $viewModel.isSaveModePromptPresented) {
                SessionSaveModeSheet(
                    viewModel: viewModel,
                    itemCount: max(viewModel.queueItems.count, viewModel.queueItems.filter { $0.state == .queued || $0.state == .failed }.count),
                    onConfirm: { mode in
                        viewModel.isSaveModePromptPresented = false
                        viewModel.startProcessingQueue(saveMode: mode)
                    },
                    onCancel: {
                        viewModel.isSaveModePromptPresented = false
                    }
                )
            }
            .sheet(isPresented: $viewModel.isSettingsPresented) {
                FloatingSettingsSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.isRecordingModalPresented) {
                LiveAudioMeterView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.isRecordingSourceSheetPresented) {
                AudioRecordingSourceSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.isWatchedFolderPresented) {
                WatchedFolderSheet(viewModel: viewModel)
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
                    onStartQueue: { viewModel.requestStartQueue() },
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
                window.titleVisibility = .hidden
                window.title = ""
            }
        )
        .navigationTitle("")
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
                },
                onSpace: {
                    viewModel.audioPlayer.togglePlayPause()
                },
                onCommandLeft: {
                    viewModel.audioPlayer.skipBackward(by: 5.0)
                },
                onCommandRight: {
                    viewModel.audioPlayer.skipForward(by: 5.0)
                },
                onCommandR: {
                    viewModel.isRecordingSourceSheetPresented = true
                }
            )
        )
    }
    
    // MARK: - Native macOS Unified Toolbar (Clean & Minimal)
    @ToolbarContentBuilder
    private var mainToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 24, height: 24)
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
                Text("Transkript Hub")
                    .font(.system(size: 14, weight: .bold))
            }
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
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .liquidGlassCapsule(glowColor: .white.opacity(0.3), material: .ultraThinMaterial)
            }
            .buttonStyle(.plain)
            .help("Hızlı Komut Paleti (⌘K)")
        }
        
        ToolbarItem(placement: .automatic) {
            // Settings Floating Modal Button
            Button(action: {
                viewModel.openSettings()
            }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .liquidGlassCapsule(glowColor: .white.opacity(0.3), material: .ultraThinMaterial)
            }
            .buttonStyle(.plain)
            .help("Ayarlar (⌘,)")
        }
    }
    
    private func navigationBackBar(title: String) -> some View {
        HStack {
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    viewModel.selectedSection = .queue
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("Ana Merkeze Dön")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .liquidGlassCapsule(glowColor: .accentColor.opacity(0.4), material: .ultraThinMaterial)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            Text(title)
                .font(.system(size: 14, weight: .bold))
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.4))
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
    let onSpace: () -> Void
    let onCommandLeft: () -> Void
    let onCommandRight: () -> Void
    let onCommandR: () -> Void
    
    init(
        onCommandK: @escaping () -> Void,
        onCommandV: @escaping () -> Void,
        onCommandShiftC: @escaping () -> Void,
        onCommandA: @escaping () -> Void,
        onSpace: @escaping () -> Void = {},
        onCommandLeft: @escaping () -> Void = {},
        onCommandRight: @escaping () -> Void = {},
        onCommandR: @escaping () -> Void = {}
    ) {
        self.onCommandK = onCommandK
        self.onCommandV = onCommandV
        self.onCommandShiftC = onCommandShiftC
        self.onCommandA = onCommandA
        self.onSpace = onSpace
        self.onCommandLeft = onCommandLeft
        self.onCommandRight = onCommandRight
        self.onCommandR = onCommandR
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyInterceptingView()
        view.onCommandK = onCommandK
        view.onCommandV = onCommandV
        view.onCommandShiftC = onCommandShiftC
        view.onCommandA = onCommandA
        view.onSpace = onSpace
        view.onCommandLeft = onCommandLeft
        view.onCommandRight = onCommandRight
        view.onCommandR = onCommandR
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class KeyInterceptingView: NSView {
    var onCommandK: (() -> Void)?
    var onCommandV: (() -> Void)?
    var onCommandShiftC: (() -> Void)?
    var onCommandA: (() -> Void)?
    var onSpace: (() -> Void)?
    var onCommandLeft: (() -> Void)?
    var onCommandRight: (() -> Void)?
    var onCommandR: (() -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        
        if flags == .command && chars == "r" {
            onCommandR?()
            return true
        }
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
        if flags == .command && (event.keyCode == 123 || chars == "\u{f702}") {
            if let responder = window?.firstResponder as? NSTextView {
                responder.moveToBeginningOfLine(nil)
                return true
            }
            if let responder = window?.firstResponder, responder is NSTextField {
                return super.performKeyEquivalent(with: event)
            }
            onCommandLeft?()
            return true
        }
        if flags == .command && (event.keyCode == 124 || chars == "\u{f703}") {
            if let responder = window?.firstResponder as? NSTextView {
                responder.moveToEndOfLine(nil)
                return true
            }
            if let responder = window?.firstResponder, responder is NSTextField {
                return super.performKeyEquivalent(with: event)
            }
            onCommandRight?()
            return true
        }
        if flags.isEmpty && (event.keyCode == 49 || chars == " ") {
            if let responder = window?.firstResponder, responder is NSTextView || responder is NSTextField {
                return super.performKeyEquivalent(with: event)
            }
            onSpace?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
