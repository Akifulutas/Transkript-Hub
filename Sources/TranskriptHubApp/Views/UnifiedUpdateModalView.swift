import SwiftUI
import AppKit
import TranskriptHubCore

public struct UnifiedUpdateModalView: View {
    @ObservedObject var viewModel: AppViewModel
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Modal Header
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
                
                Text(viewModel.t("update_modal_title"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.primary)
                
                Spacer()
                
                Button(action: {
                    viewModel.isUnifiedUpdatePresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Modal Body
            ScrollView {
                VStack(spacing: 16) {
                    if viewModel.isCheckingUnifiedUpdates {
                        checkingStateView
                    } else if viewModel.isDownloadingAppUpdate {
                        downloadingAppStateView
                    } else if viewModel.downloadingModel != nil {
                        downloadingModelStateView
                    } else if let successModel = viewModel.unifiedModelDownloadSuccessName {
                        modelDownloadSuccessView(modelName: successModel)
                    } else {
                        resultsStateView
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 520)
        .frame(minHeight: 320, maxHeight: 460)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - State 1: Checking
    private var checkingStateView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 24)
            
            ProgressView()
                .controlSize(.regular)
                .scaleEffect(1.2)
            
            VStack(spacing: 6) {
                Text(viewModel.t("update_checking_title"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.primary)
                
                Text(viewModel.unifiedStatusMessage)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            Spacer().frame(height: 16)
            
            Button(viewModel.t("update_btn_cancel")) {
                viewModel.isUnifiedUpdatePresented = false
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
    
    // MARK: - State 2: Downloading App Update
    private var downloadingAppStateView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 16)
            
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 56, height: 56)
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            
            VStack(spacing: 6) {
                Text(viewModel.t("update_app_downloading"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.primary)
                
                if let update = viewModel.unifiedAppUpdate {
                    Text("Transkript Hub v\(update.latestVersion)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
            }
            
            ProgressView(value: viewModel.appUpdateDownloadFraction, total: 1.0)
                .progressViewStyle(.linear)
                .padding(.horizontal, 24)
            
            Text(viewModel.appUpdateDownloadStatus)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.secondary)
            
            Spacer().frame(height: 8)
            
            Button(viewModel.t("update_btn_cancel")) {
                viewModel.cancelAppUpdateDownload()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
    
    // MARK: - State 3: Downloading AI Model
    private var downloadingModelStateView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 16)
            
            ZStack {
                Circle()
                    .fill(Color.Premium.cashmereViolet.opacity(0.18))
                    .frame(width: 56, height: 56)
                Image(systemName: "cpu.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.Premium.cashmereViolet)
            }
            
            VStack(spacing: 6) {
                Text(viewModel.t("update_model_downloading"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.primary)
                
                if let model = viewModel.downloadingModel {
                    Text(model.displayName)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
            }
            
            ProgressView(value: viewModel.modelDownloadFraction, total: 1.0)
                .progressViewStyle(.linear)
                .padding(.horizontal, 24)
            
            Text(viewModel.modelDownloadStatusText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Color.secondary)
            
            Spacer().frame(height: 8)
            
            Button(viewModel.t("update_btn_cancel")) {
                viewModel.cancelModelDownload()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
    
    // MARK: - State 4: Model Download Success
    private func modelDownloadSuccessView(modelName: String) -> some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 16)
            
            ZStack {
                Circle()
                    .fill(Color.Premium.emeraldMineral.opacity(0.16))
                    .frame(width: 54, height: 54)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(Color.Premium.emeraldMineral)
            }
            
            VStack(spacing: 6) {
                Text(String(format: viewModel.t("update_success_model"), modelName))
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(Color.primary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                
                Text("Model transkript motorunuz için hemen aktif hale getirildi.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.secondary)
            }
            
            Spacer().frame(height: 8)
            
            Button(viewModel.t("update_btn_done")) {
                viewModel.isUnifiedUpdatePresented = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }
    
    // MARK: - State 5: Results Presentation (App Update / AI Model / Up to Date)
    @ViewBuilder
    private var resultsStateView: some View {
        // A. App Update Card (if newer version available)
        if let appUpdate = viewModel.unifiedAppUpdate {
            appUpdateCard(appUpdate)
        }
        
        // B. New AI Model Card (if recommended model not installed)
        if let model = viewModel.unifiedCandidateModel {
            aiModelCard(model)
        }
        
        // C. Everything Up to Date (if no app update and no new model)
        if viewModel.unifiedIsUpToDate || (viewModel.unifiedAppUpdate == nil && viewModel.unifiedCandidateModel == nil) {
            everythingUpToDateCard
        }
    }
    
    // MARK: - App Update Card View
    private func appUpdateCard(_ update: AppUpdateInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.Premium.emeraldMineral.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.Premium.emeraldMineral)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(viewModel.t("update_app_title"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.primary)
                        
                        Text("v\(update.latestVersion)")
                            .font(.system(size: 10.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.Premium.emeraldMineral)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.Premium.emeraldMineral.opacity(0.16))
                            )
                    }
                    
                    Text(viewModel.t("update_app_desc"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.secondary)
                }
                
                Spacer()
            }
            
            if !update.releaseNotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(update.releaseNotes)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            
            HStack(spacing: 10) {
                Button(action: {
                    viewModel.downloadAppUpdateAndRelaunch()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(viewModel.t("update_app_action_relaunch"))
                            .font(.system(size: 11.5, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(Color.Premium.emeraldMineral)
                
                Button(viewModel.t("update_btn_later")) {
                    viewModel.isUnifiedUpdatePresented = false
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Spacer()
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.Premium.emeraldMineral.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - AI Model Card View
    private func aiModelCard(_ model: WhisperModelSpec) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.Premium.cashmereViolet.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.Premium.cashmereViolet)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(viewModel.t("update_model_title"))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.primary)
                        
                        if let badge = model.badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.Premium.cashmereViolet)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(Color.Premium.cashmereViolet.opacity(0.14))
                                )
                        }
                    }
                    
                    Text(String(format: viewModel.t("update_model_prompt"), model.displayName, model.sizeDescription))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.primary.opacity(0.9))
                }
                
                Spacer()
            }
            
            // Model Details
            HStack(spacing: 12) {
                Text(model.summary)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color.secondary)
                
                Spacer()
                
                HStack(spacing: 8) {
                    HStack(spacing: 2) {
                        Text("\(viewModel.t("model_speed_label")):")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Color.secondary)
                        Text("\(formattedScore(model.speedScore))/10")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                    
                    HStack(spacing: 2) {
                        Text("\(viewModel.t("model_accuracy_label")):")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Color.secondary)
                        Text("\(formattedScore(model.accuracyScore))/10")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Color.Premium.emeraldMineral)
                    }
                }
            }
            .padding(10)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            
            HStack(spacing: 10) {
                Button(action: {
                    viewModel.downloadModelInUpdateDialog(model.model)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(viewModel.t("update_model_action_download"))
                            .font(.system(size: 11.5, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                
                Button(viewModel.t("update_btn_not_now")) {
                    viewModel.isUnifiedUpdatePresented = false
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                Spacer()
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
    
    // MARK: - Everything Up to Date Card View
    private var everythingUpToDateCard: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 12)
            
            ZStack {
                Circle()
                    .fill(Color.Premium.emeraldMineral.opacity(0.18))
                    .frame(width: 58, height: 58)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.Premium.emeraldMineral)
            }
            
            VStack(spacing: 6) {
                Text(viewModel.t("update_uptodate_title"))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.primary)
                
                Text(String(format: viewModel.t("update_uptodate_desc"), UpdateChecker.currentVersion))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            Spacer().frame(height: 8)
            
            Button(viewModel.t("update_btn_done")) {
                viewModel.isUnifiedUpdatePresented = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }
    
    private func formattedScore(_ score: Double) -> String {
        if score.truncatingRemainder(dividingBy: 1.0) == 0 {
            return "\(Int(score))"
        } else {
            return String(format: "%.1f", score)
        }
    }
}
