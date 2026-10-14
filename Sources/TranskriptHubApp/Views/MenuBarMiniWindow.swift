import SwiftUI
import AppKit

struct MenuBarMiniWindow: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var quickText: String = ""
    
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
                        .fill(viewModel.isFolderWatching ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 7, height: 7)
                    Text(viewModel.isFolderWatching ? "İzleniyor" : "Hazır")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .liquidGlassCapsule(glowColor: viewModel.isFolderWatching ? .green : .white, material: .ultraThinMaterial)
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
                
                TextField("Link yapıştır...", text: $quickText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit {
                        submitQuickText()
                    }
                
                if !quickText.isEmpty {
                    Button("Ekle") {
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
            
            // Action Buttons
            HStack(spacing: 8) {
                Button(action: { viewModel.addFromClipboard() }) {
                    Label("Panodan Al", systemImage: "doc.on.clipboard")
                        .font(.system(size: 11))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                
                if let lastText = viewModel.selectedItem?.transcript ?? viewModel.historyItems.first?.snippet {
                    Button(action: { viewModel.copyTranscript(text: lastText) }) {
                        Label(viewModel.copiedToast ? "Kopyalandı!" : "Son Metni Kopyala", systemImage: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            
            Divider()
            
            // Bottom Controls
            HStack {
                Button("Ana Pencereyi Aç") {
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                
                Spacer()
                
                Button("Çıkış") {
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
}
