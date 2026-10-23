import SwiftUI
import AppKit

public struct AudioRecordingSourceSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var hoveredSource: AudioRecordingSource? = nil
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    private struct PermissionWarningInfo {
        let title: String
        let description: String
        let buttonTitle: String
        let action: () -> Void
    }
    
    private var activePermissionWarning: PermissionWarningInfo? {
        let micMissing = !viewModel.isMicrophonePermissionGranted
        let systemMissing = !viewModel.isSystemAudioPermissionGranted
        
        // If user is hovering or focusing a specific card, prioritize that card's permission state
        if let hovered = hoveredSource {
            if hovered == .microphone && micMissing {
                return micWarningInfo
            } else if hovered == .systemAudio && systemMissing {
                return systemAudioWarningInfo
            }
        }
        
        // Otherwise, show active warning if any
        if micMissing && systemMissing {
            return PermissionWarningInfo(
                title: viewModel.t("record_permission_both_title"),
                description: viewModel.t("record_permission_both_desc"),
                buttonTitle: viewModel.t("record_permission_request_btn"),
                action: {
                    if viewModel.microphonePermissionStatus == .notDetermined {
                        viewModel.requestMicrophonePermission()
                    } else if !viewModel.isSystemAudioPermissionGranted {
                        viewModel.requestSystemAudioPermission()
                    } else {
                        viewModel.openMicrophoneSettings()
                    }
                }
            )
        } else if micMissing {
            return micWarningInfo
        } else if systemMissing {
            return systemAudioWarningInfo
        }
        return nil
    }
    
    private var micWarningInfo: PermissionWarningInfo {
        let isNotDetermined = viewModel.microphonePermissionStatus == .notDetermined
        return PermissionWarningInfo(
            title: viewModel.t("record_permission_mic_title"),
            description: viewModel.t("record_permission_mic_desc"),
            buttonTitle: isNotDetermined ? viewModel.t("record_permission_request_btn") : viewModel.t("watched_open_settings"),
            action: {
                if isNotDetermined {
                    viewModel.requestMicrophonePermission()
                } else {
                    viewModel.openMicrophoneSettings()
                }
            }
        )
    }
    
    private var systemAudioWarningInfo: PermissionWarningInfo {
        let hasOpened = viewModel.hasOpenedSystemAudioSettings
        return PermissionWarningInfo(
            title: viewModel.t("record_permission_system_title"),
            description: viewModel.t("record_permission_system_desc"),
            buttonTitle: hasOpened ? viewModel.t("record_relaunch_app") : viewModel.t("record_permission_open_settings"),
            action: {
                if hasOpened {
                    viewModel.relaunchApp()
                } else {
                    viewModel.openSystemAudioSettings()
                }
            }
        )
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.Premium.crimsonVelvet.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.Premium.crimsonVelvet)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.t("sheet_recording_source_title"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.primary)
                    Text(viewModel.t("sheet_recording_source_desc"))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    viewModel.isRecordingSourceSheetPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("\(viewModel.t("action_cancel")) (Esc)")
                .accessibilityLabel(viewModel.t("action_cancel"))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            
            Divider()
            
            // Proactive Permission Alert (Matching WatchedFolderView design)
            if let warning = activePermissionWarning {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.Premium.champagneBronze)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(warning.title)
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(warning.description)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        warning.action()
                    }) {
                        Text(warning.buttonTitle)
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.Premium.champagneBronze.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.Premium.champagneBronze.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Balanced Compact Source Cards
            HStack(spacing: 14) {
                sourceSelectionCard(
                    source: .microphone,
                    title: viewModel.t("record_source_mic"),
                    description: viewModel.t("record_source_mic_desc"),
                    accentColor: Color.Premium.crimsonVelvet,
                    icon: "mic.fill",
                    isMissingPermission: !viewModel.isMicrophonePermissionGranted
                )
                .hoverHelpTooltip(
                    title: viewModel.t("hub_tooltip_mic_source_title"),
                    description: viewModel.t("hub_tooltip_mic_source_desc"),
                    icon: "mic.fill",
                    statusColor: Color.Premium.crimsonVelvet,
                    placement: .bottomLeading,
                    width: 220
                )
                
                sourceSelectionCard(
                    source: .systemAudio,
                    title: viewModel.t("record_source_system"),
                    description: viewModel.t("record_source_system_desc"),
                    accentColor: Color.Premium.slateAzure,
                    icon: "display",
                    isMissingPermission: !viewModel.isSystemAudioPermissionGranted
                )
                .hoverHelpTooltip(
                    title: viewModel.t("hub_tooltip_system_source_title"),
                    description: viewModel.t("hub_tooltip_system_source_desc"),
                    icon: "display",
                    statusColor: Color.Premium.slateAzure,
                    placement: .bottomTrailing,
                    width: 220
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, activePermissionWarning == nil ? 14 : 10)
            .padding(.bottom, 8)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
            
            // Helpful Explanation Footer
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                Text(viewModel.t("sheet_recording_footer_info"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.4))
        }
        .frame(width: 460)
        .fixedSize(horizontal: true, vertical: true)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 10)
        .onAppear {
            viewModel.checkAudioPermissions()
        }
    }
    
    private func sourceSelectionCard(
        source: AudioRecordingSource,
        title: String,
        description: String,
        accentColor: Color,
        icon: String,
        isMissingPermission: Bool
    ) -> some View {
        let isHovered = hoveredSource == source
        let cardTint = isMissingPermission ? Color.Premium.champagneBronze : accentColor
        
        return Button(action: {
            if isMissingPermission {
                if source == .microphone {
                    if viewModel.microphonePermissionStatus == .notDetermined {
                        viewModel.requestMicrophonePermission()
                    } else {
                        viewModel.openMicrophoneSettings()
                    }
                } else {
                    if viewModel.hasOpenedSystemAudioSettings {
                        viewModel.relaunchApp()
                    } else {
                        viewModel.requestSystemAudioPermission()
                    }
                }
                return
            }
            viewModel.requestRecording(source: source)
        }) {
            VStack(spacing: 8) {
                // Top Icon & Permission Tag
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(cardTint.opacity(isHovered ? 0.24 : 0.14))
                            .frame(width: 44, height: 44)
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(cardTint)
                    }
                    .frame(maxWidth: .infinity)
                    
                    if isMissingPermission {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8, weight: .bold))
                            Text(viewModel.t("watched_fda_badge_needed"))
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(Color.Premium.champagneBronze)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.Premium.champagneBronze.opacity(0.15))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule().stroke(Color.Premium.champagneBronze.opacity(0.35), lineWidth: 0.5)
                        )
                    }
                }
                
                Text(title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.primary)
                
                Text(description)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                
                if isMissingPermission {
                    let btnText = (source == .systemAudio && viewModel.hasOpenedSystemAudioSettings)
                        ? viewModel.t("record_relaunch_app")
                        : viewModel.t("record_permission_request_btn")
                    let btnIcon = (source == .systemAudio && viewModel.hasOpenedSystemAudioSettings)
                        ? "arrow.clockwise"
                        : "hand.raised.fill"
                    HStack(spacing: 4) {
                        Text(btnText)
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: btnIcon)
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(Color.Premium.champagneBronze)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.Premium.champagneBronze.opacity(isHovered ? 0.22 : 0.1))
                    .clipShape(Capsule())
                } else {
                    HStack(spacing: 4) {
                        Text(viewModel.t("record_action_start"))
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(accentColor.opacity(isHovered ? 0.22 : 0.1))
                    .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, minHeight: 140)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(isHovered ? 0.85 : 0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(cardTint.opacity(isHovered ? 0.6 : (isMissingPermission ? 0.4 : 0.2)), lineWidth: isHovered ? 1.5 : 1)
            )
            .shadow(color: cardTint.opacity(isHovered ? 0.16 : 0.0), radius: 8, x: 0, y: 3)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isHovered)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredSource = hovering ? source : nil
        }
    }
}
