import SwiftUI
import TranskriptHubCore

// MARK: - Live Audio Meter & Microphone Recording View (Milestone 2)

public struct LiveAudioMeterView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var recordingEngine: AudioRecordingEngine
    @Environment(\.dismiss) private var dismiss
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        self.recordingEngine = viewModel.recordingEngine
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header with Recording Indicator and Close Button
            HStack(spacing: 12) {
                Circle()
                    .fill(recordingEngine.isPaused ? Color.orange : Color.red)
                    .frame(width: 10, height: 10)
                    .shadow(color: (recordingEngine.isPaused ? Color.orange : Color.red).opacity(0.4), radius: 3, x: 0, y: 1)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(recordingEngine.isPaused ? viewModel.t("live_recording_paused") : viewModel.t("live_recording_active"))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    HStack(spacing: 5) {
                        Text(viewModel.recordingSource == .microphone ? viewModel.t("record_source_mic") : viewModel.t("record_source_system"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color.accentColor)
                        
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        
                        Text(viewModel.t("live_realtime_spectrum"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .lineLimit(1)
                }
                
                Spacer()
                
                // Formatted Duration Timer (Fixed-width & Monospaced Digit)
                Text(formattedDuration(recordingEngine.recordedDuration))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(recordingEngine.isPaused ? .secondary : .accentColor)
                    .frame(width: 88, alignment: .center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(8)
                
                Button(action: {
                    viewModel.cancelRecording()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(Color.secondary.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("\(viewModel.t("live_cancel_help")) (Esc)")
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            
            Divider()
            
            VStack(spacing: 20) {
                // 16 Frequency Bars (vDSP Real-Time Metering)
                VStack(spacing: 10) {
                    HStack(alignment: .center, spacing: 8) {
                        ForEach(0..<16, id: \.self) { index in
                            let level = (index < recordingEngine.frequencyBands.count) ? recordingEngine.frequencyBands[index] : 0.05
                            FrequencyBar(level: CGFloat(level), isPaused: recordingEngine.isPaused)
                        }
                    }
                    .frame(height: 76)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
                    
                    // Overall RMS Input Level Bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 5)
                            
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [.accentColor, .purple, .pink],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(4, geo.size.width * CGFloat(recordingEngine.currentMeteringLevel)), height: 5)
                                .animation(.easeOut(duration: 0.08), value: recordingEngine.currentMeteringLevel)
                        }
                    }
                    .frame(height: 5)
                }
                
                // Live Recording Info Text
                HStack(spacing: 5) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(viewModel.recordingSource == .microphone ? viewModel.t("live_recording_mic_info") : viewModel.t("live_recording_system_info"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
                
                // Transport & Action Controls (Rock Solid, Zero Layout Shift)
                HStack(spacing: 12) {
                    // Cancel Button
                    Button(action: {
                        viewModel.cancelRecording()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11, weight: .semibold))
                            Text(viewModel.t("action_cancel"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Pause / Resume Toggle
                    Button(action: {
                        if recordingEngine.isPaused {
                            try? recordingEngine.resumeRecording()
                        } else {
                            try? recordingEngine.pauseRecording()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: recordingEngine.isPaused ? "play.fill" : "pause.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text(recordingEngine.isPaused ? viewModel.t("live_resume") : viewModel.t("live_pause"))
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 58)
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.primary.opacity(0.08))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    
                    // Stop & Transcribe Primary Button
                    Button(action: {
                        Task {
                            await viewModel.stopRecordingAndTranscribe()
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .bold))
                            Text(viewModel.t("live_finish_transcribe"))
                                .font(.system(size: 12, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [Color.accentColor, Color.purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .cornerRadius(8)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 550)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 8)
    }
    
    private func formattedDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        let s = total % 60
        let m = total / 60
        let tenths = Int((seconds.truncatingRemainder(dividingBy: 1.0)) * 10)
        return String(format: "%02d:%02d.%d", m, s, tenths)
    }
}

// MARK: - Frequency Bar Component

private struct FrequencyBar: View {
    let level: CGFloat
    let isPaused: Bool
    
    private var barHeight: CGFloat {
        let clamped = max(0.06, min(level, 1.0))
        return clamped * 56.0
    }
    
    var body: some View {
        VStack {
            Spacer()
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isPaused ? [Color.secondary.opacity(0.5), Color.secondary] : [Color.accentColor, Color.purple],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .frame(width: 8, height: max(6, barHeight))
                .animation(.spring(response: 0.12, dampingFraction: 0.65), value: level)
            Spacer()
        }
        .frame(width: 10, height: 60)
    }
}
