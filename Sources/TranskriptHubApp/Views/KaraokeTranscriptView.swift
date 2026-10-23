import SwiftUI
import AppKit
import TranskriptHubCore

public struct KaraokeTranscriptView: View {
    public let segments: [Segment]
    @ObservedObject var player: AudioPlayerController
    public var fontSize: CGFloat
    public var onSpeakerRenamed: ((String, String) -> Void)? = nil
    public var onSegmentTextEdited: ((Int, String) -> Void)? = nil
    
    @State private var isAutoScrollPaused: Bool = false
    @State private var lastScrolledSegmentId: String? = nil
    
    public init(
        segments: [Segment],
        player: AudioPlayerController,
        fontSize: CGFloat = 14,
        onSpeakerRenamed: ((String, String) -> Void)? = nil,
        onSegmentTextEdited: ((Int, String) -> Void)? = nil
    ) {
        self.segments = segments
        self.player = player
        self.fontSize = fontSize
        self.onSpeakerRenamed = onSpeakerRenamed
        self.onSegmentTextEdited = onSegmentTextEdited
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
                                segmentIndex: index,
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
                                },
                                onSegmentClicked: { seg in
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        isAutoScrollPaused = false
                                    }
                                    player.seek(to: seg.start)
                                    if !player.isPlaying {
                                        player.play()
                                    }
                                    lastScrolledSegmentId = seg.id
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(seg.id, anchor: .center)
                                    }
                                },
                                onSpeakerRenamed: onSpeakerRenamed,
                                onSegmentTextEdited: onSegmentTextEdited
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
                            Text(L10n.tr("karaoke_return_to_play"))
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
    let segmentIndex: Int
    let currentTime: Double
    let isActiveSegment: Bool
    let fontSize: CGFloat
    let onWordClicked: (Word) -> Void
    var onSegmentClicked: ((Segment) -> Void)? = nil
    var onSpeakerRenamed: ((String, String) -> Void)? = nil
    var onSegmentTextEdited: ((Int, String) -> Void)? = nil
    
    @State private var isRenamingSpeaker: Bool = false
    @State private var newSpeakerName: String = ""
    @State private var isEditingText: Bool = false
    @State private var editedText: String = ""
    @State private var isHovered: Bool = false
    
    private var higColor: Color {
        guard let spk = segment.speaker, !spk.isEmpty else { return Color.Premium.cashmereViolet }
        let badge = AppleHIGPalette.color(for: spk)
        switch badge.index {
        case 0: return Color.Premium.slateAzure
        case 1: return Color.Premium.cashmereViolet
        case 2: return Color.Premium.champagneBronze
        case 3: return Color.Premium.emeraldMineral
        case 4: return Color.Premium.crimsonVelvet
        case 5: return Color.Premium.obsidianTeal
        case 6: return Color.Premium.sapphirePro
        case 7: return Color.Premium.champagneBronze
        default: return .accentColor
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Segment Metadata Header (Timestamp, Speaker Badge & Edit Action)
            HStack(spacing: 8) {
                // Time Range Button (Click to jump to segment start)
                Button(action: {
                    onSegmentClicked?(segment)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isActiveSegment ? "speaker.wave.2.fill" : "play.circle.fill")
                            .font(.system(size: 9))
                            .opacity(isHovered || isActiveSegment ? 1.0 : 0.6)
                        Text("\(AudioPlayerController.formatTime(segment.start)) – \(AudioPlayerController.formatTime(segment.end))")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(isActiveSegment ? Color.accentColor : Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule()
                            .fill(isActiveSegment ? Color.accentColor.opacity(0.12) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
                    )
                }
                .buttonStyle(.plain)
                .help(L10n.tr("karaoke_play_from_segment_help"))
                
                // Interactive Speaker Badge
                if let speaker = segment.speaker, !speaker.isEmpty {
                    Button(action: {
                        newSpeakerName = speaker
                        isRenamingSpeaker = true
                    }) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(higColor)
                                .frame(width: 5, height: 5)
                            Text(speaker)
                                .font(.system(size: 9, weight: .bold))
                            Image(systemName: "pencil")
                                .font(.system(size: 7))
                                .opacity(0.6)
                        }
                        .foregroundStyle(higColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(higColor.opacity(0.12)))
                        .overlay(Capsule().stroke(higColor.opacity(0.25), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("karaoke_change_speaker_help"))
                    .popover(isPresented: $isRenamingSpeaker) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.tr("karaoke_rename_speaker_title"))
                                .font(.system(size: 11, weight: .bold))
                            
                            TextField(L10n.tr("karaoke_speaker_placeholder"), text: $newSpeakerName)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 190)
                                .onSubmit {
                                    commitSpeakerRename()
                                }
                            
                            HStack {
                                Button(L10n.tr("action_cancel")) { isRenamingSpeaker = false }
                                    .controlSize(.small)
                                Spacer()
                                Button(L10n.tr("karaoke_update_all")) {
                                    commitSpeakerRename()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(newSpeakerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(12)
                    }
                }
                
                Spacer()
                
                // Inline Edit Segment Button (Visible on hover or active)
                if !isEditingText && (isHovered || isActiveSegment) {
                    Button(action: {
                        editedText = segment.text
                        isEditingText = true
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: "pencil.line")
                                .font(.system(size: 9))
                            Text(L10n.tr("karaoke_edit_segment"))
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.primary.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.tr("karaoke_edit_segment_help"))
                    .transition(.opacity)
                }
            }
            
            // Words Flow or Inline Text Editor
            if isEditingText {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(L10n.tr("karaoke_segment_text_placeholder"), text: $editedText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: fontSize))
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)
                        )
                    
                    HStack {
                        Button(L10n.tr("action_cancel")) {
                            isEditingText = false
                        }
                        .controlSize(.small)
                        
                        Spacer()
                        
                        Button(L10n.tr("karaoke_save_edit")) {
                            let trimmed = editedText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                onSegmentTextEdited?(segmentIndex, trimmed)
                            }
                            isEditingText = false
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.top, 4)
            } else {
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
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isActiveSegment ? Color.accentColor.opacity(0.06) : (isHovered ? Color.primary.opacity(0.02) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isActiveSegment ? Color.accentColor.opacity(0.25) : (isHovered ? Color.primary.opacity(0.1) : Color.primary.opacity(0.04)),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            guard !isEditingText && !isRenamingSpeaker else { return }
            onSegmentClicked?(segment)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    private func commitSpeakerRename() {
        let trimmed = newSpeakerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let current = segment.speaker, current != trimmed else {
            isRenamingSpeaker = false
            return
        }
        onSpeakerRenamed?(current, trimmed)
        isRenamingSpeaker = false
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

