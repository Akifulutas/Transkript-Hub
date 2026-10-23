import SwiftUI
import AppKit
import TranskriptHubCore

// MARK: - Pipeline Bezier Shape
struct PipelineBezierShape: Shape {
    var startPoint: CGPoint
    var endPoint: CGPoint
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: startPoint)
        let midY = (startPoint.y + endPoint.y) * 0.5
        path.addCurve(
            to: endPoint,
            control1: CGPoint(x: startPoint.x, y: midY),
            control2: CGPoint(x: endPoint.x, y: midY)
        )
        return path
    }
}

// MARK: - Interactive Neon Pipeline Conduit Canvas
struct NeonConduitCanvasView: View {
    let isVoiceMemosActive: Bool
    let isICloudActive: Bool
    let isCustomActive: Bool
    let isVoiceMemosFDAMissing: Bool
    
    // Neon Color Palette
    private let amberNeon = Color(hex: "#FFB300")
    private let cyanNeon = Color(hex: "#00E5FF")
    private let purpleNeon = Color(hex: "#D500F9")
    private let inactiveTube = Color.primary.opacity(0.08)
    
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat(time * 38.0).truncatingRemainder(dividingBy: 36)
            
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height
                
                // Top Pod Emitter Anchors
                let p1Start = CGPoint(x: w * 0.17, y: 0)
                let p2Start = CGPoint(x: w * 0.50, y: 0)
                let p3Start = CGPoint(x: w * 0.83, y: 0)
                
                // Bottom Collector Intake Valves
                let p1End = CGPoint(x: w * 0.44, y: h)
                let p2End = CGPoint(x: w * 0.50, y: h)
                let p3End = CGPoint(x: w * 0.56, y: h)
                
                ZStack {
                    // Pipe 1: Voice Memos -> Collector
                    singlePipe(
                        start: p1Start,
                        end: p1End,
                        isActive: isVoiceMemosActive,
                        isWarning: isVoiceMemosFDAMissing,
                        color: amberNeon,
                        phase: phase
                    )
                    
                    // Pipe 2: iCloud Drive -> Collector
                    singlePipe(
                        start: p2Start,
                        end: p2End,
                        isActive: isICloudActive,
                        isWarning: false,
                        color: cyanNeon,
                        phase: phase
                    )
                    
                    // Pipe 3: Custom Folders -> Collector
                    singlePipe(
                        start: p3Start,
                        end: p3End,
                        isActive: isCustomActive,
                        isWarning: false,
                        color: purpleNeon,
                        phase: phase
                    )
                    
                    // Intake Port Rings at Bottom
                    intakePort(at: p1End, isActive: isVoiceMemosActive, color: amberNeon)
                    intakePort(at: p2End, isActive: isICloudActive, color: cyanNeon)
                    intakePort(at: p3End, isActive: isCustomActive, color: purpleNeon)
                }
            }
        }
        .frame(height: 80)
    }
    
    @ViewBuilder
    private func singlePipe(
        start: CGPoint,
        end: CGPoint,
        isActive: Bool,
        isWarning: Bool,
        color: Color,
        phase: CGFloat
    ) -> some View {
        let shape = PipelineBezierShape(startPoint: start, endPoint: end)
        
        // 1. Dark Conduit Tunnel (Always visible)
        shape
            .stroke(inactiveTube, style: StrokeStyle(lineWidth: 6, lineCap: .round))
        
        if isActive {
            // 2. Wide Ambient Neon Glow
            shape
                .stroke(color.opacity(0.35), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .blur(radius: 4)
            
            // 3. Solid Laser Core Beam
            shape
                .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            
            // 4. Flowing Energy Pulse (Animated Dash Particles)
            shape
                .stroke(
                    Color.white,
                    style: StrokeStyle(
                        lineWidth: 1.6,
                        lineCap: .round,
                        dash: [8, 16],
                        dashPhase: -phase
                    )
                )
                .shadow(color: color, radius: 4)
        } else if isWarning {
            // Amber Warning Pulse
            shape
                .stroke(
                    Color.Premium.champagneBronze.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [4, 6])
                )
        } else {
            // Inactive Dormant Line
            shape
                .stroke(
                    Color.primary.opacity(0.12),
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 8])
                )
        }
    }
    
    @ViewBuilder
    private func intakePort(at point: CGPoint, isActive: Bool, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(isActive ? color.opacity(0.2) : Color.primary.opacity(0.04))
                .frame(width: 14, height: 14)
            Circle()
                .stroke(isActive ? color : Color.primary.opacity(0.18), lineWidth: 1.5)
                .frame(width: 10, height: 10)
            if isActive {
                Circle()
                    .fill(Color.white)
                    .frame(width: 4, height: 4)
                    .shadow(color: color, radius: 3)
            }
        }
        .position(point)
    }
}

