import SwiftUI
import AppKit
import TranskriptHubCore

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
                
                // Master Status & Auto-Transcription Mode Card (Liquid Glass)
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
                    
                    // Auto-Transcribe Without Confirmation Toggle
                    HStack(alignment: .top, spacing: 10) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(viewModel.folderWatcher.autoTranscribe ? Color.teal.opacity(0.14) : Color.secondary.opacity(0.1))
                                .frame(width: 28, height: 28)
                            Image(systemName: viewModel.folderWatcher.autoTranscribe ? "bolt.fill" : "hand.tap.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(viewModel.folderWatcher.autoTranscribe ? .teal : .secondary)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.t("watched_auto_transcribe_title"))
                                .font(.system(size: 12, weight: .semibold))
                            Text(viewModel.t("watched_auto_transcribe_desc"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $viewModel.folderWatcher.autoTranscribe)
                            .toggleStyle(.switch)
                    }
                    
                    Divider()
                    
                    // Quick Action & Status Row
                    HStack(spacing: 10) {
                        HStack(spacing: 6) {
                            Image(systemName: "circle.grid.cross.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.accentColor)
                            Text(String(format: viewModel.t("watched_active_sources_count"), viewModel.activeWatchedDirectoriesCount))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            viewModel.triggerFolderScan()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text(viewModel.t("watched_scan_now"))
                            }
                        }
                        .font(.system(size: 11, weight: .medium))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        Button(action: {
                            viewModel.triggerCloudScan()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "icloud.and.arrow.down")
                                Text(viewModel.t("watched_scan_cloud"))
                            }
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Force scan and download any pending .icloud files in watched directory")
                    }
                    
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
                
                // Section 1: Monitored Audio Sources (Input)
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.t("watched_sources_title"))
                            .font(.system(size: 14, weight: .bold))
                        Text(viewModel.t("watched_sources_desc"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    // Source 1: iCloud Drive
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.blue.opacity(0.12))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "icloud.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.blue)
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(viewModel.t("watched_icloud_title"))
                                        .font(.system(size: 13, weight: .semibold))
                                    
                                    if viewModel.folderWatcher.isICloudDriveAvailable {
                                        Text(viewModel.t("watched_icloud_status_ready"))
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.green)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.green.opacity(0.12)))
                                    } else {
                                        Text(viewModel.t("watched_icloud_status_missing"))
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.orange.opacity(0.12)))
                                    }
                                    
                                    if viewModel.folderWatcher.isICloudTranskriptFolderReady {
                                        Text(viewModel.t("watched_icloud_folder_ready"))
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.blue.opacity(0.12)))
                                    }
                                }
                                Text(viewModel.t("watched_icloud_desc"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $viewModel.folderWatcher.watchiCloudDrive)
                                .toggleStyle(.switch)
                        }
                        
                        // iCloud Setup & Finder Buttons
                        HStack(spacing: 8) {
                            Button(action: {
                                viewModel.setupICloudTranskriptFolderAndSetOutput()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder.badge.plus")
                                    Text(viewModel.t("watched_icloud_folder_setup_btn"))
                                }
                                .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            
                            Button(viewModel.t("action_open_finder")) {
                                viewModel.openInFinder(path: FolderWatcher.iCloudTranskriptDirectory.path)
                            }
                            .font(.system(size: 11))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            
                            Spacer()
                        }
                        .padding(.top, 2)
                        
                        if viewModel.folderWatcher.watchiCloudDrive {
                            Divider()
                            
                            HStack {
                                Toggle(isOn: $viewModel.folderWatcher.watchiCloudRoot) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(viewModel.t("watched_icloud_root_opt"))
                                            .font(.system(size: 11, weight: .medium))
                                        Text(FolderWatcher.iCloudRootDirectory.path)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .toggleStyle(.checkbox)
                                
                                Spacer()
                                
                                Button(viewModel.t("action_open_finder")) {
                                    viewModel.openInFinder(path: FolderWatcher.iCloudRootDirectory.path)
                                }
                                .font(.system(size: 10))
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(8)
                        }
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 12, glowColor: viewModel.folderWatcher.watchiCloudDrive ? .blue.opacity(0.5) : .white, material: .ultraThinMaterial)
                    
                    // Source 2: Apple Voice Memos (Sesli Notlar)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.orange.opacity(0.12))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "waveform")
                                    .font(.system(size: 16))
                                    .foregroundColor(.orange)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(viewModel.t("watched_voicememos_title"))
                                        .font(.system(size: 13, weight: .semibold))
                                    
                                    if viewModel.folderWatcher.isVoiceMemosDirectlyAccessible {
                                        Text(viewModel.t("watched_status_accessible"))
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.green)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.green.opacity(0.12)))
                                    } else {
                                        Text(viewModel.t("watched_status_fda_needed"))
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.orange)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.orange.opacity(0.12)))
                                    }
                                }
                                Text(viewModel.t("watched_voicememos_desc"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $viewModel.isVoiceMemosEnabled)
                                .toggleStyle(.switch)
                        }
                        
                        if viewModel.folderWatcher.watchVoiceMemos {
                            Divider()
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(FolderWatcher.voiceMemosDirectory.path)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                
                                if !viewModel.folderWatcher.isVoiceMemosDirectlyAccessible {
                                    Button(viewModel.t("watched_open_settings")) {
                                        viewModel.openFullDiskAccessSettings()
                                    }
                                    .font(.system(size: 10, weight: .semibold))
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                } else {
                                    Button(viewModel.t("action_open_finder")) {
                                        viewModel.openInFinder(path: FolderWatcher.voiceMemosDirectory.path)
                                    }
                                    .font(.system(size: 10))
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(8)
                        }
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 12, glowColor: viewModel.folderWatcher.watchVoiceMemos ? .orange.opacity(0.5) : .white, material: .ultraThinMaterial)
                    
                    // Source 3: Custom Watched Folder (İzlenecek Klasör)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.purple.opacity(0.12))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 16))
                                    .foregroundColor(.purple)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(viewModel.t("watched_custom_title"))
                                        .font(.system(size: 13, weight: .semibold))
                                    if viewModel.folderWatcher.watchCustomFolder && viewModel.folderWatcher.customFolderURL != nil {
                                        Text(viewModel.t("settings_active"))
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.purple)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.purple.opacity(0.12)))
                                    }
                                }
                                Text(viewModel.t("watched_custom_desc"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: $viewModel.folderWatcher.watchCustomFolder)
                                .toggleStyle(.switch)
                        }
                        
                        Divider()
                        
                        if let customURL = viewModel.folderWatcher.customFolderURL {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(customURL.lastPathComponent)
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(customURL.path)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Button(viewModel.t("watched_change_folder")) {
                                    viewModel.selectCustomWatchedFolder()
                                }
                                .font(.system(size: 10))
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Button(viewModel.t("watched_reset_folder")) {
                                    viewModel.resetCustomWatchedFolder()
                                }
                                .font(.system(size: 10))
                                .buttonStyle(.plain)
                                .foregroundColor(.red.opacity(0.8))
                                
                                Button(viewModel.t("action_open_finder")) {
                                    viewModel.openInFinder(path: customURL.path)
                                }
                                .font(.system(size: 10))
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(8)
                        } else {
                            HStack {
                                Text(viewModel.t("watched_no_custom_selected"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Button(viewModel.t("watched_choose_folder")) {
                                    viewModel.selectCustomWatchedFolder()
                                }
                                .font(.system(size: 11, weight: .semibold))
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.03))
                            .cornerRadius(8)
                        }
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 12, glowColor: viewModel.folderWatcher.watchCustomFolder ? .purple.opacity(0.5) : .white, material: .ultraThinMaterial)
                }
                
                // Section 2: Transcript Output Directory (.txt Save Location)
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(viewModel.t("watched_output_title"))
                            .font(.system(size: 14, weight: .bold))
                        Text(viewModel.t("watched_output_desc"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center, spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.teal.opacity(0.14))
                                    .frame(width: 34, height: 34)
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.teal)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(viewModel.outputDirectoryURL.lastPathComponent)
                                        .font(.system(size: 13, weight: .semibold))
                                    
                                    Text(viewModel.isCustomOutputDirectory ? viewModel.t("watched_output_custom_badge") : viewModel.t("watched_output_default_badge"))
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(viewModel.isCustomOutputDirectory ? .teal : .secondary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule().fill(
                                                (viewModel.isCustomOutputDirectory ? Color.teal : Color.secondary).opacity(0.12)
                                            )
                                        )
                                }
                                
                                Text(viewModel.outputDirectoryURL.path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            
                            Spacer()
                            
                            Button(viewModel.isCustomOutputDirectory ? viewModel.t("watched_change_folder") : viewModel.t("watched_choose_folder")) {
                                viewModel.selectOutputDirectory()
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            
                            if viewModel.isCustomOutputDirectory {
                                Button(viewModel.t("watched_reset_folder")) {
                                    viewModel.resetOutputDirectory()
                                }
                                .font(.system(size: 10))
                                .buttonStyle(.plain)
                                .foregroundColor(.red.opacity(0.8))
                            }
                            
                            Button(viewModel.t("action_open_finder")) {
                                viewModel.openInFinder(path: viewModel.outputDirectoryURL.path)
                            }
                            .font(.system(size: 10))
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 12, glowColor: .teal.opacity(0.45), material: .ultraThinMaterial)
                }
                
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
                
                Spacer()
            }
            .padding(20)
        }
        .navigationTitle(viewModel.t("section_watched_folder"))
        .onAppear {
            viewModel.checkFullDiskAccess()
        }
    }
}

// MARK: - Dedicated Native Modal Sheet
public struct WatchedFolderSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Sheet Header with Apple-Style Done Button
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.teal.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: "folder.fill.badge.gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.teal)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.t("watched_title"))
                        .font(.system(size: 14, weight: .bold))
                    Text(viewModel.t("watched_subtitle"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    dismiss()
                }) {
                    Text(viewModel.t("action_done"))
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            Divider()
            
            WatchedFolderView(viewModel: viewModel)
        }
        .frame(width: 680, height: 560)
        .background(.ultraThinMaterial)
    }
}
