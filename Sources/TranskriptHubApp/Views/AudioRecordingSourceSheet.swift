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
                    Text("Ses Kaydı Başlat")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Kaydetmek istediğiniz ses kaynağını belirleyin")
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
                .help("Kapat (Esc)")
                .accessibilityLabel("Kapat")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Two Big Touchable Cards
            HStack(spacing: 16) {
                sourceSelectionCard(
                    source: .microphone,
                    title: "Canlı Mikrofon",
                    badge: "🎙️ Kullanıcı / Ortam Sesi",
                    description: "Mac mikrofonunuz veya bağlı harici mikrofondan konuşmanızı, podcast'inizi ya da sesli notlarınızı canlı kaydedin.",
                    accentColor: .red,
                    icon: "mic.fill"
                )
                
                sourceSelectionCard(
                    source: .systemAudio,
                    title: "Bilgisayar / Zoom Sesi",
                    badge: "🖥️ Sistem / Toplantı Sesi",
                    description: "Zoom, Google Meet, Microsoft Teams, YouTube veya Mac'inizdeki uygulamalardan gelen sesleri doğrudan kaydedin.",
                    accentColor: .blue,
                    icon: "display"
                )
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
        }
        .frame(width: 540, height: 300)
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
        badge: String,
        description: String,
        accentColor: Color,
        icon: String
    ) -> some View {
        let isHovered = hoveredSource == source
        
        return Button(action: {
            viewModel.isRecordingSourceSheetPresented = false
            Task {
                await viewModel.startRecording(source: source)
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(isHovered ? 0.25 : 0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(accentColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.primary)
                        
                        Text(badge)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accentColor)
                    }
                    
                    Spacer()
                }
                
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                HStack {
                    Spacer()
                    HStack(spacing: 5) {
                        Text("Kaydı Başlat")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(accentColor.opacity(isHovered ? 0.2 : 0.1))
                    .clipShape(Capsule())
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(isHovered ? 0.85 : 0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(accentColor.opacity(isHovered ? 0.6 : 0.2), lineWidth: isHovered ? 1.5 : 1)
            )
            .shadow(color: accentColor.opacity(isHovered ? 0.15 : 0.0), radius: 8, x: 0, y: 3)
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
