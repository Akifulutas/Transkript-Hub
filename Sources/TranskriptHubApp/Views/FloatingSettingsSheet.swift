import SwiftUI
import AppKit
import TranskriptHubCore

public struct FloatingSettingsSheet: View {
    @ObservedObject var viewModel: AppViewModel
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Modal Top Bar with Close (X) button
            topBar
            
            Divider()
            
            // Settings Content
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // 1. Interface Language
                    languageSection
                    
                    // 2. Updates & AI Models (Unified Check & Model Scanning)
                    updatesAndModelsSection
                    
                    // 3. Batch Transcript Format (YouTube & Multi-file)
                    batchFormatSection
                    
                    // 4. Help & Maintenance (Onboarding Tour & Media Cache)
                    maintenanceSection
                }
                .padding(22)
            }
        }
        .frame(width: 520, height: 500)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
    }
    
    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "gearshape.2.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.t("section_settings"))
                        .font(.system(size: 15, weight: .bold))
                    Text(viewModel.t("settings_general_subtitle"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Modern Circular Close Button (X)
            Button(action: {
                viewModel.isSettingsPresented = false
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.secondary.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
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
                        viewModel.isSettingsPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            viewModel.initiateUnifiedUpdateCheck()
                        }
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
                        viewModel.isSettingsPresented = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            viewModel.openOnboardingTour()
                        }
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
