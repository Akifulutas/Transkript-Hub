import SwiftUI
import AppKit
import TranskriptHubCore

struct WatchedFolderView: View {
    @ObservedObject var viewModel: AppViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 1. Full Disk Access Warning Banner (Prominently displayed if missing)
                if !viewModel.fullDiskAccessStatus.isGranted {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.Premium.champagneBronze)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.t("watched_fda_warning_title"))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.primary)
                            Text(viewModel.t("watched_fda_warning_desc"))
                                .font(.system(size: 11))
                                .foregroundStyle(Color.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            viewModel.openFullDiskAccessSettings()
                        }) {
                            Text(viewModel.t("watched_open_settings"))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(12)
                    .background(Color.Premium.champagneBronze.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.Premium.champagneBronze.opacity(0.35), lineWidth: 1)
                    )
                }
                
                // 2. Auto-Transcription Setting Card
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(viewModel.folderWatcher.autoTranscribe ? Color.Premium.obsidianTeal.opacity(0.18) : Color.primary.opacity(0.06))
                            .frame(width: 32, height: 32)
                        Image(systemName: viewModel.folderWatcher.autoTranscribe ? "bolt.fill" : "bolt.slash")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(viewModel.folderWatcher.autoTranscribe ? Color.Premium.obsidianTeal : Color.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.t("watched_auto_transcribe_title"))
                            .font(.system(size: 12.5, weight: .semibold))
                        Text(viewModel.t("watched_auto_transcribe_desc"))
                            .font(.system(size: 11))
                            .foregroundStyle(Color.secondary)
                    }
                    
                    Spacer()
                    
                    Toggle("", isOn: $viewModel.folderWatcher.autoTranscribe)
                        .toggleStyle(.switch)
                }
                .padding(12)
                .background(Color.primary.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                )
                
                // 3. Audio Sources Section
                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.t("watched_sources_title"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.secondary)
                        .textCase(.uppercase)
                    
                    VStack(spacing: 0) {
                        // Source A: iCloud Drive
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.Premium.slateAzure.opacity(0.15))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "icloud.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.Premium.slateAzure)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewModel.t("watched_icloud_title"))
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(viewModel.t("watched_icloud_desc"))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Color.secondary)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                viewModel.openInFinder(path: FolderWatcher.iCloudRootDirectory.path)
                            }) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help(viewModel.t("action_open_finder"))
                            
                            Toggle("", isOn: $viewModel.folderWatcher.watchiCloudDrive)
                                .toggleStyle(.switch)
                        }
                        .padding(12)
                        
                        Divider()
                            .padding(.leading, 54)
                        
                        // Source B: Apple Voice Memos
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.Premium.champagneBronze.opacity(0.15))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "waveform")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.Premium.champagneBronze)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(viewModel.t("watched_voicememos_title"))
                                        .font(.system(size: 12.5, weight: .semibold))
                                    
                                    if !viewModel.folderWatcher.isVoiceMemosDirectlyAccessible {
                                        Button(action: {
                                            viewModel.openFullDiskAccessSettings()
                                        }) {
                                            HStack(spacing: 3) {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .font(.system(size: 8))
                                                Text(viewModel.t("watched_fda_badge_needed"))
                                                    .font(.system(size: 9, weight: .bold))
                                            }
                                            .foregroundStyle(Color.Premium.champagneBronze)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Capsule().fill(Color.Premium.champagneBronze.opacity(0.14)))
                                        }
                                        .buttonStyle(.plain)
                                        .help(viewModel.t("watched_fda_warning_desc"))
                                    }
                                }
                                Text(viewModel.t("watched_voicememos_desc"))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Color.secondary)
                            }
                            
                            Spacer()
                            
                            if viewModel.folderWatcher.isVoiceMemosDirectlyAccessible {
                                Button(action: {
                                    viewModel.openInFinder(path: FolderWatcher.voiceMemosDirectory.path)
                                }) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help(viewModel.t("action_open_finder"))
                            }
                            
                            Toggle("", isOn: $viewModel.isVoiceMemosEnabled)
                                .toggleStyle(.switch)
                        }
                        .padding(12)
                        
                        Divider()
                            .padding(.leading, 54)
                        
                        // Source C: Custom Folder
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.Premium.cashmereViolet.opacity(0.15))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.Premium.cashmereViolet)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewModel.t("watched_custom_title"))
                                    .font(.system(size: 12.5, weight: .semibold))
                                
                                if let custom = viewModel.folderWatcher.customFolderURL {
                                    Text(custom.path)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(Color.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                } else {
                                    Text(viewModel.t("watched_no_custom_selected"))
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Color.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if let custom = viewModel.folderWatcher.customFolderURL {
                                Button(action: {
                                    viewModel.selectCustomWatchedFolder()
                                }) {
                                    Text(viewModel.t("watched_change_folder"))
                                        .font(.system(size: 10.5, weight: .medium))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                
                                Button(action: {
                                    viewModel.resetCustomWatchedFolder()
                                }) {
                                    Image(systemName: "xmark.circle")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                                .help(viewModel.t("watched_reset_folder"))
                                
                                Button(action: {
                                    viewModel.openInFinder(path: custom.path)
                                }) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help(viewModel.t("action_open_finder"))
                            } else {
                                Button(action: {
                                    viewModel.selectCustomWatchedFolder()
                                }) {
                                    Text(viewModel.t("watched_choose_folder"))
                                        .font(.system(size: 10.5, weight: .semibold))
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            
                            Toggle("", isOn: Binding(
                                get: { viewModel.folderWatcher.watchCustomFolder && viewModel.folderWatcher.customFolderURL != nil },
                                set: { newValue in
                                    if newValue {
                                        if viewModel.folderWatcher.customFolderURL != nil {
                                            viewModel.folderWatcher.watchCustomFolder = true
                                        } else {
                                            viewModel.selectCustomWatchedFolder()
                                        }
                                    } else {
                                        viewModel.folderWatcher.watchCustomFolder = false
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                        }
                        .padding(12)
                    }
                    .background(Color.primary.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                    )
                }
                
                // 4. Output Location Section
                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.t("watched_output_title"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.secondary)
                        .textCase(.uppercase)
                    
                    if !viewModel.folderWatcher.isICloudTranskriptFolderReady {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.Premium.slateAzure.opacity(0.15))
                                    .frame(width: 30, height: 30)
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.Premium.slateAzure)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(viewModel.t("watched_icloud_folder_missing_title"))
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(viewModel.t("watched_icloud_folder_missing_desc"))
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(Color.secondary)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                viewModel.setupICloudTranskriptFolderAndSetOutput()
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 11))
                                    Text(viewModel.t("watched_icloud_folder_setup_btn"))
                                        .font(.system(size: 11, weight: .medium))
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                        .padding(12)
                        .background(Color.Premium.slateAzure.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(Color.Premium.slateAzure.opacity(0.2), lineWidth: 1)
                        )
                    }
                    
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.Premium.obsidianTeal.opacity(0.15))
                                .frame(width: 30, height: 30)
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.Premium.obsidianTeal)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(viewModel.outputDirectoryURL.lastPathComponent)
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text(viewModel.isCustomOutputDirectory ? viewModel.t("watched_output_custom_badge") : viewModel.t("watched_output_default_badge"))
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(viewModel.isCustomOutputDirectory ? Color.Premium.obsidianTeal : Color.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill((viewModel.isCustomOutputDirectory ? Color.Premium.obsidianTeal : Color.secondary).opacity(0.12)))
                            }
                            Text(viewModel.outputDirectoryURL.path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            viewModel.selectOutputDirectory()
                        }) {
                            Text(viewModel.isCustomOutputDirectory ? viewModel.t("watched_change_folder") : viewModel.t("watched_choose_folder"))
                                .font(.system(size: 10.5, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        
                        if viewModel.isCustomOutputDirectory {
                            Button(action: {
                                viewModel.resetOutputDirectory()
                            }) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(viewModel.t("watched_reset_folder"))
                        }
                        
                        Button(action: {
                            viewModel.openInFinder(path: viewModel.outputDirectoryURL.path)
                        }) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(viewModel.t("action_open_finder"))
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .stroke(Color.primary.opacity(0.07), lineWidth: 1)
                    )
                }
                
                // 5. Cloud Downloading Status Bar (if active)
                if viewModel.isCloudDownloading {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(viewModel.t("watched_cloud_downloading"))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        
                        ForEach(Array(viewModel.activeCloudDownloads).sorted(), id: \.self) { name in
                            Text(name)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Color.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(10)
                    .background(Color.accentColor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(18)
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
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            Divider()
            
            WatchedFolderView(viewModel: viewModel)
        }
        .frame(width: 620, height: 500)
        .background(.ultraThinMaterial)
    }
}
