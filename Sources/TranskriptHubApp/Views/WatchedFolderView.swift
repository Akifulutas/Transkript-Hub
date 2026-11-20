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

// MARK: - Custom Folder Neon Palette
enum CustomFolderNeonPalette {
    static let colors: [Color] = [
        Color(hex: "#D500F9"), // Electric Purple
        Color(hex: "#00E676"), // Emerald Neon
        Color(hex: "#FF4081"), // Magenta Rose
        Color(hex: "#3D5AFE"), // Indigo Laser
        Color(hex: "#FF6D00"), // Solar Orange
        Color(hex: "#1DE9B6"), // Mint Teal
        Color(hex: "#FFEA00"), // Cyber Yellow
        Color(hex: "#FF1744")  // Crimson Neon
    ]
    
    static func color(for index: Int) -> Color {
        colors[abs(index) % colors.count]
    }
}

// MARK: - Interactive Neon Pipeline Conduit Canvas (Multi-Branch Tree)
struct NeonConduitCanvasView: View {
    let isVoiceMemosActive: Bool
    let isICloudActive: Bool
    let isCustomActive: Bool
    let customFoldersCount: Int
    let isVoiceMemosFDAMissing: Bool
    
    // Base Neon Color Palette
    private let amberNeon = Color(hex: "#FFB300")
    private let cyanNeon = Color(hex: "#00E5FF")
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
                
                // Bottom Collector Intake Valves
                let p1End = CGPoint(x: w * 0.42, y: h)
                let p2End = CGPoint(x: w * 0.50, y: h)
                
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
                    intakePort(at: p1End, isActive: isVoiceMemosActive, color: amberNeon)
                    
                    // Pipe 2: iCloud Drive -> Collector
                    singlePipe(
                        start: p2Start,
                        end: p2End,
                        isActive: isICloudActive,
                        isWarning: false,
                        color: cyanNeon,
                        phase: phase
                    )
                    intakePort(at: p2End, isActive: isICloudActive, color: cyanNeon)
                    
