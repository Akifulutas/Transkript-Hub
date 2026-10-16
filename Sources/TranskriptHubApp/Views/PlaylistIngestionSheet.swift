import SwiftUI
import AppKit
import TranskriptHubCore

public struct PlaylistIngestionSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let pending: PendingBatchIngestion
    
    @State private var selectedScope: BatchScopeSelection
    @State private var customCount: Int = 15
    @State private var quickCountChoice: Int = 10
    
    public init(viewModel: AppViewModel, pending: PendingBatchIngestion) {
        self.viewModel = viewModel
        self.pending = pending
        if case .channel = pending.type {
            _selectedScope = State(initialValue: .latest10)
            _quickCountChoice = State(initialValue: 10)
        } else {
            _selectedScope = State(initialValue: .all)
            _quickCountChoice = State(initialValue: 10)
        }
    }
    
    private var isChannel: Bool {
        if case .channel = pending.type { return true }
        return false
    }
    
    private var actionLabel: String {
        switch selectedScope {
        case .all:
            return viewModel.t("sheet_add_all_to_queue")
        case .latest5:
            return String(format: viewModel.t("sheet_add_latest_to_queue"), 5)
        case .latest10:
            return String(format: viewModel.t("sheet_add_latest_to_queue"), 10)
        case .latest20:
            return String(format: viewModel.t("sheet_add_latest_to_queue"), 20)
        case .custom:
            return String(format: viewModel.t("sheet_add_custom_to_queue"), customCount)
        case .singleVideoOnly:
            return viewModel.t("sheet_add_video_to_queue")
        }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isChannel ? [.purple.opacity(0.4), .blue.opacity(0.25)] : [.red.opacity(0.4), .orange.opacity(0.25)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: isChannel ? "play.tv.fill" : "music.note.list")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isChannel ? .purple : .red)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(isChannel ? viewModel.t("sheet_channel_detected") : viewModel.t("sheet_playlist_detected"))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text(isChannel ? viewModel.t("sheet_channel_tag") : viewModel.t("sheet_playlist_tag"))
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isChannel ? Color.purple.opacity(0.2) : Color.red.opacity(0.2))
                            .foregroundColor(isChannel ? .purple : .red)
                            .clipShape(Capsule())
                    }
                    
                    Text(viewModel.t("sheet_batch_question"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            // Scope Selection Cards
            VStack(spacing: 10) {
                // Option 1: All Videos (Tüm Videoları İndir / Ekle - En Üstte)
                sheetOptionCard(
                    isSelected: selectedScope == .all,
                    icon: "square.stack.3d.up.fill",
                    title: isChannel ? viewModel.t("sheet_channel_all_title") : viewModel.t("sheet_playlist_all_title"),
                    description: isChannel ? viewModel.t("sheet_channel_all_desc") : viewModel.t("sheet_playlist_all_desc"),
                    badge: viewModel.t("sheet_save_both_badge"),
                    action: { selectedScope = .all }
                )
                
                // Option 2: Single Video Only (when watch?v=...&list=...)
                if pending.singleVideoID != nil {
                    sheetOptionCard(
                        isSelected: selectedScope == .singleVideoOnly,
                        icon: "play.circle.fill",
                        title: viewModel.t("sheet_single_video_title"),
                        description: viewModel.t("sheet_single_video_desc"),
                        action: { selectedScope = .singleVideoOnly }
                    )
                }
                
                // Option 2: Quick Presets (Son 5, 10, 20)
                let isQuickSelected: Bool = {
                    switch selectedScope {
                    case .latest5, .latest10, .latest20: return true
                    default: return false
                    }
                }()
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: isQuickSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(isQuickSelected ? .accentColor : .secondary.opacity(0.5))
                            .font(.system(size: 16))
                        
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14))
                            .foregroundColor(isQuickSelected ? .accentColor : .secondary)
                            .frame(width: 18)
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(viewModel.t("sheet_latest_videos_title"))
                                .font(.system(size: 13, weight: isQuickSelected ? .semibold : .medium))
                                .foregroundColor(.primary)
                            Text(viewModel.t("sheet_latest_videos_desc"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    
                    // Segmented quick choices
                    HStack(spacing: 8) {
                        quickChoicePill(count: 5, label: String(format: viewModel.t("sheet_latest_n"), 5))
                        quickChoicePill(count: 10, label: String(format: viewModel.t("sheet_latest_n"), 10), badge: isChannel ? viewModel.t("sheet_save_both_badge") : nil)
                        quickChoicePill(count: 20, label: String(format: viewModel.t("sheet_latest_n"), 20))
                    }
                    .padding(.leading, 30)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isQuickSelected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isQuickSelected ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if !isQuickSelected {
                        applyQuickChoice(quickCountChoice)
                    }
                }
                
                // Option 3: Custom Count
                let isCustomSelected: Bool = {
                    if case .custom = selectedScope { return true }
                    return false
                }()
                
                HStack(spacing: 12) {
                    Image(systemName: isCustomSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isCustomSelected ? .accentColor : .secondary.opacity(0.5))
                        .font(.system(size: 16))
                    
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14))
                        .foregroundColor(isCustomSelected ? .accentColor : .secondary)
                        .frame(width: 18)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(viewModel.t("sheet_custom_count_title"))
                            .font(.system(size: 13, weight: isCustomSelected ? .semibold : .medium))
                            .foregroundColor(.primary)
                        Text(viewModel.t("sheet_custom_count_desc"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 8) {
                        Text(String(format: viewModel.t("sheet_n_videos"), customCount))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(isCustomSelected ? .accentColor : .primary)
                            .frame(width: 70, alignment: .trailing)
                        
                        Stepper("", value: $customCount, in: 1...250, step: 5)
                            .labelsHidden()
                            .onChange(of: customCount) { _, newVal in
                                selectedScope = .custom(newVal)
                            }
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isCustomSelected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isCustomSelected ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedScope = .custom(customCount)
                }
            }
            
            // Error Display
            if let errorMsg = viewModel.batchResolutionError {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(errorMsg)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .lineLimit(3)
                    Spacer()
                }
                .padding(10)
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            // Loading State Indicator
            if viewModel.isResolvingBatch {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(viewModel.t("sheet_scanning_videos"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            Divider()
            
            // Footer Buttons
            HStack(spacing: 12) {
                Button(viewModel.t("action_cancel")) {
                    viewModel.cancelBatchIngestion()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
                .disabled(viewModel.isResolvingBatch)
                
                Spacer()
                
                Button(action: {
                    Task {
                        await viewModel.resolveAndIngestBatch(
                            selection: selectedScope,
                            customCount: customCount
                        )
                    }
                }) {
                    HStack(spacing: 6) {
                        if viewModel.isResolvingBatch {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13))
                        }
                        Text(actionLabel)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isResolvingBatch)
            }
        }
        .padding(24)
        .frame(width: 490)
        .background(
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }
    
    // MARK: - Subviews & Helpers
    private func sheetOptionCard(
        isSelected: Bool,
        icon: String,
        title: String,
        description: String,
        badge: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.5))
                .font(.system(size: 16))
            
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(width: 18)
            
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
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
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
            action()
        }
    }
    
    private func quickChoicePill(count: Int, label: String, badge: String? = nil) -> some View {
        let isChosen: Bool = {
            switch selectedScope {
            case .latest5: return count == 5
            case .latest10: return count == 10
            case .latest20: return count == 20
            default: return false
            }
        }()
        
        return Button(action: {
            applyQuickChoice(count)
        }) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.system(size: 11, weight: isChosen ? .bold : .medium))
                
                if let b = badge {
                    Text(b)
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.2))
                        .foregroundColor(.green)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isChosen ? Color.accentColor : Color.white.opacity(0.08))
            )
            .foregroundColor(isChosen ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
    
    private func applyQuickChoice(_ count: Int) {
        quickCountChoice = count
        switch count {
        case 5: selectedScope = .latest5
        case 10: selectedScope = .latest10
        case 20: selectedScope = .latest20
        default: selectedScope = .custom(count)
        }
    }
}
