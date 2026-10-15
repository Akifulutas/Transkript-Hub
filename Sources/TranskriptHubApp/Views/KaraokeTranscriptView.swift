import SwiftUI
import AppKit
import TranskriptHubCore

public struct KaraokeTranscriptView: View {
    public let segments: [Segment]
    @ObservedObject var player: AudioPlayerController
    public var fontSize: CGFloat
    
    @State private var isAutoScrollPaused: Bool = false
    @State private var lastScrolledSegmentId: String? = nil
    
    public init(
        segments: [Segment],
        player: AudioPlayerController,
        fontSize: CGFloat = 14
    ) {
        self.segments = segments
        self.player = player
        self.fontSize = fontSize
    }
    
    private var activeSegmentIndex: Int? {
        let time = player.currentTime
        return segments.firstIndex { time >= $0.start && time <= $0.end }
    }
    
    public var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                            SegmentRowView(
                                segment: segment,
                                currentTime: player.currentTime,
                                isActiveSegment: index == activeSegmentIndex,
                                fontSize: fontSize,
                                onWordClicked: { word in
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        isAutoScrollPaused = false
                                    }
                                    player.seek(to: word.start)
                                    if !player.isPlaying {
                                        player.play()
                                    }
                                    if let idx = segments.firstIndex(where: { word.start >= $0.start && word.start <= $0.end }) {
                                        let segId = segments[idx].id
                                        lastScrolledSegmentId = segId
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            proxy.scrollTo(segId, anchor: .center)
                                        }
                                    }
                                }
                            )
                            .id(segment.id)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }
                .background(
                    ScrollEventDetector {
                        if player.isPlaying && !isAutoScrollPaused {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isAutoScrollPaused = true
                            }
                        }
                    }
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5).onChanged { _ in
                        if player.isPlaying && !isAutoScrollPaused {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isAutoScrollPaused = true
                            }
                        }
                    }
                )
                .onChange(of: activeSegmentIndex) { _, newIndex in
                    guard player.isPlaying, !isAutoScrollPaused else { return }
                    guard let newIndex = newIndex, newIndex < segments.count else { return }
                    let segmentId = segments[newIndex].id
                    guard segmentId != lastScrolledSegmentId else { return }
                    lastScrolledSegmentId = segmentId
                    withAnimation(.easeInOut(duration: 0.35)) {
                        proxy.scrollTo(segmentId, anchor: .center)
                    }
                }
                .onChange(of: segments) { _, _ in
                    isAutoScrollPaused = false
                    lastScrolledSegmentId = nil
                }
                
                // Floating "Oynatılan Yere Dön (Resume Auto-Scroll)" Pill
                if isAutoScrollPaused && player.isPlaying {
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            isAutoScrollPaused = false
                        }
                        if let activeIndex = activeSegmentIndex, activeIndex < segments.count {
                            let segId = segments[activeIndex].id
                            lastScrolledSegmentId = segId
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                proxy.scrollTo(segId, anchor: .center)
                            }
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.to.line.compact")
                                .font(.system(size: 11, weight: .bold))
                            Text("Oynatılan Yere Dön")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .liquidGlassCapsule(glowColor: .accentColor.opacity(0.6), material: .ultraThinMaterial)
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }
}

// MARK: - Segment Row View

private struct SegmentRowView: View {
    let segment: Segment
    let currentTime: Double
    let isActiveSegment: Bool
    let fontSize: CGFloat
    let onWordClicked: (Word) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Segment Metadata Header (Timestamp & Speaker Badge)
            HStack(spacing: 8) {
                // Time Range
                Text("\(AudioPlayerController.formatTime(segment.start)) – \(AudioPlayerController.formatTime(segment.end))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(isActiveSegment ? .accentColor : .secondary)
                
                // Speaker Badge if present
                if let speaker = segment.speaker, !speaker.isEmpty {
                    Text(speaker)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.purple.opacity(0.15)))
                }
                
