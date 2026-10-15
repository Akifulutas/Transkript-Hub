import SwiftUI
import TranskriptHubCore

// MARK: - Live Audio Meter & Microphone Recording View (Milestone 2)

public struct LiveAudioMeterView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject var recordingEngine: AudioRecordingEngine
    @Environment(\.dismiss) private var dismiss
    
    @State private var isPulsing: Bool = false
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        self.recordingEngine = viewModel.recordingEngine
    }
    
    public var body: some View {
        VStack(spacing: 24) {
            // Header with Pulsing Recording Indicator
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.25))
                        .frame(width: 28, height: 28)
                        .scaleEffect(isPulsing && !recordingEngine.isPaused ? 1.3 : 1.0)
                        .opacity(isPulsing && !recordingEngine.isPaused ? 0.3 : 0.8)
                    
                    Circle()
                        .fill(recordingEngine.isPaused ? Color.orange : Color.red)
                        .frame(width: 14, height: 14)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(recordingEngine.isPaused ? "Kayıt Duraklatıldı" : "Ses Kaydediliyor...")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("Apple Silicon vDSP Gerçek Zamanlı Spektrum")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Formatted Duration Timer
                Text(formattedDuration(recordingEngine.recordedDuration))
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(recordingEngine.isPaused ? .secondary : .accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(8)
            }
            .padding(.horizontal, 4)
            
            // 16 Frequency Bars (vDSP Real-Time Metering)
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 6) {
                    ForEach(0..<16, id: \.self) { index in
                        let level = (index < recordingEngine.frequencyBands.count) ? recordingEngine.frequencyBands[index] : 0.05
                        FrequencyBar(level: CGFloat(level), isPaused: recordingEngine.isPaused)
                    }
                }
                .frame(height: 72)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
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
            
            // Transport & Action Controls
            HStack(spacing: 16) {
                // Cancel Button
                Button(action: {
                    viewModel.cancelRecording()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .semibold))
                        Text("İptal Et")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                
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
                            .font(.system(size: 12, weight: .semibold))
                        Text(recordingEngine.isPaused ? "Devam Et" : "Duraklat")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                
                // Stop & Transcribe Button
                Button(action: {
                    Task {
                        await viewModel.stopRecordingAndTranscribe()
                    }
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .bold))
                        Text("Kaydı Tamamla & Deşifre Et")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(
                        LinearGradient(
                            colors: [Color.accentColor, Color.purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .cornerRadius(9)
                    .shadow(color: Color.accentColor.opacity(0.4), radius: 8, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .liquidGlassCard(glowColor: Color.accentColor.opacity(0.4), material: .regularMaterial)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
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