                    // Pipe 3+: Multi-Branch Tree for Custom Folders
                    // ONLY visible when the 3rd option is active and has at least 1 folder!
                    if isCustomActive && customFoldersCount > 0 {
                        ForEach(0..<customFoldersCount, id: \.self) { index in
                            let branchColor = CustomFolderNeonPalette.color(for: index)
                            let startPoint = customBranchStart(index: index, count: customFoldersCount, width: w)
                            let endPoint = customBranchEnd(index: index, count: customFoldersCount, width: w, height: h)
                            let branchPhase = (phase + CGFloat(index) * 6.0).truncatingRemainder(dividingBy: 36)
                            
                            singlePipe(
                                start: startPoint,
                                end: endPoint,
                                isActive: true,
                                isWarning: false,
                                color: branchColor,
                                phase: branchPhase
                            )
                            intakePort(at: endPoint, isActive: true, color: branchColor)
                        }
                    }
                }
            }
        }
        .frame(height: 86)
    }
    
    /// Distributes emitter start points across the bottom of the 3rd card so each folder forms a distinct tree branch.
    private func customBranchStart(index: Int, count: Int, width: CGFloat) -> CGPoint {
        guard count > 1 else {
            return CGPoint(x: width * 0.83, y: 0)
        }
        let span: CGFloat = min(0.18, CGFloat(count - 1) * 0.045)
        let left = 0.83 - span * 0.5
        let step = span / CGFloat(max(1, count - 1))
        return CGPoint(x: width * (left + CGFloat(index) * step), y: 0)
    }
    
    /// Distributes intake ports on the collector terminal for each custom folder branch.
    private func customBranchEnd(index: Int, count: Int, width: CGFloat, height: CGFloat) -> CGPoint {
        guard count > 1 else {
            return CGPoint(x: width * 0.58, y: height)
        }
        let baseLeft: CGFloat = 0.56
        let maxRight: CGFloat = min(0.76, baseLeft + CGFloat(count - 1) * 0.04)
        let step = (maxRight - baseLeft) / CGFloat(max(1, count - 1))
        return CGPoint(x: width * (baseLeft + CGFloat(index) * step), y: height)
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
        
        // 1. Dark Conduit Tunnel
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
    
    private var activeCustomBranchesCount: Int {
        isCustomActive ? viewModel.folderWatcher.customFolderURLs.count : 0
    }
    
    private var activePipesCount: Int {
        (isVoiceMemosActive ? 1 : 0) + (isICloudActive ? 1 : 0) + activeCustomBranchesCount
    }
    
    private var totalPossiblePipesCount: Int {
        2 + max(1, viewModel.folderWatcher.customFolderURLs.count)
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
                    
                    // Pod 3: Custom Watched Folders (+ Button & Multi-Tree Card)
                    customFoldersPod
                }
                
                // MARK: - Tier 2: Animated Neon Conduits (Multi-Branch Tree)
                NeonConduitCanvasView(
                    isVoiceMemosActive: isVoiceMemosActive,
                    isICloudActive: isICloudActive,
                    isCustomActive: isCustomActive,
                    customFoldersCount: viewModel.folderWatcher.customFolderURLs.count,
                    isVoiceMemosFDAMissing: isVoiceMemosFDAMissing
                )
                .padding(.horizontal, 6)
                
                // MARK: - Tier 3: Output Reactor Terminal (Kayıt Klasörü)
                outputCollectorTerminal
                
                // MARK: - Tier 4: Watched Custom Folder Tree Nodes (when active)
                if isCustomActive && !viewModel.folderWatcher.customFolderURLs.isEmpty {
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
    
    // MARK: - Pod 3: Custom Folders (+ Plus Card when empty, Multi-Branch Tree Card when populated)
    private var customFoldersPod: some View {
        let accent = Color(hex: "#D500F9")
        let urls = viewModel.folderWatcher.customFolderURLs
        let count = urls.count
        
        return Group {
            if count == 0 {
                // Prominent Plus (+) Button Card when no custom folders are added yet
                Button(action: {
                    viewModel.selectCustomWatchedFolder()
                }) {
                    VStack(spacing: 8) {
                        Spacer(minLength: 4)
                        
                        ZStack {
                            Circle()
                                .fill(accent.opacity(0.14))
                                .frame(width: 38, height: 38)
                            Circle()
                                .strokeBorder(accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                                .frame(width: 38, height: 38)
                            Image(systemName: "plus")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(accent)
                        }
                        
                        VStack(spacing: 2) {
                            Text(viewModel.t("watched_custom_title"))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.primary)
                            Text("Klasör Ekle (+)")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(Color.secondary)
                        }
                        
                        Spacer(minLength: 4)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 125)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.025))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    )
                }
                .buttonStyle(.plain)
                .help("Yeni izlenecek klasör ekle")
            } else {
                // Active Multi-Folder Pod with top-right "+ Ekle" button and colored emitter dots per folder
                VStack(spacing: 8) {
                    // Header Row: Icon & Top-Right "+ Ekle" Button
                    HStack {
                        ZStack {
                            Circle()
                                .fill(accent.opacity(isCustomActive ? 0.2 : 0.08))
                                .frame(width: 28, height: 28)
                            Image(systemName: "folder.fill.badge.plus")
                                .font(.system(size: 13))
                                .foregroundStyle(isCustomActive ? accent : Color.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            viewModel.selectCustomWatchedFolder()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9.5, weight: .bold))
                                Text("Ekle")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Capsule().fill(accent.opacity(0.18)))
                            .foregroundStyle(accent)
                        }
                        .buttonStyle(.plain)
                        .help("Yeni klasör ekle (+)")
                    }
                    
                    // Title & Subtitle
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.t("watched_custom_title"))
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                        
                        Text("\(count) Klasör • Ağaç Akışı")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(isCustomActive ? accent : Color.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Spacer(minLength: 4)
                    
                    // Status Text & Toggle (Matches Voice Memos & iCloud Pods)
                    HStack(spacing: 6) {
                        Text(isCustomActive ? "Bağlı" : "Devre Dışı")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isCustomActive ? accent : Color.secondary)
                        
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
                    
                    // Multi-color Conduit Connector Ports (1 emitter dot per folder when active; hidden when off)
                    if isCustomActive {
                        HStack(spacing: 6) {
                            ForEach(Array(urls.enumerated()), id: \.element.path) { index, _ in
                                let c = CustomFolderNeonPalette.color(for: index)
                                Circle()
                                    .fill(c)
                                    .frame(width: 7, height: 7)
                                    .shadow(color: c, radius: 4)
                            }
                        }
                        .padding(.top, 2)
                    } else {
                        Spacer()
                            .frame(height: 10)
                    }
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
        }
    }
    
    // MARK: - Output Reactor Collector Terminal (Kayıt Klasörü)
    private var outputCollectorTerminal: some View {
        VStack(spacing: 12) {
            // Reactor Core Glow Ring + Info
            HStack(spacing: 14) {
                ZStack {
                    // Multi-source Conic Reactor Glow
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                colors: reactorGradientColors,
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
                    Text(viewModel.t("watched_output_title"))
                        .font(.system(size: 13.5, weight: .bold))
                    
                    Text(viewModel.t("watched_output_title"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
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
                    
                    Text("\(activePipesCount)/\(totalPossiblePipesCount) KAYNAK AKTİF")
                        .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                        .foregroundStyle(activePipesCount > 0 ? Color(hex: "#00E676") : Color.secondary)
                }
                
                Text("•")
                    .foregroundStyle(Color.secondary.opacity(0.4))
                
                Text(activePipesCount == totalPossiblePipesCount ? viewModel.t("watched_hud_all_active") : (activePipesCount > 0 ? viewModel.t("watched_hud_listening_active") : viewModel.t("watched_hud_waiting")))
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
    
    private var reactorGradientColors: [Color] {
        var colors: [Color] = [
            isVoiceMemosActive ? Color(hex: "#FFB300") : Color.primary.opacity(0.1),
            isICloudActive ? Color(hex: "#00E5FF") : Color.primary.opacity(0.1)
        ]
        if isCustomActive {
            for idx in viewModel.folderWatcher.customFolderURLs.indices {
                colors.append(CustomFolderNeonPalette.color(for: idx))
            }
        } else {
            colors.append(Color.primary.opacity(0.1))
        }
        colors.append(colors.first ?? Color.primary.opacity(0.1))
        return colors
    }
    
    // MARK: - Watched Custom Folders Chips Tray (Color-Matched to Tree Branches)
    private var customFolderChipsTray: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("İzlenen Özel Klasör Ağacı (\(viewModel.folderWatcher.customFolderURLs.count))")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.secondary)
                
                Spacer()
                
                Button(action: {
                    viewModel.selectCustomWatchedFolder()
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 10))
                        Text("Klasör Ekle")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(Color(hex: "#D500F9"))
                }
                .buttonStyle(.plain)
                
                Text("•")
                    .foregroundStyle(Color.secondary.opacity(0.4))
                
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
                ForEach(Array(viewModel.folderWatcher.customFolderURLs.enumerated()), id: \.element.path) { index, url in
                    let branchColor = CustomFolderNeonPalette.color(for: index)
                    HStack(spacing: 6) {
                        Circle()
                            .fill(branchColor)
                            .frame(width: 7, height: 7)
                            .shadow(color: branchColor, radius: 3)
                        
                        Image(systemName: "folder.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(branchColor)
                        
                        Text(url.lastPathComponent)
                            .font(.system(size: 10.5, weight: .semibold))
                        
                        Button(action: {
                            viewModel.removeCustomWatchedFolder(url)
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Klasörü izleme ağacından kaldır")
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(branchColor.opacity(0.10))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(branchColor.opacity(0.35), lineWidth: 0.8)
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