                Spacer()
            }
            
            // Words Flow
            let effectiveWords = segment.words.isEmpty ? Segment.interpolateWords(for: segment.text, start: segment.start, end: segment.end) : segment.words
            
            WordFlowLayout(spacing: 4, lineSpacing: 6) {
                ForEach(effectiveWords) { word in
                    WordTokenView(
                        word: word,
                        currentTime: currentTime,
                        isActiveSegment: isActiveSegment,
                        fontSize: fontSize,
                        onClick: { onWordClicked(word) }
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActiveSegment ? Color.accentColor.opacity(0.06) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isActiveSegment ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.04),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Word Token View

private struct WordTokenView: View {
    let word: Word
    let currentTime: Double
    let isActiveSegment: Bool
    let fontSize: CGFloat
    let onClick: () -> Void
    
    @State private var isHovered: Bool = false
    
    private var isWordActive: Bool {
        currentTime >= word.start && currentTime <= word.end
    }
    
    private var isPastWord: Bool {
        currentTime > word.end
    }
    
    var body: some View {
        Button(action: onClick) {
            Text(word.text)
                .font(.system(size: fontSize, weight: isWordActive ? .bold : .regular))
                .foregroundColor(textColor)
                .padding(.horizontal, isWordActive ? 5 : 3)
                .padding(.vertical, isWordActive ? 3 : 1)
                .background(
                    Group {
                        if isWordActive {
                            Capsule()
                                .fill(Color.accentColor.opacity(0.22))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                                )
                                .shadow(color: Color.accentColor.opacity(0.3), radius: 4, x: 0, y: 1)
                        } else if isHovered {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                        } else {
                            Color.clear
                        }
                    }
                )
                .scaleEffect(isWordActive ? 1.05 : 1.0)
                .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isWordActive)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
    
    private var textColor: Color {
        if isWordActive {
            return .accentColor
        } else if isPastWord {
            return .primary.opacity(0.90)
        } else {
            return .secondary.opacity(0.65)
        }
    }
}

// MARK: - SwiftUI Flow Layout

public struct WordFlowLayout: Layout {
    public var spacing: CGFloat
    public var lineSpacing: CGFloat
    
    public init(spacing: CGFloat = 4, lineSpacing: CGFloat = 6) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }
    
    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var maxHeightInLine: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += maxHeightInLine + lineSpacing
                maxHeightInLine = 0
            }
            currentX += size.width + spacing
            maxHeightInLine = max(maxHeightInLine, size.height)
        }
        height = currentY + maxHeightInLine
        return CGSize(width: width, height: height)
    }
    
    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var maxHeightInLine: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += maxHeightInLine + lineSpacing
                maxHeightInLine = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            maxHeightInLine = max(maxHeightInLine, size.height)
        }
    }
}

// MARK: - Native AppKit Scroll Event Detector

private struct ScrollEventDetector: NSViewRepresentable {
    let onUserScroll: () -> Void
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onUserScroll: onUserScroll)
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = ScrollEventView()
        view.coordinator = context.coordinator
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onUserScroll = onUserScroll
    }
    
    @MainActor
    final class Coordinator {
        var onUserScroll: () -> Void
        init(onUserScroll: @escaping () -> Void) {
            self.onUserScroll = onUserScroll
        }
    }
    
    @MainActor
    private final class ScrollEventView: NSView {
        weak var coordinator: Coordinator?
        private var monitor: Any?
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
        
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil {
                stopMonitoring()
            }
        }
        
        private func startMonitoring() {
            stopMonitoring()
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDragged]) { [weak self] event in
                guard let self = self, let window = self.window, event.window == window else { return event }
                let location = self.convert(event.locationInWindow, from: nil)
                if self.bounds.contains(location) {
                    if event.type == .scrollWheel {
                        if abs(event.scrollingDeltaY) > 1.0 || abs(event.scrollingDeltaX) > 1.0 || abs(event.deltaY) > 0.1 {
                            self.coordinator?.onUserScroll()
                        }
                    } else if event.type == .leftMouseDragged {
                        self.coordinator?.onUserScroll()
                    }
                }
                return event
            }
        }
        
        private func stopMonitoring() {
            if let monitor = monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}

