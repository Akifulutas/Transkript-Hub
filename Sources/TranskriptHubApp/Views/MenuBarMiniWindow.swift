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
            
            // Middle Content: Playlist Ingestion Prompt OR Default Controls
            if let pending = viewModel.pendingBatchIngestion {
                menuBarPlaylistPromptView(pending: pending)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)),
                        removal: .opacity.combined(with: .scale(scale: 0.96))
                    ))
            } else {
                defaultControlsView
                    .transition(.opacity)
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
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: viewModel.pendingBatchIngestion != nil)
    }
    
    // MARK: - Playlist / Batch Ingestion Prompt (Replaces default controls)
    private func menuBarPlaylistPromptView(pending: PendingBatchIngestion) -> some View {
        VStack(spacing: 10) {
            // Header Badge
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.Premium.crimsonVelvet.opacity(0.18))
                        .frame(width: 26, height: 26)
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.Premium.crimsonVelvet)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(pending.title)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(Color.primary)
                    Text(pending.subtitle)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.cancelBatchIngestion()
                    }
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            // Short, clear question
            Text(viewModel.t("menu_playlist_question"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
            
            if viewModel.isResolvingBatch {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(viewModel.t("menu_playlist_resolving"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.secondary)
                }
                .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    // Option 1: Playlist'in Tamamını Ekle
                    Button(action: {
                        Task { await viewModel.resolveAndIngestBatch(selection: .all) }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 10.5, weight: .bold))
                            Text(viewModel.t("menu_playlist_add_all"))
                                .font(.system(size: 11, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(Color.Premium.crimsonVelvet)
                    
                    // Options: İlk 5 Video / Yalnızca Bu Video
                    HStack(spacing: 6) {
                        Button(action: {
                            Task { await viewModel.resolveAndIngestBatch(selection: .latest5) }
                        }) {
                            Text(viewModel.t("menu_playlist_add_latest_5"))
                                .font(.system(size: 10, weight: .medium))
                                .frame(maxWidth: .infinity)
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        if pending.singleVideoID != nil {
                            Button(action: {
                                Task { await viewModel.resolveAndIngestBatch(selection: .singleVideoOnly) }
                            }) {
                                Text(viewModel.t("menu_playlist_add_single"))
                                    .font(.system(size: 10, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .lineLimit(1)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    
                    // Cancel
                    Button(viewModel.t("action_cancel")) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            viewModel.cancelBatchIngestion()
                        }
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.secondary)
                    .padding(.top, 2)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
    
    // MARK: - Default Controls (When no playlist prompt is active)
    private var defaultControlsView: some View {
        VStack(spacing: 12) {
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
            .onDrop(of: [.fileURL, .url, .item, .content, .text], isTargeted: $isDropTargeted) { providers in
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
        }
    }
    
    private func submitQuickText() {
        let trimmed = quickText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        viewModel.quickInputText = trimmed
        viewModel.addFromQuickInput()
        quickText = ""
    }
    
    private func handleDrop(providers: [NSItemProvider]) {
        _ = viewModel.handleUniversalDrop(providers: providers)
    }
}
