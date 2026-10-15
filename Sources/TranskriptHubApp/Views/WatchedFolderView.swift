import SwiftUI
import AppKit

struct WatchedFolderView: View {
    @ObservedObject var viewModel: AppViewModel
    @AppStorage("dismissedFDABanner") private var dismissedFDABanner: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Banner
                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 50, height: 50)
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 24))
                            .foregroundColor(.accentColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.t("watched_title"))
                            .font(.system(size: 15, weight: .bold))
                        Text(viewModel.t("watched_subtitle"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 4)
                
                // Status Card (Liquid Glass)
                VStack(spacing: 14) {
                    HStack {
                        HStack(spacing: 8) {
                            ZStack {
                                Circle()
                                    .fill(viewModel.isFolderWatching ? Color.green : Color.gray)
                                    .frame(width: 9, height: 9)
                                if viewModel.isFolderWatching {
                                    Circle()
                                        .stroke(Color.green.opacity(0.4), lineWidth: 2)
                                        .frame(width: 15, height: 15)
                                }
                            }
                            
                            Text(viewModel.isFolderWatching ? viewModel.t("watched_active") : viewModel.t("watched_inactive"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $viewModel.isFolderWatching)
                            .toggleStyle(.switch)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(viewModel.t("watched_path"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text(viewModel.watchedDirectoryPath)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Button(viewModel.t("watched_scan_cloud")) {
                                viewModel.triggerCloudScan()
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Force scan and download any pending .icloud files in watched directory")
                            
                            Button(viewModel.t("action_open_finder")) {
                                viewModel.openInFinder(path: viewModel.watchedDirectoryPath)
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    
                    // Automatic iCloud Download Status
                    HStack(spacing: 8) {
                        Image(systemName: "icloud.and.arrow.down")
                            .foregroundColor(.accentColor)
                            .font(.system(size: 13))
                        
                        Text(viewModel.t("watched_cloud_status"))
                            .font(.system(size: 12, weight: .medium))
                        
                        Text(viewModel.t("watched_cloud_active"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    .padding(.top, 4)
                    
                    if viewModel.isCloudDownloading {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(viewModel.t("watched_cloud_downloading"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.accentColor)
                            
                            ForEach(Array(viewModel.activeCloudDownloads).sorted(), id: \.self) { name in
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text(name)
                                        .font(.system(size: 11, weight: .medium))
                                        .lineLimit(1)
                                    Spacer()
                                    Text("Downloading...")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .padding(8)
                                .background(Color.accentColor.opacity(0.08))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(16)
                .liquidGlass(cornerRadius: 14, glowColor: viewModel.isFolderWatching ? .green.opacity(0.6) : .white, material: .ultraThinMaterial)
                
                // Full Disk Access Banner for Voice Memos
                if !viewModel.fullDiskAccessStatus.isGranted && !dismissedFDABanner {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 22))
                            .foregroundColor(.orange)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.t("watched_fda_title"))
                                .font(.system(size: 12, weight: .semibold))
                            Text(viewModel.t("watched_fda_desc"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(viewModel.t("watched_open_settings")) {
                            viewModel.openFullDiskAccessSettings()
                        }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                dismissedFDABanner = true
                            }
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.secondary)
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .help("Dismiss this alert")
                    }
                    .padding(14)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                    )
                }
                
                // Tips / Guide Card (Liquid Glass)
                VStack(alignment: .leading, spacing: 10) {
                    Label("iPhone Sesli Notlar (Voice Memos) Entegrasyonu", systemImage: "iphone")
                        .font(.system(size: 13, weight: .semibold))
                    
                    Text("1. iPhone'unuzda **Ayarlar > Apple Kimliği > iCloud > Sesli Notlar** ayarının açık olduğundan emin olun.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Text("2. iPhone veya Apple Watch'tan aldığınız ses kaydını iCloud Drive üzerindeki **Transkript** klasörüne paylaştığınızda Mac'iniz kaydı anında metne döker.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Text("3. Uygulama açık olduğu sürece (menü çubuğu simgesi), pencere kapalı olsa dahi yeni sesler arka planda sessizce işlenir.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .liquidGlass(cornerRadius: 14, glowColor: .white.opacity(0.5), material: .ultraThinMaterial)
                
                Spacer()
            }
            .padding(20)
        }
        .navigationTitle("İzlenen Klasör")
        .onAppear {
            viewModel.checkFullDiskAccess()
        }
    }
}
