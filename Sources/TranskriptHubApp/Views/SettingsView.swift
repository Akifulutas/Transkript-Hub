import SwiftUI
import AppKit
import TranskriptHubCore

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Interface Language
                languageSection
                
                // 2. Updates & AI Models (Unified Check & Model Scanning)
                updatesAndModelsSection
                
                // 3. Batch Transcript Format (YouTube & Multi-file)
                batchFormatSection
                
                // 4. Help & Maintenance (Onboarding Tour & Media Cache)
                maintenanceSection
                
                Spacer()
            }
            .padding(24)
        }
        .navigationTitle(viewModel.t("section_settings"))
    }
    
    // MARK: - 1. Language Section
    private var languageSection: some View {
        cardSection(title: viewModel.t("settings_language"), icon: "globe") {
            VStack(alignment: .leading, spacing: 10) {
                Text(viewModel.t("settings_language_desc"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Picker("", selection: $viewModel.appLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }
    
    // MARK: - 2. Updates & AI Models Section
    private var updatesAndModelsSection: some View {
        cardSection(title: viewModel.t("settings_updates_models_title"), icon: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Transkript Hub")
                            .font(.system(size: 14, weight: .bold))
                        Text(String(format: viewModel.t("settings_current_version"), UpdateChecker.currentVersion))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.initiateUnifiedUpdateCheck()
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "sparkles")
                            Text(viewModel.t("settings_check_updates_and_models"))
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                
                Text(viewModel.t("settings_updates_models_desc"))
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
                
                Divider()
                
                HStack {
                    Toggle(viewModel.t("settings_auto_check_updates"), isOn: $viewModel.autoCheckUpdates)
                        .toggleStyle(.switch)
                        .font(.system(size: 11))
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.openInBrowser(url: "https://github.com/Akifulutas/Transkript-Hub")
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                            Text(viewModel.t("settings_open_repo"))
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - 3. Batch Format Preferences Section
    private var batchFormatSection: some View {
        cardSection(title: viewModel.t("settings_batch_format_title"), icon: "doc.on.doc") {
            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.t("settings_save_format_question"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Picker("", selection: $viewModel.sessionSaveMode) {
                    Text(viewModel.t("settings_save_both_opt")).tag(SessionSaveMode.both)
                    Text(viewModel.t("settings_save_individual_opt")).tag(SessionSaveMode.individual)
                    Text(viewModel.t("settings_save_combined_opt")).tag(SessionSaveMode.combined)
                }
                .pickerStyle(.radioGroup)
                .font(.system(size: 11))
            }
        }
    }
    
    // MARK: - 4. Help & Maintenance Section
    private var maintenanceSection: some View {
        cardSection(title: viewModel.t("settings_help_maintenance_title"), icon: "sparkles") {
            VStack(alignment: .leading, spacing: 12) {
                // Restart Onboarding Tour
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.t("menu_onboarding_tour"))
                            .font(.system(size: 12, weight: .semibold))
                        Text(viewModel.t("settings_restart_onboarding_desc"))
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.openOnboardingTour()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "play.circle.fill")
                            Text(viewModel.t("settings_restart_onboarding"))
                        }
                        .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Divider()
                
                // Session Media Cache Cleanup
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.t("hub_media_cache"))
                            .font(.system(size: 12, weight: .semibold))
                        Text(String(format: viewModel.t("hub_media_cache_size"), viewModel.sessionMediaCacheSizeString))
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.evictSessionMediaCache()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                            Text(viewModel.t("hub_clear_cache"))
                        }
                        .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }
    
    // MARK: - Card Container Helper
    private func cardSection<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .bold))
            }
            
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liquidGlass(cornerRadius: 12, glowColor: .white.opacity(0.45), material: .ultraThinMaterial)
        }
    }
}
