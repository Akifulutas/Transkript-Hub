import SwiftUI
import AppKit

struct MenuBarMiniWindow: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var quickText: String = ""
    @State private var isDropTargeted: Bool = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.accentColor)
                }
                
                Text("Transkript Hub")
                    .font(.system(size: 13, weight: .bold))
                
                Spacer()
                
                // Live Status Pulse
                HStack(spacing: 4) {
                    Circle()
                        .fill(viewModel.isFolderWatching ? Color.Premium.emeraldMineral : Color.gray.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text(viewModel.isFolderWatching ? viewModel.t("status_watching") : viewModel.t("status_ready"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .liquidGlassCapsule(glowColor: viewModel.isFolderWatching ? Color.Premium.emeraldMineral : .white, material: .ultraThinMaterial)
            }
            
            Divider()
            
            // Actionable Status Card
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.actionableSummary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                if viewModel.isProcessing {
                    ProgressView(value: viewModel.progressFraction)
                        .progressViewStyle(.linear)
                        .padding(.top, 2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: 10, glowColor: .white.opacity(0.4), material: .ultraThinMaterial)
            
            // Quick Paste YouTube Link or Text
            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                TextField(viewModel.t("menu_paste_link_placeholder"), text: $quickText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit {
                        submitQuickText()
                    }
                
                if !quickText.isEmpty {
                    Button(viewModel.t("action_add")) {
                        submitQuickText()
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .liquidGlassCapsule(glowColor: .white.opacity(0.6), material: .ultraThinMaterial)
            
            // Drag & Drop Area for Files
            VStack(spacing: 4) {
                Image(systemName: isDropTargeted ? "arrow.down.circle.fill" : "arrow.down.doc")
                    .font(.system(size: 15))
                    .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary)
                Text(isDropTargeted ? viewModel.t("hub_drop_target") : viewModel.t("menu_drop_sub"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isDropTargeted ? Color.accentColor : Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
            )
            .onDrop(of: [.fileURL, .url], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }
            
            // Action Buttons
            HStack(spacing: 8) {
                Button(action: {
                    Task {
                        await viewModel.startRecording()
                    }
                }) {
                    Label(viewModel.t("menu_record_audio"), systemImage: "mic.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.Premium.crimsonVelvet)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                Button(action: { viewModel.addFromClipboard() }) {
                    Label(viewModel.t("menu_paste_clipboard"), systemImage: "doc.on.clipboard")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                if let lastText = viewModel.selectedItem?.transcript ?? viewModel.historyItems.first?.snippet {
                    Button(action: { viewModel.copyTranscript(text: lastText) }) {
                        Label(viewModel.copiedToast ? viewModel.t("action_copied") : viewModel.t("action_get_text"), systemImage: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            Divider()
            
            // Bottom Controls
            HStack {
                Button(viewModel.t("menu_open_main")) {
                    viewModel.bringMainWindowToFront()
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                
                Spacer()
                
                Button(viewModel.t("section_settings")) {
                    viewModel.openSettings()
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Button(viewModel.t("menu_quit")) {
                    NSApp.terminate(nil)
                }
                .font(.system(size: 11))
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(width: 320)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func submitQuickText() {
        let trimmed = quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.quickInputText = trimmed
        viewModel.addFromQuickInput()
        quickText = ""
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
}
