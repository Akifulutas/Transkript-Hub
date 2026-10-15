import SwiftUI
import AVFoundation
import TranskriptHubCore

public struct WaveformVisualizerView: View {
    @ObservedObject var player: AudioPlayerController
    public let waveformPoints: [WaveformPoint]
    
    @State private var isScrubbing: Bool = false
    @State private var scrubTime: Double = 0.0
    @State private var hoverLocation: CGPoint? = nil
    @State private var isHovering: Bool = false
    
    public init(player: AudioPlayerController, waveformPoints: [WaveformPoint] = []) {
        self.player = player
        self.waveformPoints = waveformPoints
    }
    
    private var effectiveDuration: Double {
        player.duration > 0 ? player.duration : 1.0
    }
    
    private var displayTime: Double {
        if isScrubbing {
            return scrubTime
        }
        return player.currentTime
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            // Interactive Metal-backed Waveform Canvas
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let progress = min(max(0.0, displayTime / effectiveDuration), 1.0)
                let playheadX = CGFloat(progress) * width
                
                ZStack(alignment: .topLeading) {
                    // Metal Canvas Waveform Rendering
                    Canvas { context, size in
                        let points = effectivePoints
                        guard !points.isEmpty else { return }
                        
                        let midY = size.height / 2.0
                        let maxBarHeight = size.height * 0.44
                        let count = points.count
                        let barPitch = size.width / CGFloat(count)
                        let barWidth = max(1.5, barPitch * 0.65)
                        
                        var playedPath = Path()
                        var unplayedPath = Path()
                        
                        for (i, pt) in points.enumerated() {
                            let x = CGFloat(i) * barPitch + (barPitch - barWidth) / 2
                            let amp = CGFloat(max(0.06, pt.max))
                            let barHeight = max(4.0, amp * maxBarHeight * 2.0)
                            let rect = CGRect(
                                x: x,
                                y: midY - barHeight / 2.0,
                                width: barWidth,
                                height: barHeight
                            )
                            let bar = Path(roundedRect: rect, cornerRadius: barWidth / 2.0)
                            
                            if (x + barWidth) <= playheadX {
                                playedPath.addPath(bar)
                            } else {
                                unplayedPath.addPath(bar)
                            }
                        }
                        
                        // Fill played region with vibrant Apple accent gradient
                        context.fill(
                            playedPath,
                            with: .linearGradient(
                                Gradient(colors: [Color.accentColor, Color.purple]),
                                startPoint: CGPoint(x: 0, y: 0),
                                endPoint: CGPoint(x: max(playheadX, 10), y: size.height)
                            )
                        )
                        
                        // Fill unplayed region with translucent primary
                        context.fill(
                            unplayedPath,
                            with: .color(Color.primary.opacity(0.18))
                        )
                        
                        // Playhead Indicator Line
                        var playheadPath = Path()
                        playheadPath.move(to: CGPoint(x: playheadX, y: 0))
                        playheadPath.addLine(to: CGPoint(x: playheadX, y: size.height))
                        context.stroke(
                            playheadPath,
                            with: .color(Color.white),
                            lineWidth: 2
                        )
                        
                        // Playhead Pill Nubs (Top & Bottom Voice Memos style)
                        let nubW: CGFloat = 8
                        let nubH: CGFloat = 4
                        let topNubRect = CGRect(x: playheadX - nubW / 2, y: 0, width: nubW, height: nubH)
                        let btmNubRect = CGRect(x: playheadX - nubW / 2, y: size.height - nubH, width: nubW, height: nubH)
                        context.fill(Path(roundedRect: topNubRect, cornerRadius: 2), with: .color(.white))
                        context.fill(Path(roundedRect: btmNubRect, cornerRadius: 2), with: .color(.white))
                    }
                    .frame(width: width, height: height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isScrubbing {
                                    player.beginScrubbing()
                                    isScrubbing = true
                                }
                                let ratio = min(max(0.0, value.location.x / width), 1.0)
                                scrubTime = ratio * effectiveDuration
                                player.seek(to: scrubTime)
                            }
                            .onEnded { value in
                                let ratio = min(max(0.0, value.location.x / width), 1.0)
                                let targetTime = ratio * effectiveDuration
                                player.seek(to: targetTime)
                                isScrubbing = false
                                player.endScrubbing(resumePlayback: true)
                            }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            isHovering = true
                            hoverLocation = loc
                        case .ended:
                            isHovering = false
                            hoverLocation = nil
                        }
                    }
                    
                    // Hover Tooltip Pill
                    if isHovering, let hover = hoverLocation {
                        let hoverRatio = min(max(0.0, hover.x / width), 1.0)
                        let hoverTime = hoverRatio * effectiveDuration
                        let tooltipX = min(max(35, hover.x), width - 35)
                        
                        Text(AudioPlayerController.formatTimeWithMilliseconds(hoverTime))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.black.opacity(0.75))
                            )
                            .position(x: tooltipX, y: 12)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: 72)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .liquidGlass(cornerRadius: 12, glowColor: .white.opacity(0.25), material: .ultraThinMaterial)
            
            // Transport Controls Deck
            HStack(spacing: 12) {
                // Current Time Monospace
                Text(AudioPlayerController.formatTimeWithMilliseconds(displayTime))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(minWidth: 64, alignment: .leading)
                
                Spacer()
                
                // Transport Playback Buttons
                HStack(spacing: 14) {
                    // Jump -5s
                    Button(action: {
                        player.seek(to: max(0.0, player.currentTime - 5.0))
                    }) {
                        Image(systemName: "gobackward.5")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.primary)
                    .help("5 saniye geri (⌘←)")
                    
                    // Circular Play / Pause
                    Button(action: {
                        player.togglePlayPause()
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor)
                                .frame(width: 32, height: 32)
                                .shadow(color: Color.accentColor.opacity(0.35), radius: 6, x: 0, y: 2)
                            
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .offset(x: player.isPlaying ? 0 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Oynat / Duraklat (Space)")
                    
                    // Jump +5s
                    Button(action: {
                        player.seek(to: min(player.duration, player.currentTime + 5.0))
                    }) {
                        Image(systemName: "goforward.5")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.primary)
                    .help("5 saniye ileri (⌘→)")
                }
                
                Spacer()
                
                // Playback Speed Selector
                Menu {
                    ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                        Button(action: {
                            player.setPlaybackRate(Float(rate))
                        }) {
                            HStack {
                                Text("\(rate, specifier: "%.2f")x")
                                if abs(Double(player.playbackRate) - rate) < 0.05 {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text("\(player.playbackRate, specifier: "%.2f")x")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .liquidGlassCapsule(glowColor: .white.opacity(0.3), material: .ultraThinMaterial)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                
                // Total Duration Monospace
                Text(AudioPlayerController.formatTime(player.duration))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 44, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
    
    /// Fallback points if none provided, generating a clean ambient wave pattern
    private var effectivePoints: [WaveformPoint] {
        if !waveformPoints.isEmpty {
            return waveformPoints
        }
        // Synthetic resting ambient bars (100 bars)
        return (0..<100).map { i in
            let factor = sin(Double(i) * 0.1) * cos(Double(i) * 0.05)
            let amp = Float(abs(factor) * 0.35 + 0.1)
            return WaveformPoint(min: 0.0, max: min(1.0, amp))
        }
    }
}
