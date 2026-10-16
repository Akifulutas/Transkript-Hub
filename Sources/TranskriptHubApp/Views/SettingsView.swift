import SwiftUI
import AppKit
import TranskriptHubCore

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var downloadingModel: WhisperModel? = nil
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Interface Language Section
                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.t("settings_language"))
                        .font(.system(size: 14, weight: .bold))
                    
                    Text(viewModel.t("settings_language_desc"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    Picker("", selection: $viewModel.appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(14)
                    .liquidGlass(cornerRadius: 14, glowColor: .white.opacity(0.6), material: .ultraThinMaterial)
                }
                
                // Whisper Models Section
                VStack(alignment: .leading, spacing: 12) {
                    Text(viewModel.t("settings_whisper_models"))
                        .font(.system(size: 14, weight: .bold))
                    
                    Text(viewModel.t("settings_whisper_desc"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 8) {
                        modelRow(model: .tiny, name: "Tiny", size: "75 MB", desc: viewModel.t("model_tiny_desc"))
                        Divider()
                        modelRow(model: .base, name: "Base", size: "142 MB", desc: viewModel.t("model_base_desc"))
                        Divider()
                        modelRow(model: .small, name: "Small", size: "466 MB", desc: viewModel.t("model_small_desc"))
                        Divider()
                        modelRow(model: .largeV3Turbo, name: "Large-v3-Turbo", size: "1.6 GB", desc: viewModel.t("model_turbo_desc"))
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 14, glowColor: .white.opacity(0.6), material: .ultraThinMaterial)
                }
                
                // Storage Section
                VStack(alignment: .leading, spacing: 10) {
                    Text(viewModel.t("settings_output_dir"))
                        .font(.system(size: 14, weight: .bold))
                    
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.t("settings_txt_save_path"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(viewModel.outputDirectoryURL.path)
                                .font(.system(size: 11, design: .monospaced))
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
                        
                        Button(viewModel.t("settings_open_folder")) {
                            viewModel.openInFinder(path: viewModel.outputDirectoryURL.path)
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 14, glowColor: .white.opacity(0.6), material: .ultraThinMaterial)
                    
                    // Session Media Cache Card
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.t("hub_media_cache"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(String(format: viewModel.t("hub_media_cache_size"), viewModel.sessionMediaCacheSizeString))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        }
                        
                        Spacer()
                        
                        Button(viewModel.t("hub_clear_cache")) {
                            viewModel.evictSessionMediaCache()
                        }
                        .font(.system(size: 11))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 14, glowColor: .white.opacity(0.6), material: .ultraThinMaterial)
                }
                
                Spacer()
            }
            .padding(20)
        }
        .navigationTitle(viewModel.t("section_settings"))
    }
    
    private func modelRow(model: WhisperModel, name: String, size: String, desc: String) -> some View {
        let isDownloaded = viewModel.modelManager.isModelDownloaded(model)
        
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 13, weight: .semibold))
                    Text(size)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    if viewModel.selectedModel == model {
                        Text(viewModel.t("settings_active"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .liquidGlassCapsule(glowColor: .accentColor, material: .ultraThinMaterial)
                    }
                }
                
                Text(desc)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isDownloaded {
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                        Text(viewModel.t("settings_downloaded"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
                    Button(role: .destructive) {
                        viewModel.deleteModelInSettings(model)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(4)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.t("hub_delete_model_help"))
                }
            } else if viewModel.downloadingModel == model {
                HStack(spacing: 8) {
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView(value: viewModel.modelDownloadFraction)
                            .progressViewStyle(.linear)
                            .frame(width: 130)
                        
                        Text(viewModel.modelDownloadStatusText.isEmpty ? viewModel.t("hub_processing") : viewModel.modelDownloadStatusText)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        viewModel.cancelModelDownload()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.t("hub_cancel_download_help"))
                }
            } else {
                Button(viewModel.t("settings_download")) {
                    viewModel.downloadModelInSettings(model)
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
