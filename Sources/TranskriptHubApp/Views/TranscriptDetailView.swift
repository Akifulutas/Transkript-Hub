import SwiftUI
import AppKit
import TranskriptHubCore

public struct TranscriptDetailView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var searchInText: String = ""
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    var activeItem: QueueItem? {
        viewModel.selectedItem
    }
    
    var activeHistoryItem: HistoryItem? {
        viewModel.selectedHistoryItem
    }
    
    public var body: some View {
        Group {
            if viewModel.showCombinedSessionTranscript {
                combinedSessionView
            } else if let item = activeItem {
                contentForItem(item)
            } else if let history = activeHistoryItem {
                contentForHistory(history)
            } else if viewModel.selectedItemIDs.count > 1 {
                combinedSessionView
            } else {
                studioWelcomeView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
    
    // MARK: - Queue Item View
    @ViewBuilder
    private func contentForItem(_ item: QueueItem) -> some View {
        let transcript = effectiveTranscript(for: item)
        VStack(spacing: 0) {
            // Liquid Glass Inspector Header
            inspectorHeader(
                title: item.title,
                subtitle: item.subtitle,
                duration: item.durationSec,
                transcript: transcript,
                outputURL: item.outputURL,
                browserURL: item.canonicalURL,
                sourceAudioURL: item.effectiveAudioURL
            )
            
            Divider()
            
            // Body: Processing Card or Full Transcript
            if item.state == .transcribing {
                if let text = transcript, !text.isEmpty {
                    VStack(spacing: 0) {
                        liveTranscriptionBanner(item: item)
                        transcriptReader(text: text, isLive: true)
                    }
                } else {
                    activeProcessingCard(title: item.title, state: item.state)
                }
            } else if item.state == .fetching {
                activeProcessingCard(title: item.title, state: item.state)
            } else if let text = transcript, !text.isEmpty {
                VStack(spacing: 0) {
                    // 1. Interactive Audio Waveform Visualizer
                    WaveformVisualizerView(
                        player: viewModel.audioPlayer,
                        waveformPoints: item.waveformPoints ?? viewModel.activeWaveformPoints
                    )
                    
                    Divider()
                    
                    // 2. Transcript Content (Karaoke / Plain Text)
                    if viewModel.isKaraokeMode {
                        let effectiveSegments: [Segment] = viewModel.segments(for: item)
                        KaraokeTranscriptView(
                            segments: effectiveSegments,
                            player: viewModel.audioPlayer,
                            fontSize: CGFloat(viewModel.transcriptFontSize),
                            onSpeakerRenamed: { oldName, newName in
                                Task {
                                    await viewModel.renameSpeaker(in: item, from: oldName, to: newName)
                                }
                            },
                            onSegmentTextEdited: { segIdx, newText in
                                Task {
                                    await viewModel.updateSegmentText(in: item, segmentIndex: segIdx, newText: newText)
                                }
                            }
                        )
                    } else {
                        transcriptReader(text: text)
                    }
                }
                .task(id: item.id) {
                    await viewModel.loadAudio(for: item)
                }
            } else if item.state == .failed {
                failedStateView(item: item)
            } else {
                readyToTranscribeView(title: item.title)
            }
        }
    }
    
    private func effectiveTranscript(for item: QueueItem) -> String? {
        if let t = item.transcript, !t.isEmpty {
            return t
        }
        if let out = item.outputURL, let diskContent = try? String(contentsOf: out, encoding: .utf8), !diskContent.isEmpty {
            return diskContent
        }
        let candidate = viewModel.outputWriter.defaultOutputDirectory.appendingPathComponent("\(item.title).txt")
        if let diskContent = try? String(contentsOf: candidate, encoding: .utf8), !diskContent.isEmpty {
            return diskContent
        }
        return nil
    }
    
    // MARK: - History Item View
    @ViewBuilder
    private func contentForHistory(_ history: HistoryItem) -> some View {
        let content = (try? String(contentsOfFile: history.outputPath, encoding: .utf8)) ?? history.snippet
        let url = URL(fileURLWithPath: history.outputPath)
        let fileExists = FileManager.default.fileExists(atPath: history.outputPath)
        
        VStack(spacing: 0) {
            inspectorHeader(
                title: history.title,
                subtitle: String(format: viewModel.t("detail_archive_subtitle"), history.outputPath),
                duration: nil,
                transcript: content.isEmpty ? nil : content,
                outputURL: fileExists ? url : nil,
                browserURL: nil
            )
            
            Divider()
            
            if fileExists && !content.isEmpty {
                VStack(spacing: 0) {
                    if viewModel.audioPlayer.duration > 0 || viewModel.audioPlayer.currentURL != nil {
                        WaveformVisualizerView(
                            player: viewModel.audioPlayer,
                            waveformPoints: viewModel.activeWaveformPoints
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial.opacity(0.4))
                        
                        Divider()
                    }
                    
                    if viewModel.isKaraokeMode {
                        KaraokeTranscriptView(
                            segments: viewModel.segments(for: history, text: content),
                            player: viewModel.audioPlayer,
                            fontSize: CGFloat(viewModel.transcriptFontSize)
                        )
                    } else {
                        transcriptReader(text: content)
                    }
                }
                .task(id: history.id) {
                    await viewModel.loadAudio(for: history)
                }
            } else {
                missingHistoryFileView(history: history)
            }
        }
    }
    
    // MARK: - Missing History File View
    private func missingHistoryFileView(history: HistoryItem) -> some View {
        VStack(spacing: 16) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 70, height: 70)
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 32))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 6) {
                Text(viewModel.t("detail_archive_missing_title"))
                    .font(.system(size: 16, weight: .bold))
                
                Text(String(format: viewModel.t("detail_archive_missing_desc"), history.outputPath))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }
            
            if !history.snippet.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.t("detail_saved_snippet"))
                        .font(.system(size: 11, weight: .semibold))
                    Text(history.snippet)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .frame(maxWidth: 420)
                .liquidGlass(cornerRadius: 12, glowColor: .white.opacity(0.4), material: .ultraThinMaterial)
            }
            
            Spacer()
        }
        .padding(24)
    }
    
    // MARK: - Liquid Glass Inspector Header
    private func inspectorHeader(
        title: String,
        subtitle: String,
        duration: Double?,
        transcript: String?,
        outputURL: URL?,
        browserURL: String?,
        sourceAudioURL: URL? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.selectedItemID = nil
                        viewModel.selectedItemIDs.removeAll()
                        viewModel.showCombinedSessionTranscript = false
                        viewModel.selectedSection = .queue
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .bold))
                        Text(viewModel.t("nav_back_to_hub"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .liquidGlassCapsule(glowColor: .accentColor.opacity(0.3), material: .ultraThinMaterial)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(viewModel.t("nav_back_to_hub"))
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(2)
                    
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Quick Action Capsule Buttons (H / 2 Capsule Rule)
                HStack(spacing: 8) {
                    // Karaoke Mode Switcher Pill
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            viewModel.isKaraokeMode.toggle()
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: viewModel.isKaraokeMode ? "sparkles" : "doc.plaintext")
                                .font(.system(size: 11, weight: .bold))
                            Text(viewModel.isKaraokeMode ? viewModel.t("detail_karaoke") : viewModel.t("detail_plain_text"))
                                .font(.system(size: 11, weight: .bold))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(
                            viewModel.isKaraokeMode
                                ? AnyView(
                                    Capsule()
                                        .fill(LinearGradient(colors: [Color.purple, Color.blue], startPoint: .leading, endPoint: .trailing))
                                        .shadow(color: Color.purple.opacity(0.4), radius: 5, x: 0, y: 1)
                                  )
                                : AnyView(
                                    Capsule()
                                        .fill(Color.primary.opacity(0.06))
                                  )
                        )
                        .foregroundColor(viewModel.isKaraokeMode ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                    .hoverHelpTooltip(
                        title: viewModel.t("hub_tooltip_karaoke_title"),
                        description: viewModel.t("hub_tooltip_karaoke_desc"),
                        icon: "sparkles",
                        status: viewModel.isKaraokeMode ? viewModel.t("detail_karaoke") : viewModel.t("detail_plain_text"),
                        statusColor: .purple,
                        placement: .bottomTrailing,
                        width: 230
                    )
                    
                    // Session Combined View Toggle
                    if viewModel.completedCount > 1 {
                        Button(action: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                viewModel.showCombinedSessionTranscript.toggle()
                            }
                        }) {
                            Label(
                                viewModel.showCombinedSessionTranscript ? viewModel.t("detail_single_video") : String(format: viewModel.t("detail_session_combined"), viewModel.completedCount),
                                systemImage: viewModel.showCombinedSessionTranscript ? "doc.plaintext" : "rectangle.stack.fill"
                            )
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(viewModel.showCombinedSessionTranscript ? Color.accentColor : Color.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4.5)
                            .background(
                                Capsule()
                                    .fill(viewModel.showCombinedSessionTranscript ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.06))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    // Copy
                    Button(action: { viewModel.copyTranscript(text: transcript) }) {
                        Image(systemName: viewModel.copiedToast ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(viewModel.copiedToast ? Color.Premium.emeraldMineral : Color.accentColor)
                            .padding(5)
                            .background(
                                Circle()
                                    .fill(viewModel.copiedToast ? Color.Premium.emeraldMineral.opacity(0.20) : Color.accentColor.opacity(0.12))
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(transcript == nil || transcript!.isEmpty)
                    .accessibilityLabel(viewModel.t("action_copy_transcript"))
                    .hoverHelpTooltip(
                        title: "\(viewModel.t("action_copy")) (⌘⇧C)",
                        description: viewModel.t("hub_tooltip_copy_transcript_desc"),
                        icon: viewModel.copiedToast ? "checkmark" : "doc.on.doc",
                        statusColor: viewModel.copiedToast ? Color.Premium.emeraldMineral : .accentColor,
                        placement: .bottomTrailing,
                        width: 220
                    )
                    
                    // Finder
                    if let output = outputURL {
                        Button(action: { viewModel.openInFinder(path: output.path) }) {
                            Image(systemName: "folder")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(5)
                                .background(Circle().fill(Color.accentColor.opacity(0.12)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(viewModel.t("action_open_finder"))
                        .hoverHelpTooltip(
                            title: viewModel.t("hub_tooltip_finder_title"),
                            description: viewModel.t("hub_tooltip_finder_desc"),
                            icon: "folder",
                            statusColor: .accentColor,
                            placement: .bottomTrailing,
                            width: 220
                        )
                    }
                    
                    // Source Link / Original Audio File
                    if let browser = browserURL {
                        Button(action: { viewModel.openInBrowser(url: browser) }) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(5)
                                .background(Circle().fill(Color.accentColor.opacity(0.12)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(viewModel.t("action_open_browser"))
                        .hoverHelpTooltip(
                            title: viewModel.t("action_open_browser"),
                            description: browser,
                            icon: "arrow.up.right",
                            statusColor: .accentColor,
                            placement: .bottomTrailing,
                            width: 220
                        )
                    } else if let audioURL = sourceAudioURL {
                        Button(action: { viewModel.openInFinder(path: audioURL.path) }) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(5)
                                .background(Circle().fill(Color.accentColor.opacity(0.12)))
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(viewModel.t("hub_action_open_source_audio"))
                        .hoverHelpTooltip(
                            title: viewModel.t("hub_action_open_source_audio"),
                            description: audioURL.lastPathComponent,
                            icon: "arrow.up.right",
                            statusColor: .accentColor,
                            placement: .bottomTrailing,
                            width: 220
                        )
                    }
                }
            }
            
            // Metadata chips and search in text
            if let text = transcript, !text.isEmpty {
                HStack(spacing: 12) {
                    let wordCount = text.split(separator: " ").count
                    let charCount = text.count
                    
                    Text("\(wordCount) \(viewModel.t("action_words"))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Text("\(charCount) \(viewModel.t("action_chars"))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Search in text field
                    HStack(spacing: 4) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                        TextField(viewModel.t("action_search_text"), text: $searchInText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .frame(width: 130)
                        
                        if !searchInText.isEmpty {
                            Button(action: { searchInText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .liquidGlassCapsule(glowColor: .white.opacity(0.6), material: .ultraThinMaterial)
                    
                    // Kinetic Typography Scale Buttons
                    HStack(spacing: 3) {
                        Button(action: { viewModel.transcriptFontSize = max(11, viewModel.transcriptFontSize - 1) }) {
                            Text("A-").font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                        
                        Button(action: { viewModel.transcriptFontSize = min(22, viewModel.transcriptFontSize + 1) }) {
                            Text("A+").font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .liquidGlassCapsule(glowColor: .white.opacity(0.4), material: .ultraThinMaterial)
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Combined Session View
    private var combinedSessionView: some View {
        let text = viewModel.combinedTranscript
        let completedCount = viewModel.selectedItemIDs.count > 1
            ? viewModel.queueItems.filter { viewModel.selectedItemIDs.contains($0.id) && $0.state == .completed }.count
            : viewModel.completedItems.count
        
        return VStack(spacing: 0) {
            inspectorHeader(
                title: String(format: viewModel.t("detail_combined_title"), completedCount),
                subtitle: viewModel.selectedItemIDs.count > 1 ? String(format: viewModel.t("detail_combined_desc_selected"), viewModel.selectedItemIDs.count) : viewModel.t("detail_combined_desc_all"),
                duration: nil,
                transcript: text.isEmpty ? nil : text,
                outputURL: viewModel.lastOutputURL,
                browserURL: nil
            )
            
            Divider()
            
            if !text.isEmpty {
                transcriptReader(text: text)
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(viewModel.t("detail_no_transcript"))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Native Kinetic Transcript Reader (Full ⌘A, ⌘C, Smooth Scaling)
    private func transcriptReader(text: String, isLive: Bool = false) -> some View {
        NativeTranscriptTextView(
            text: text,
            fontSize: CGFloat(viewModel.transcriptFontSize),
            searchHighlight: searchInText,
            autoScrollToEnd: isLive
        )
    }
    
    // MARK: - Live Transcription Banner
    private func liveTranscriptionBanner(item: QueueItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.18))
                    .frame(width: 28, height: 28)
                
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.purple)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(viewModel.t("status_live_stream_header"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                    
                    let currentProgress = item.progress > 0 ? item.progress : viewModel.progressFraction
                    let percent = Int(currentProgress * 100)
                    Text("%\(percent)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.purple.opacity(0.15)))
                }
                
                Text(viewModel.t("status_live_stream_desc"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            let currentProgress = item.progress > 0 ? item.progress : viewModel.progressFraction
            ProgressView(value: currentProgress)
                .progressViewStyle(.linear)
                .frame(width: 130)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.purple.opacity(0.06))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.purple.opacity(0.2)),
            alignment: .bottom
        )
    }
    
    // MARK: - Active Processing State (Loading in 8-State Matrix)
    private func activeProcessingCard(title: String, state: QueueItemState) -> some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(state == .fetching ? Color.blue.opacity(0.12) : Color.purple.opacity(0.12))
                    .frame(width: 80, height: 80)
                
                Image(systemName: state == .fetching ? "arrow.down.circle.fill" : "waveform.circle.fill")
                    .font(.system(size: 42))
                    .foregroundColor(state == .fetching ? .blue : .purple)
            }
            
            VStack(spacing: 6) {
                Text(state == .fetching ? viewModel.t("detail_analyzing_audio") : viewModel.t("detail_ai_transcribing"))
                    .font(.system(size: 16, weight: .bold))
                
                Text(viewModel.currentOperation.isEmpty ? viewModel.t("detail_ai_converting") : viewModel.currentOperation)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            ProgressView(value: viewModel.progressFraction)
                .progressViewStyle(.linear)
                .frame(maxWidth: 320)
            
            HStack(spacing: 6) {
                Image(systemName: "cpu")
                    .font(.system(size: 11))
                Text("whisper.cpp v1.9.2")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .liquidGlassCapsule(glowColor: .purple.opacity(0.5), material: .ultraThinMaterial)
            
            Spacer()
        }
        .padding(24)
    }
    
    // MARK: - Ready State
    private func readyToTranscribeView(title: String) -> some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "play.circle")
                .font(.system(size: 38))
                .foregroundColor(.accentColor.opacity(0.8))
            
            Text(viewModel.t("detail_ready_title"))
                .font(.system(size: 15, weight: .semibold))
            
            Text(viewModel.t("detail_ready_desc"))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            
            Button("\(viewModel.t("action_start_now")) (⌘Return)") {
                viewModel.requestStartQueue()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!viewModel.canStartQueue)
            .padding(.top, 4)
            
            Spacer()
        }
        .padding(20)
    }
    
    // MARK: - Failed State (Error in 8-State Matrix)
    private func failedStateView(item: QueueItem) -> some View {
        VStack(spacing: 16) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.12))
                    .frame(width: 72, height: 72)
                
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 34))
                    .foregroundColor(.orange)
            }
            
            VStack(spacing: 6) {
                Text(viewModel.t("detail_error_title"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.orange)
                
                Text(item.errorMessage ?? viewModel.t("detail_default_error"))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.t("detail_suggested_solution"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                Text(viewModel.t("detail_suggested_solution_body"))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineSpacing(3)
            }
            .padding(12)
            .frame(maxWidth: 380)
            .liquidGlass(cornerRadius: 10, glowColor: .orange.opacity(0.5), material: .ultraThinMaterial)
            
            Button(viewModel.t("detail_retry_btn")) {
                viewModel.retryItem(id: item.id)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .padding(.top, 4)
            
            Spacer()
        }
        .padding(24)
    }
    
    // MARK: - Frosted Glass Studio Welcome Hub (Aligning with Visual Design Reference)
    private var studioWelcomeView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Top KPI / Metric Cards Row (4 rounded frosted glass capsules/cards)
                HStack(spacing: 12) {
                    kpiMetricCard(
                        icon: "doc.text.badge.checkmark",
                        badgeColor: .blue,
                        caption: viewModel.t("detail_kpi_transcribed"),
                        value: "\(viewModel.totalTranscribedCount)",
                        unit: viewModel.t("detail_kpi_files")
                    )
                    
                    kpiMetricCard(
                        icon: "waveform",
                        badgeColor: .purple,
                        caption: viewModel.t("detail_kpi_audio_duration"),
                        value: viewModel.totalAudioHoursString,
                        unit: ""
                    )
                    
                    kpiMetricCard(
                        icon: "folder.fill.badge.gearshape",
                        badgeColor: .green,
                        caption: viewModel.t("detail_kpi_watched_folder"),
                        value: viewModel.isFolderWatching ? viewModel.t("detail_kpi_active_1") : viewModel.t("status_disabled"),
                        unit: ""
                    )
                    
                    kpiMetricCard(
                        icon: "cpu.fill",
                        badgeColor: .orange,
                        caption: viewModel.t("detail_kpi_model_accuracy"),
                        value: viewModel.selectedModel.displayName,
                        unit: "99.4%"
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                // Analytics Row: Donut / Progress Breakdown & Recent Activity Table
                HStack(alignment: .top, spacing: 14) {
                    // Donut / Source Breakdown Card
                    sourceBreakdownCard
                        .frame(maxWidth: 310)
                    
                    // Recent Activity Table Card
                    recentActivityCard
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
                
                // Interactive Liquid Glass Drop Zone
                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.doc")
                            .font(.system(size: 26))
                            .foregroundColor(.accentColor.opacity(0.8))
                        
                        Text(viewModel.t("hub_drop_or_add"))
                            .font(.system(size: 14, weight: .semibold))
                        
                        Text(viewModel.t("hub_drop_target"))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 380)
                    }
                    
                    // Format Chips (H / 2 Capsule Rule)
                    HStack(spacing: 6) {
                        formatChip("YouTube")
                        formatChip("M4A")
                        formatChip("MP3")
                        formatChip("WAV")
                        formatChip(viewModel.t("detail_voice_memos"))
                        formatChip("iCloud")
                    }
                    
                    // Quick Action Buttons
                    HStack(spacing: 12) {
                        Button(action: { viewModel.addFromClipboard() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.clipboard")
                                Text(viewModel.t("hub_paste_clipboard_action"))
                            }
                            .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        
                        Button(action: { selectLocalAudioFiles() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform")
                                Text(viewModel.t("hub_choose_audio_file"))
                            }
                            .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
                .liquidGlass(cornerRadius: 18, glowColor: .accentColor.opacity(0.5), material: .ultraThinMaterial)
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
    
    // MARK: - KPI Card Component
    private func kpiMetricCard(
        icon: String,
        badgeColor: Color,
        caption: String,
        value: String,
        unit: String
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(badgeColor.opacity(0.16))
                    .frame(width: 38, height: 38)
                
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(badgeColor)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .liquidGlass(cornerRadius: 14, glowColor: badgeColor.opacity(0.4), material: .ultraThinMaterial)
    }
    
    // MARK: - Donut / Source Breakdown Card
    private var sourceBreakdownCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(viewModel.t("detail_source_distribution"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                
                Spacer()
                
                Image(systemName: "chart.pie.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
            }
            
            let yt = max(1, viewModel.youtubeItemsCount)
            let local = max(1, viewModel.localAudioItemsCount)
            let voice = max(1, viewModel.watchedFolderItemsCount)
            let total = Double(yt + local + voice)
            
            HStack(spacing: 16) {
                // Mini Donut Graphic
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 8)
                        .frame(width: 64, height: 64)
                    
                    Circle()
                        .trim(from: 0, to: CGFloat(Double(yt) / total))
                        .stroke(Color.red, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                    
                    Circle()
                        .trim(from: CGFloat(Double(yt) / total), to: CGFloat(Double(yt + local) / total))
                        .stroke(Color.blue, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                    
                    Circle()
                        .trim(from: CGFloat(Double(yt + local) / total), to: 1.0)
                        .stroke(Color.green, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 64, height: 64)
                        .rotationEffect(.degrees(-90))
                    
                    VStack(spacing: 0) {
                        Text("\(yt + local + voice)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Text(viewModel.t("detail_records"))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
                
                // Legend
                VStack(alignment: .leading, spacing: 6) {
                    legendRow(color: .red, label: "YouTube", count: yt)
                    legendRow(color: .blue, label: viewModel.t("detail_local_audio"), count: local)
                    legendRow(color: .green, label: viewModel.t("detail_voice_memos"), count: voice)
                }
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: 16, glowColor: .white.opacity(0.3), material: .ultraThinMaterial)
    }
    
    private func legendRow(color: Color, label: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
    }
    
    // MARK: - Recent Activity Table Card
    private var recentActivityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(viewModel.t("detail_recent_activity"))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                
                Spacer()
                
                Text("\(viewModel.completedItems.count + viewModel.historyItems.count) \(viewModel.t("detail_total"))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            let recentRows = Array(viewModel.completedItems.prefix(3))
            if recentRows.isEmpty && viewModel.historyItems.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "tray")
                        .foregroundColor(.secondary.opacity(0.5))
                        .font(.system(size: 22))
                    Text(viewModel.t("detail_no_completed"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                VStack(spacing: 6) {
                    ForEach(recentRows) { item in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 6, height: 6)
                            
                            Text(item.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            
                            Spacer()
                            
                            if let dur = item.durationSec {
                                Text(formatTime(dur))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            
                            Button(action: {
                                viewModel.selectedItemID = item.id
                            }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(8)
                    }
                    
                    ForEach(Array(viewModel.historyItems.prefix(max(0, 3 - recentRows.count)))) { hist in
                        HStack(spacing: 8) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)
                            
                            Text(hist.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(hist.kind.capitalized)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.secondary.opacity(0.12)))
                            
                            Button(action: {
                                viewModel.selectedSection = .history
                                viewModel.selectedItemID = hist.id
                            }) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding(16)
        .liquidGlass(cornerRadius: 16, glowColor: .white.opacity(0.3), material: .ultraThinMaterial)
    }
    
    private func formatChip(_ name: String) -> some View {
        Text(name)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .liquidGlassCapsule(glowColor: .white.opacity(0.3), material: .ultraThinMaterial)
    }
    
    private func selectLocalAudioFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [.audio, .movie]
        if panel.runModal() == .OK {
            viewModel.addAudioFiles(panel.urls)
        }
    }
}

// MARK: - Timestamp Formatting Helper
public func formatTime(_ seconds: Double) -> String {
    guard !seconds.isNaN && !seconds.isInfinite && seconds >= 0 else { return "00:00" }
    let totalSecs = Int(seconds)
    let m = totalSecs / 60
    let s = totalSecs % 60
    return String(format: "%02d:%02d", m, s)
}
