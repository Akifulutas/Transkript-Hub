import SwiftUI
import AppKit

public struct AudioRecordingSourceSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var hoveredSource: AudioRecordingSource? = nil
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.red)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.t("sheet_recording_source_title"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(viewModel.t("sheet_recording_source_desc"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    viewModel.isRecordingSourceSheetPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("\(viewModel.t("action_cancel")) (Esc)")
                .accessibilityLabel(viewModel.t("action_cancel"))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Balanced Compact Source Cards
            HStack(spacing: 14) {
                sourceSelectionCard(
                    source: .microphone,
                    title: viewModel.t("record_source_mic"),
                    accentColor: .red,
                    icon: "mic.fill"
                )
                
                sourceSelectionCard(
                    source: .systemAudio,
                    title: viewModel.t("record_source_system"),
                    accentColor: .blue,
                    icon: "display"
                )
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
        }
        .frame(width: 430, height: 215)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 10)
    }
    
    private func sourceSelectionCard(
        source: AudioRecordingSource,
        title: String,
        accentColor: Color,
        icon: String
    ) -> some View {
        let isHovered = hoveredSource == source
        
        return Button(action: {
            viewModel.requestRecording(source: source)
        }) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(isHovered ? 0.24 : 0.14))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(accentColor)
                }
                
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                
                HStack(spacing: 4) {
                    Text(viewModel.t("record_action_start"))
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 11))
                }
                .foregroundStyle(accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(accentColor.opacity(isHovered ? 0.22 : 0.1))
                .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(isHovered ? 0.85 : 0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accentColor.opacity(isHovered ? 0.6 : 0.2), lineWidth: isHovered ? 1.5 : 1)
            )
            .shadow(color: accentColor.opacity(isHovered ? 0.16 : 0.0), radius: 8, x: 0, y: 3)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredSource = hovering ? source : nil
        }
    }
}