// MARK: - Gamified Watched Folder View
struct WatchedFolderView: View {
    @ObservedObject var viewModel: AppViewModel
    
    // Status Computations
    private var isVoiceMemosActive: Bool {
        viewModel.isVoiceMemosEnabled && viewModel.folderWatcher.isVoiceMemosDirectlyAccessible
    }
    
    private var isICloudActive: Bool {
        viewModel.folderWatcher.watchiCloudDrive && viewModel.folderWatcher.isICloudDriveAvailable
    }
    
    private var isCustomActive: Bool {
        viewModel.folderWatcher.watchCustomFolder && !viewModel.folderWatcher.customFolderURLs.isEmpty
    }
    
    private var isVoiceMemosFDAMissing: Bool {
        !viewModel.folderWatcher.isVoiceMemosDirectlyAccessible
    }
    
    private var activePipesCount: Int {
        (isVoiceMemosActive ? 1 : 0) + (isICloudActive ? 1 : 0) + (isCustomActive ? 1 : 0)
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // MARK: - Top Master Reactor & FDA Alert
                topControlHUD
                
                // MARK: - Tier 1: Three Input Pods
                HStack(spacing: 12) {
                    // Pod 1: Voice Memos
                    voiceMemosPod
                    
                    // Pod 2: iCloud Drive
                    iCloudPod
                    
                    // Pod 3: Custom Watched Folders
                    customFoldersPod
                }
                
                // MARK: - Tier 2: Animated Neon Conduits (Boru Hatları)
                NeonConduitCanvasView(
                    isVoiceMemosActive: isVoiceMemosActive,
                    isICloudActive: isICloudActive,
                    isCustomActive: isCustomActive,
                    isVoiceMemosFDAMissing: isVoiceMemosFDAMissing
                )
                .padding(.horizontal, 6)
                
                // MARK: - Tier 3: Output Reactor Terminal (Hedef Depolama)
                outputCollectorTerminal
                
                // MARK: - Tier 4: Watched Custom Folder Chips (if any added)
                if !viewModel.folderWatcher.customFolderURLs.isEmpty {
                    customFolderChipsTray
                }
            }
            .padding(18)
        }
        .navigationTitle(viewModel.t("section_watched_folder"))
        .onAppear {
            viewModel.checkFullDiskAccess()
        }
    }
    
    // MARK: - Top Control HUD
    private var topControlHUD: some View {
        VStack(spacing: 8) {
            // Full Disk Access Alert (Pulsing if needed)
            if !viewModel.fullDiskAccessStatus.isGranted {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color.Premium.champagneBronze)
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(viewModel.t("watched_fda_warning_title"))
                            .font(.system(size: 11.5, weight: .bold))
                        Text(viewModel.t("watched_fda_warning_desc"))
                            .font(.system(size: 10))
                            .foregroundStyle(Color.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.openFullDiskAccessSettings()
                    }) {
                        Text(viewModel.t("watched_open_settings"))
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
            }
            
            // Auto-Transcribe Master Switch
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(viewModel.folderWatcher.autoTranscribe ? Color(hex: "#00E676").opacity(0.2) : Color.primary.opacity(0.06))
                        .frame(width: 32, height: 32)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(viewModel.folderWatcher.autoTranscribe ? Color(hex: "#00E676") : Color.secondary)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(viewModel.t("watched_auto_transcribe_title"))
                            .font(.system(size: 12.5, weight: .bold))
                        
                        Text(viewModel.folderWatcher.autoTranscribe ? "OTOMATİK ÇEVİRİ AÇIK" : "ONAY BEKLEME MODU")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(viewModel.folderWatcher.autoTranscribe ? Color(hex: "#00E676") : Color.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill((viewModel.folderWatcher.autoTranscribe ? Color(hex: "#00E676") : Color.secondary).opacity(0.12)))
                    }
                    Text(viewModel.t("watched_auto_transcribe_desc"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $viewModel.folderWatcher.autoTranscribe)
                    .toggleStyle(.switch)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.035))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
    
    // MARK: - Pod 1: Voice Memos
    private var voiceMemosPod: some View {
        let accent = Color(hex: "#FFB300")
        return VStack(spacing: 8) {
            // Header Row: Icon & Status Dot
            HStack {
                ZStack {
                    Circle()
                        .fill(accent.opacity(isVoiceMemosActive ? 0.2 : 0.08))
                        .frame(width: 28, height: 28)
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(isVoiceMemosActive ? accent : Color.secondary)
                }
                
                Spacer()
                
                Circle()
                    .fill(isVoiceMemosActive ? accent : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
                    .shadow(color: isVoiceMemosActive ? accent : Color.clear, radius: 3)
            }
            
            // Title & Subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.t("watched_voicememos_title"))
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                Text("Apple Watch & iPhone")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 4)
            
            // Action / Toggle
            HStack {
                if !viewModel.folderWatcher.isVoiceMemosDirectlyAccessible {
                    Button(action: {
                        viewModel.openFullDiskAccessSettings()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8))
                            Text(viewModel.t("watched_fda_badge_needed"))
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .foregroundStyle(Color.Premium.champagneBronze)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.Premium.champagneBronze.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                    .help(viewModel.t("watched_fda_warning_desc"))
                } else {
                    Text(isVoiceMemosActive ? "Bağlı" : "Devre Dışı")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isVoiceMemosActive ? accent : Color.secondary)
                }
                
                Spacer()
                
                Toggle("", isOn: $viewModel.isVoiceMemosEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            
            // Conduit Connector Port (Visual Emitter)
            Circle()
                .fill(isVoiceMemosActive ? accent : Color.primary.opacity(0.1))
                .frame(width: 8, height: 8)
                .shadow(color: isVoiceMemosActive ? accent : Color.clear, radius: 4)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 125)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isVoiceMemosActive ? accent.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: isVoiceMemosActive ? accent.opacity(0.12) : Color.clear, radius: 8)
    }
    
    // MARK: - Pod 2: iCloud Drive
    private var iCloudPod: some View {
        let accent = Color(hex: "#00E5FF")
        return VStack(spacing: 8) {
            // Header Row: Icon & Status Dot
            HStack {
                ZStack {
                    Circle()
                        .fill(accent.opacity(isICloudActive ? 0.2 : 0.08))
                        .frame(width: 28, height: 28)
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(isICloudActive ? accent : Color.secondary)
                }
                
                Spacer()
                
                Circle()
                    .fill(isICloudActive ? accent : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
                    .shadow(color: isICloudActive ? accent : Color.clear, radius: 3)
            }
            
            // Title & Subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.t("watched_icloud_title"))
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                Text("Bulut & Dosyalar")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 4)
            
            // Action / Toggle
            HStack {
                Button(action: {
                    viewModel.openInFinder(path: FolderWatcher.iCloudRootDirectory.path)
                }) {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.secondary)
                .help(viewModel.t("action_open_finder"))
                
                Text(isICloudActive ? "Bağlı" : "Devre Dışı")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isICloudActive ? accent : Color.secondary)
                
                Spacer()
                
                if !viewModel.folderWatcher.isICloudTranskriptFolderReady {
                    Button(action: {
                        viewModel.setupICloudTranskriptFolderAndSetOutput()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 8.5))
                            Text(viewModel.t("watched_icloud_folder_setup_short_btn"))
                                .font(.system(size: 9.5, weight: .bold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.mini)
                }
                
                Toggle("", isOn: $viewModel.folderWatcher.watchiCloudDrive)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            
            // Conduit Connector Port (Visual Emitter)
            Circle()
                .fill(isICloudActive ? accent : Color.primary.opacity(0.1))
                .frame(width: 8, height: 8)
                .shadow(color: isICloudActive ? accent : Color.clear, radius: 4)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 125)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isICloudActive ? accent.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: isICloudActive ? accent.opacity(0.12) : Color.clear, radius: 8)
    }
    
    // MARK: - Pod 3: Custom Folders (Multi-folder)
    private var customFoldersPod: some View {
        let accent = Color(hex: "#D500F9")
        let count = viewModel.folderWatcher.customFolderURLs.count
        
        return VStack(spacing: 8) {
            // Header Row: Icon & Status Dot
            HStack {
                ZStack {
                    Circle()
                        .fill(accent.opacity(isCustomActive ? 0.2 : 0.08))
                        .frame(width: 28, height: 28)
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 13))
                        .foregroundStyle(isCustomActive ? accent : Color.secondary)
                }
                
                Spacer()
                
                Circle()
                    .fill(isCustomActive ? accent : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
                    .shadow(color: isCustomActive ? accent : Color.clear, radius: 3)
            }
            
            // Title & Subtitle
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.t("watched_custom_title"))
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
                
                Text(count == 0 ? "Klasör Ekle (+)" : "\(count) Klasör Seçili")
                    .font(.system(size: 9.5))
                    .foregroundStyle(count > 0 ? accent : Color.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer(minLength: 4)
            
            // Action / Toggle
            HStack(spacing: 6) {
                Button(action: {
                    viewModel.selectCustomWatchedFolder()
                }) {
                    HStack(spacing: 2) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                        Text("Ekle")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(accent.opacity(0.15)))
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
                .help("Yeni izlenecek klasör ekle")
                
                Spacer()
                
                Toggle("", isOn: Binding(
                    get: { viewModel.folderWatcher.watchCustomFolder && !viewModel.folderWatcher.customFolderURLs.isEmpty },
                    set: { newValue in
                        if newValue {
                            if !viewModel.folderWatcher.customFolderURLs.isEmpty {
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
                .controlSize(.mini)
            }
            
            // Conduit Connector Port (Visual Emitter)
            Circle()
                .fill(isCustomActive ? accent : Color.primary.opacity(0.1))
                .frame(width: 8, height: 8)
                .shadow(color: isCustomActive ? accent : Color.clear, radius: 4)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 125)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isCustomActive ? accent.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: isCustomActive ? accent.opacity(0.12) : Color.clear, radius: 8)
    }
    
    // MARK: - Output Reactor Collector Terminal (Hedef Depolama)
    private var outputCollectorTerminal: some View {
        VStack(spacing: 12) {
            // Reactor Core Glow Ring + Info
            HStack(spacing: 14) {
                ZStack {
                    // Multi-source Conic Reactor Glow
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                colors: [
                                    isVoiceMemosActive ? Color(hex: "#FFB300") : Color.primary.opacity(0.1),
                                    isICloudActive ? Color(hex: "#00E5FF") : Color.primary.opacity(0.1),
                                    isCustomActive ? Color(hex: "#D500F9") : Color.primary.opacity(0.1),
                                    isVoiceMemosActive ? Color(hex: "#FFB300") : Color.primary.opacity(0.1)
                                ],
                                center: .center
                            ),
                            lineWidth: 2.5
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: activePipesCount > 0 ? Color.cyan.opacity(0.3) : Color.clear, radius: 6)
                    
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(viewModel.t("watched_output_title"))
                            .font(.system(size: 13, weight: .bold))
                        
                        Text(viewModel.isCustomOutputDirectory ? viewModel.t("watched_output_custom_badge") : viewModel.t("watched_output_default_badge"))
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(viewModel.isCustomOutputDirectory ? Color(hex: "#00E5FF") : Color.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill((viewModel.isCustomOutputDirectory ? Color(hex: "#00E5FF") : Color.secondary).opacity(0.12)))
                    }
                    
                    Text(viewModel.outputDirectoryURL.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Spacer()
                
                // Destination Action Buttons
                HStack(spacing: 6) {
                    Button(action: {
                        viewModel.selectOutputDirectory()
                    }) {
                        Text(viewModel.t("watched_change_folder"))
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    
                    if viewModel.isCustomOutputDirectory {
                        Button(action: {
                            viewModel.resetOutputDirectory()
                        }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help(viewModel.t("watched_reset_folder"))
                    }
                    
                    Button(action: {
                        viewModel.openInFinder(path: viewModel.outputDirectoryURL.path)
                    }) {
                        Image(systemName: "folder")
                            .font(.system(size: 10.5))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(viewModel.t("action_open_finder"))
                }
            }
            
            // Missing Transkript Folder Prompt (If iCloud Folder not present)
            if !viewModel.folderWatcher.isICloudTranskriptFolderReady {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(hex: "#00E5FF"))
                    
                    Text(viewModel.t("watched_icloud_folder_missing_desc"))
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.secondary)
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.setupICloudTranskriptFolderAndSetOutput()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 10))
                            Text(viewModel.t("watched_icloud_folder_setup_btn"))
                                .font(.system(size: 10.5, weight: .bold))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(hex: "#00E5FF").opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            
            // Bottom HUD Status Bar
            HStack {
                HStack(spacing: 5) {
                    Circle()
                        .fill(activePipesCount > 0 ? Color(hex: "#00E676") : Color.secondary)
                        .frame(width: 6, height: 6)
                        .shadow(color: activePipesCount > 0 ? Color(hex: "#00E676") : Color.clear, radius: 3)
                    
                    Text(String(format: viewModel.t("watched_hud_sources_count"), activePipesCount))
                        .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(activePipesCount > 0 ? Color(hex: "#00E676") : Color.secondary)
                }
                
                Text("•")
                    .foregroundStyle(Color.secondary.opacity(0.4))
                
                Text(activePipesCount == 3 ? viewModel.t("watched_hud_all_active") : (activePipesCount > 0 ? viewModel.t("watched_hud_listening_active") : viewModel.t("watched_hud_waiting")))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.secondary)
                
                Spacer()
                
                if viewModel.isCloudDownloading {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text(viewModel.t("watched_cloud_downloading"))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(activePipesCount > 0 ? Color.cyan.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: activePipesCount > 0 ? Color.cyan.opacity(0.08) : Color.clear, radius: 10)
    }
    
    // MARK: - Watched Custom Folders Chips Tray
    private var customFolderChipsTray: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("İzlenen Özel Klasörler (\(viewModel.folderWatcher.customFolderURLs.count))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.secondary)
                
                Spacer()
                
                Button(action: {
                    viewModel.resetCustomWatchedFolder()
                }) {
                    Text(viewModel.t("watched_reset_folder"))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
            }
            
            FlowLayout(spacing: 6) {
                ForEach(viewModel.folderWatcher.customFolderURLs, id: \.path) { url in
                    HStack(spacing: 5) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(hex: "#D500F9"))
                        
                        Text(url.lastPathComponent)
                            .font(.system(size: 10, weight: .medium))
                        
                        Button(action: {
                            viewModel.removeCustomWatchedFolder(url)
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Klasörü izleme listesinden kaldır")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .help(url.path)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Lightweight Flow Layout for Chips
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var height: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxHeightInRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += maxHeightInRow + spacing
                maxHeightInRow = 0
            }
            maxHeightInRow = max(maxHeightInRow, size.height)
            x += size.width + spacing
        }
        height = y + maxHeightInRow
        return CGSize(width: width, height: max(height, 20))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var maxHeightInRow: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += maxHeightInRow + spacing
                maxHeightInRow = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            maxHeightInRow = max(maxHeightInRow, size.height)
            x += size.width + spacing
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
                        .fill(Color.cyan.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: "waveform.badge.magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.cyan)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(viewModel.t("watched_title"))
                        .font(.system(size: 14, weight: .bold))
                    Text("Otomatik Boru Akışı • Ses Algılama İstasyonu")
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
        .frame(width: 660, height: 560)
        .background(.ultraThinMaterial)
    }
}
