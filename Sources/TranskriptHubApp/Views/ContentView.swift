import SwiftUI
import AppKit
import UniformTypeIdentifiers
import TranskriptHubCore

public struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var isAddMediaPresented: Bool = false
    
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
                            navigationBackBar(title: viewModel.t("hub_card_history"))
                            HistoryListView(viewModel: viewModel)
                        }
                    case .watchedFolder:
                        VStack(spacing: 0) {
                            navigationBackBar(title: viewModel.t("section_watched_folder"))
                            WatchedFolderView(viewModel: viewModel)
                        }
                    case .settings:
                        VStack(spacing: 0) {
                            navigationBackBar(title: viewModel.t("section_settings"))
                            SettingsView(viewModel: viewModel)
                        }
                    }
                }
            }
            .frame(minWidth: 900, minHeight: 600)
            .toolbar {
                mainToolbar
            }
            .sheet(isPresented: Binding(
                get: { viewModel.showMainWindowPlaylistSheet && viewModel.pendingBatchIngestion != nil },
                set: { if !$0 { viewModel.cancelBatchIngestion() } }
            )) {
                if let pending = viewModel.pendingBatchIngestion {
                    PlaylistIngestionSheet(viewModel: viewModel, pending: pending)
                }
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
            .sheet(isPresented: $viewModel.isRecordingSourceSheetPresented, onDismiss: {
                viewModel.recordingSourceSheetDidDismiss()
            }) {
                AudioRecordingSourceSheet(viewModel: viewModel)
            }
            .alert(
                viewModel.recordingAlertPermission == nil ? viewModel.t("record_failed_title") : viewModel.t("record_permission_title"),
                isPresented: Binding(
                    get: { viewModel.recordingAlertMessage != nil },
                    set: { if !$0 { viewModel.dismissRecordingAlert() } }
                )
            ) {
                if viewModel.recordingAlertPermission != nil {
                    Button(viewModel.t("watched_open_settings")) { viewModel.openRecordingPermissionSettings() }
                    Button(viewModel.t("action_cancel"), role: .cancel) { viewModel.dismissRecordingAlert() }
                } else {
                    Button(viewModel.t("action_ok"), role: .cancel) { viewModel.dismissRecordingAlert() }
                }
            } message: {
                Text(viewModel.recordingAlertMessage ?? "")
            }
            .sheet(isPresented: $viewModel.isWatchedFolderPresented) {
                WatchedFolderSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.isOnboardingPresented) {
                AppOnboardingView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.isUnifiedUpdatePresented) {
                UnifiedUpdateModalView(viewModel: viewModel)
            }
            .alert(
                viewModel.t("voice_memos_import_title"),
                isPresented: $viewModel.isVoiceMemosPromptPresented
            ) {
                Button(viewModel.t("voice_memos_import_all")) {
                    viewModel.confirmVoiceMemosImport(importAll: true)
                }
                Button(viewModel.t("voice_memos_watch_new_only")) {
                    viewModel.confirmVoiceMemosImport(importAll: false)
                }
                Button(viewModel.t("action_cancel"), role: .cancel) {
                    viewModel.cancelVoiceMemosImport()
                }
            } message: {
                Text(String(format: viewModel.t("voice_memos_import_message"), viewModel.pendingVoiceMemosCount))
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
        }
        .onDrop(of: [.fileURL, .url, .item, .content, .text], isTargeted: $viewModel.isDropTargetActive) { providers in
            viewModel.handleUniversalDrop(providers: providers)
        }
        .overlay(
            Group {
                if viewModel.isDropTargetActive {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.accentColor.opacity(0.85), lineWidth: 2)
                            .background(Color.accentColor.opacity(0.06))
                        
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc.fill")
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                            Text(viewModel.t("hub_tooltip_drop_zone_title"))
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.primary)
                        }
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: Color.black.opacity(0.2), radius: 12, y: 6)
                    }
                    .padding(6)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: viewModel.isDropTargetActive)
        )
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
                    .init(color: Color.white.opacity(0.025), location: 0.0),
                    .init(color: Color(hex: "#8E9EAB").opacity(0.02), location: 0.35),
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
                onCommandV: {
                    viewModel.addFromClipboard()
                },
                onCommandO: {
                    viewModel.promptForLocalAudioFiles()
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
        
        ToolbarItemGroup(placement: .automatic) {
            // Add Media Button (YouTube link, Paste Clipboard, Choose Audio File)
            Button(action: {
                isAddMediaPresented.toggle()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text(viewModel.t("toolbar_add_media"))
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .liquidGlassCapsule(glowColor: Color.accentColor.opacity(0.35), material: .ultraThinMaterial)
            }
            .buttonStyle(.plain)
            .help(viewModel.t("toolbar_add_media_help"))
            .popover(isPresented: $isAddMediaPresented, arrowEdge: .bottom) {
                AddMediaPopoverView(
                    viewModel: viewModel,
                    isPresented: $isAddMediaPresented
                )
            }
            
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
            .help("\(viewModel.t("section_settings")) (⌘,)")
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
                    Text(viewModel.t("nav_back_to_hub"))
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
        case .tiny: return "Tiny (75 MB - \(viewModel.t("model_speed_fast")))"
        case .base: return "Base (142 MB - \(viewModel.t("model_speed_standard")))"
        case .small: return "Small (466 MB - \(viewModel.t("model_speed_balanced")))"
        case .medium: return "Medium (1.5 GB)"
        case .largeV3Turbo: return "Large-v3-Turbo (1.6 GB - \(viewModel.t("model_speed_best")))"
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
        case "fr": return viewModel.t("hub_lang_fr")
        case "es": return viewModel.t("hub_lang_es")
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
    let onCommandV: () -> Void
    let onCommandO: () -> Void
    let onCommandShiftC: () -> Void
    let onCommandA: () -> Void
    let onSpace: () -> Void
    let onCommandLeft: () -> Void
    let onCommandRight: () -> Void
    let onCommandR: () -> Void
    
    init(
        onCommandV: @escaping () -> Void,
        onCommandO: @escaping () -> Void = {},
        onCommandShiftC: @escaping () -> Void,
        onCommandA: @escaping () -> Void,
        onSpace: @escaping () -> Void = {},
        onCommandLeft: @escaping () -> Void = {},
        onCommandRight: @escaping () -> Void = {},
        onCommandR: @escaping () -> Void = {}
    ) {
        self.onCommandV = onCommandV
        self.onCommandO = onCommandO
        self.onCommandShiftC = onCommandShiftC
        self.onCommandA = onCommandA
        self.onSpace = onSpace
        self.onCommandLeft = onCommandLeft
        self.onCommandRight = onCommandRight
        self.onCommandR = onCommandR
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyInterceptingView()
        view.onCommandV = onCommandV
        view.onCommandO = onCommandO
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
    var onCommandV: (() -> Void)?
    var onCommandO: (() -> Void)?
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
        
        if flags == .command && chars == "o" {
            onCommandO?()
            return true
        }
        
        if flags == .command && chars == "r" {
            onCommandR?()
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
