import SwiftUI
import AppKit
import TranskriptHubCore

public struct PlaylistIngestionSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let pending: PendingBatchIngestion
    
    @State private var selectedScope: BatchScopeSelection
    @State private var customCount: Int = 15
    
    public init(viewModel: AppViewModel, pending: PendingBatchIngestion) {
        self.viewModel = viewModel
        self.pending = pending
        // Default to latest10 for channels (channels can have thousands of videos), or all for playlists
        if case .channel = pending.type {
            _selectedScope = State(initialValue: .latest10)
        } else {
            _selectedScope = State(initialValue: pending.singleVideoID != nil ? .all : .all)
        }
    }
    
    private var isChannel: Bool {
        if case .channel = pending.type { return true }
        return false
    }
    
    private var actionLabel: String {
        switch selectedScope {
        case .all:
            return "Tüm Videoları Ekle"
        case .latest5:
            return "Son 5 Videoyu Ekle"
        case .latest10:
            return "Son 10 Videoyu Ekle"
        case .latest20:
            return "Son 20 Videoyu Ekle"
        case .custom:
            return "\(customCount) Videoyu Ekle"
        case .singleVideoOnly:
            return "Yalnızca Tek Videoyu Ekle"
        }
    }
    
    public var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isChannel ? [.purple.opacity(0.35), .blue.opacity(0.2)] : [.red.opacity(0.35), .orange.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 46, height: 46)
                    
                    Image(systemName: isChannel ? "play.tv.fill" : "music.note.list")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isChannel ? .purple : .red)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(isChannel ? "YouTube Kanalı Algılandı" : "Oynatma Listesi Algılandı")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text(isChannel ? "KANAL" : "PLAYLIST")
                            .font(.system(size: 9, weight: .heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isChannel ? Color.purple.opacity(0.2) : Color.red.opacity(0.2))
                            .foregroundColor(isChannel ? .purple : .red)
                            .clipShape(Capsule())
                    }
                    
                    Text(pending.subtitle)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(.bottom, 2)
            
            // Subtitle Description
            Text("Bu bağlantıda birden fazla video bulunuyor. Kuyruğa kaç adet videonun aktarılmasını istersiniz?")
                .font(.system(size: 12.5))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Scope Selection Grid / List
            VStack(spacing: 8) {
                // If single video ID is available (e.g. watch?v=...&list=...)
                if pending.singleVideoID != nil {
                    selectionCard(
                        scope: .singleVideoOnly,
                        icon: "play.circle.fill",
                        title: "Yalnızca Bu Tek Videoyu Ekle",
                        subtitle: "Oynatma listesini yoksay, sadece açtığınız videoyu kuyruğa al"
                    )
                }
                
                selectionCard(
                    scope: .all,
                    icon: "square.stack.3d.up.fill",
                    title: isChannel ? "Tüm Kanal Videoları" : "Tüm Oynatma Listesi",
                    subtitle: isChannel ? "Kanalın yüklediği tüm videoları kuyruğa alır" : "Listedeki tüm videoları sırayla kuyruğa ekler",
                    badge: isChannel ? nil : "Önerilen"
                )
                
                HStack(spacing: 8) {
                    compactScopeButton(scope: .latest5, title: "Son 5", icon: "5.circle.fill")
                    compactScopeButton(scope: .latest10, title: "Son 10", icon: "10.circle.fill", badge: isChannel ? "Önerilen" : nil)
                    compactScopeButton(scope: .latest20, title: "Son 20", icon: "20.circle.fill")
                }
                
                // Custom Count Tile
                customCountCard
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
                    Text("Videolar taranıyor ve başlıklar alınıyor...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(10)
                .background(Color.accentColor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            Spacer(minLength: 4)
            
            // Action Buttons
            HStack(spacing: 12) {
                Button(action: {
                    viewModel.cancelBatchIngestion()
                }) {
                    Text("Vazgeç")
                        .font(.system(size: 12, weight: .medium))
                        .frame(minWidth: 80)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .liquidGlassCapsule(glowColor: .white.opacity(0.2), material: .ultraThinMaterial)
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
                            Image(systemName: "plus.square.fill.on.square.fill")
                                .font(.system(size: 12))
                        }
                        Text(actionLabel)
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(viewModel.isResolvingBatch)
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(
            VisualEffectView(material: .sidebar, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }
    
    // MARK: - Subviews
    private func selectionCard(
        scope: BatchScopeSelection,
        icon: String,
        title: String,
        subtitle: String,
        badge: String? = nil
    ) -> some View {
        let isSelected = selectedScope == scope
        return Button(action: {
            selectedScope = scope
        }) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.5))
                    .font(.system(size: 16))
                
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                            .foregroundColor(.primary)
                        
                        if let b = badge {
                            Text(b)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.green.opacity(0.2))
                                .foregroundColor(.green)
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func compactScopeButton(
        scope: BatchScopeSelection,
        title: String,
        icon: String,
        badge: String? = nil
    ) -> some View {
        let isSelected = selectedScope == scope
        return Button(action: {
            selectedScope = scope
        }) {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 11))
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium))
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
                .foregroundColor(isSelected ? .accentColor : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var customCountCard: some View {
        let isSelected: Bool = {
            if case .custom = selectedScope { return true }
            return false
        }()
        
        return Button(action: {
            selectedScope = .custom(customCount)
        }) {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.5))
                    .font(.system(size: 16))
                
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Özel Sayı")
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(.primary)
                    Text("Belirttiğiniz sayıda en yeni videoyu aktarır")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Stepper control
                HStack(spacing: 6) {
                    Text("\(customCount) video")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(isSelected ? .accentColor : .secondary)
                        .frame(width: 70, alignment: .trailing)
                    
                    Stepper("", value: $customCount, in: 1...500, step: 5)
                        .labelsHidden()
                        .onChange(of: customCount) { _, newVal in
                            selectedScope = .custom(newVal)
                        }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
