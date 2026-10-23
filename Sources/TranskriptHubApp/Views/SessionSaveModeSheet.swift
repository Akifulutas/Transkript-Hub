import SwiftUI
import AppKit

public enum SessionSaveMode: String, CaseIterable, Identifiable, Sendable {
    case individual = "individual" // Ayrı Ayrı Dosyalar
    case combined = "combined"     // Tek Birleşik Dosya
    case both = "both"             // Her İkisi (Ayrı + Birleşik)
    
    public var id: String { rawValue }
}

public struct SessionSaveModeSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let itemCount: Int
    let onConfirm: (SessionSaveMode) -> Void
    let onCancel: () -> Void
    
    @State private var selectedMode: SessionSaveMode = .both
    
    public init(
        viewModel: AppViewModel,
        itemCount: Int,
        onConfirm: @escaping (SessionSaveMode) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.itemCount = itemCount
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.Premium.sapphirePro.opacity(0.35), Color.Premium.sapphireProDeep.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "square.and.arrow.down.on.square.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(viewModel.t("sheet_save_mode_title"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(String(format: viewModel.t("sheet_save_mode_desc"), itemCount))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            // 3 Mode Selection Cards
            VStack(spacing: 10) {
                modeCard(
                    mode: .both,
                    icon: "square.2.layers.3d.top.filled",
                    title: viewModel.t("sheet_save_both_title"),
                    description: viewModel.t("sheet_save_both_desc"),
                    badge: viewModel.t("sheet_save_both_badge")
                )
                
                modeCard(
                    mode: .individual,
                    icon: "doc.on.doc.fill",
                    title: viewModel.t("sheet_save_separate_title"),
                    description: viewModel.t("sheet_save_separate_desc")
                )
                
                modeCard(
                    mode: .combined,
                    icon: "doc.text.fill",
                    title: viewModel.t("sheet_save_combined_title"),
                    description: viewModel.t("sheet_save_combined_desc")
                )
            }
            
            Divider()
            
            // Action Buttons
            HStack(spacing: 12) {
                Button(viewModel.t("action_cancel")) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                
                Spacer()
                
                Button(action: {
                    onConfirm(selectedMode)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11))
                        Text(viewModel.t("action_transcribe_queue"))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }
    
    private func modeCard(
        mode: SessionSaveMode,
        icon: String,
        title: String,
        description: String,
        badge: String? = nil
    ) -> some View {
        let isSelected = selectedMode == mode
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.5))
                .font(.system(size: 16))
            
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(.primary)
                    
                    if let b = badge {
                        Text(b)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.Premium.emeraldMineral.opacity(0.18))
                            .foregroundColor(Color.Premium.emeraldMineral)
                            .clipShape(Capsule())
                    }
                }
                
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedMode = mode
        }
    }
}
