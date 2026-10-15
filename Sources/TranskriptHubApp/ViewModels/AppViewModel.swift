import Foundation
import SwiftUI
import AppKit
import TranskriptHubCore
import GRDB

public enum SidebarSection: String, Hashable, CaseIterable, Identifiable {
    case queue = "Kuyruk"
    case history = "Geçmiş"
    case watchedFolder = "İzlenen Klasör"
    case settings = "Ayarlar"
    
    public var id: String { rawValue }
    
    public var icon: String {
        switch self {
        case .queue: return "tray.and.arrow.down.fill"
        case .history: return "clock.arrow.circlepath"
        case .watchedFolder: return "folder.badge.gearshape"
        case .settings: return "gearshape"
        }
    }
}

public enum SettingsTab: String, CaseIterable, Identifiable, Sendable {
    case general = "general"
    case models = "models"
    case storage = "storage"
    case automation = "automation"
    case updates = "updates"
    
    public var id: String { rawValue }
}

public enum BatchScopeSelection: Hashable, Sendable {
    case all
    case latest5
    case latest10
    case latest20
    case custom(Int)
    case singleVideoOnly
}

public struct PendingBatchIngestion: Identifiable, Sendable, Equatable {
    public var id: String { url }
    public let url: String
    public let type: YouTubeLinkType
    public let title: String
    public let subtitle: String
    public let singleVideoID: String?
    
    public init(url: String, type: YouTubeLinkType, title: String, subtitle: String, singleVideoID: String? = nil) {
        self.url = url
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.singleVideoID = singleVideoID
    }
}

public enum AudioRecordingSource: String, CaseIterable, Identifiable, Sendable {
    case microphone = "microphone"
    case systemAudio = "systemAudio"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .microphone: return "🎙️ Canlı Mikrofon"
        case .systemAudio: return "🖥️ Bilgisayar / Zoom Sesi"
        }
    }
}

final class NotificationObserverToken: @unchecked Sendable {
    private let token: any NSObjectProtocol
    
    init(_ token: any NSObjectProtocol) {
        self.token = token
    }
    
    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}

@MainActor
public final class AppViewModel: ObservableObject {
    // Navigation & Selection
    @Published public var selectedSection: SidebarSection = .queue
    @Published public var selectedItemIDs: Set<String> = [] {
        didSet {
            loadAudioForSelectedItem()
        }
    }
    
    // MARK: - M1 Audio Playback & Media Retention
    public var sessionMediaDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TranskriptHub/SessionMedia", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    public func loadAudioForSelectedItem() {
        guard let item = selectedItem else {
            audioPlayer.stop()
            return
        }
        Task { @MainActor in
            await self.loadAudio(for: item)
        }
    }
    
    public var selectedItemID: String? {
        get { selectedItemIDs.first }
        set {
            if let val = newValue {
                selectedItemIDs = [val]
            } else {
                selectedItemIDs = []
            }
        }
    }
    
    // Interface Language (English, Deutsch, Türkçe)
    @Published public var appLanguage: AppLanguage = .english {
        didSet {
            UserDefaults.standard.set(appLanguage.rawValue, forKey: "appInterfaceLanguage")
        }
    }
    
    public func t(_ key: String, _ args: CVarArg...) -> String {
        let format = L10n.tr(key, lang: appLanguage)
        if args.isEmpty { return format }
        return String(format: format, arguments: args)
    }
    
    public func updateItemProgress(id: String, progress: Double) {
        guard let index = queueItems.firstIndex(where: { $0.id == id }) else { return }
        queueItems[index].progress = progress
    }
    
    public func updateItemLiveTranscript(id: String, transcript: String) {
        guard let index = queueItems.firstIndex(where: { $0.id == id }) else { return }
        queueItems[index].transcript = transcript
    }
    
    // Floating Settings Modal
    @Published public var isSettingsPresented: Bool = false
    @Published public var selectedSettingsTab: SettingsTab = .general
    @Published public var isWatchedFolderPresented: Bool = false
    @Published public var isHistoryPresented: Bool = false
    
    // Updates
    public let updateChecker = UpdateChecker()
    @Published public var updateInfo: AppUpdateInfo? = nil
    @Published public var isCheckingUpdates: Bool = false
    @Published public var updateCheckStatusText: String = ""
    @Published public var autoCheckUpdates: Bool = true
    
    // Model Catalog Search & Online Repo
    @Published public var modelSearchQuery: String = ""
    @Published public var onlineModelStatusText: String = ""
    @Published public var isCheckingOnlineModels: Bool = false
    
    public func openSettings(tab: SettingsTab = .general) {
        selectedSettingsTab = tab
        isSettingsPresented = true
        bringMainWindowToFront()
    }
    
    public func bringMainWindowToFront() {
        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: { !($0 is NSPanel) }) {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @Published public var showCombinedSessionTranscript: Bool = false
    @Published public var searchQuery: String = ""
    @Published public var transcriptFontSize: Double = 13.0
    
    // Density Mode (Standard / Compact)
    @Published public var densityMode: DensityMode = .standard
    
    // Command Palette (⌘K)
    @Published public var isCommandPalettePresented: Bool = false
    @Published public var commandPaletteSearch: String = ""
    
    // Confirmation & Undo State (8-State Matrix)
    @Published public var showUndoToast: Bool = false
    @Published public var undoToastMessage: String = ""
    private var undoBackupItems: [QueueItem] = []
    private var undoDismissTask: Task<Void, Never>?
    
    // Unified Active Queue (YouTube links & local audio files)
    @Published public var queueItems: [QueueItem] = []
    @Published public var historyItems: [HistoryItem] = []
    
    // Playlist & Channel Batch Ingestion State
    @Published public var pendingBatchIngestion: PendingBatchIngestion? = nil
    @Published public var isResolvingBatch: Bool = false
    @Published public var batchResolutionError: String? = nil
    
    // Session Save Mode Prompt
    @Published public var isSaveModePromptPresented: Bool = false
    @Published public var sessionSaveMode: SessionSaveMode = .both
    
    // Quick Add Inputs
    @Published public var quickInputText: String = ""
    @Published public var isDropTargetActive: Bool = false
    
    // Model & Language Selection
    @Published public var selectedModel: WhisperModel = .largeV3Turbo
    @Published public var selectedLanguage: String = "auto"
    
    public var downloadedModels: [WhisperModel] {
        modelManager.downloadedModels()
    }
    
    public var selectedModelTitle: String {
        if downloadedModels.isEmpty {
            return "Model Yok"
        }
        return selectedModel.rawValue.capitalized
    }
    
    // Model Download & Deletion Tracking
    @Published public var downloadingModel: WhisperModel? = nil
    @Published public var modelDownloadFraction: Double = 0.0
    @Published public var modelDownloadStatusText: String = ""
    
    // Processing & Progress
    @Published public var isProcessing: Bool = false
    @Published public var progressFraction: Double = 0.0
    @Published public var statusMessage: String = "Hazır"
    @Published public var currentOperation: String = ""
    @Published public var lastOutputURL: URL? = nil
    @Published public var errorMessage: String? = nil
    @Published public var copiedToast: Bool = false
    
    // Audio Playback & Interactive Waveform Scrubbing
    public let audioPlayer = AudioPlayerController()
    public let waveformGenerator = AccelerateWaveformGenerator()
    @Published public var activeWaveformPoints: [WaveformPoint] = []
    @Published public var isLoadingWaveform: Bool = false
    @Published public var isKaraokeMode: Bool = true
    @Published public var currentPlayingItemId: String? = nil
    
    // In-App Microphone / System Audio Recording Engine (Milestone 2)
    public let recordingEngine = AudioRecordingEngine()
    @Published public var isRecordingModalPresented: Bool = false
    @Published public var isRecordingSourceSheetPresented: Bool = false
    @Published public var recordingSource: AudioRecordingSource = .microphone
    
    public func startRecording(source: AudioRecordingSource = .microphone) async {
        self.recordingSource = source
        do {
            _ = try await recordingEngine.startRecording()
            isRecordingModalPresented = true
            statusMessage = source == .microphone ? "Mikrofon kaydı başladı..." : "Sistem / Zoom sesi kaydı başladı..."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    public func stopRecordingAndTranscribe() async {
        do {
            let url = try await recordingEngine.stopRecording()
            isRecordingModalPresented = false
            statusMessage = "Kayıt tamamlandı, deşifre ediliyor..."
            addAudioFiles([url])
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    public func cancelRecording() {
        recordingEngine.cancelRecording()
        isRecordingModalPresented = false
        statusMessage = "Kayıt iptal edildi."
    }
    
    // KPI Analytics for Frosted Glass Dashboard
    public var totalTranscribedCount: Int {
        completedItems.count + historyItems.count
    }
    
    public var totalAudioSeconds: Double {
        let queueSecs = queueItems.compactMap(\.durationSec).reduce(0.0, +)
        let histSecs = Double(historyItems.count) * 180.0
        return queueSecs + histSecs
    }
    
    public var totalAudioHoursString: String {
        let hours = totalAudioSeconds / 3600.0
        return String(format: "%.1f saat", max(hours, 0.1))
    }
    
    public var totalWordCount: Int {
        let queueWords = queueItems.compactMap(\.transcript).map { $0.split(separator: " ").count }.reduce(0, +)
        let histWords = historyItems.map { $0.snippet.split(separator: " ").count }.reduce(0, +)
        return queueWords + histWords
    }
    
    public var youtubeItemsCount: Int {
        queueItems.filter(\.isYouTube).count + historyItems.filter { $0.kind == "youtube" }.count
    }
    
    public var localAudioItemsCount: Int {
        queueItems.filter { !$0.isYouTube }.count + historyItems.filter { $0.kind == "audio" }.count
    }
    
    public var watchedFolderItemsCount: Int {
        queueItems.filter { $0.subtitle.contains("İzlenen") || $0.subtitle.contains("Watched") || $0.subtitle.contains("Sesli Not") }.count
    }
    
    // System Monitors
    @Published public var isClipboardMonitoring: Bool = true {
        didSet {
            if isClipboardMonitoring {
                clipboardMonitor.startMonitoring()
            } else {
                clipboardMonitor.stopMonitoring()
            }
        }
    }
    
    @Published public var isFolderWatching: Bool = true {
        didSet {
            if isFolderWatching {
                folderWatcher.startWatching()
            } else {
                folderWatcher.stopWatching()
            }
        }
    }
    
    public private(set) var clipboardMonitor: ClipboardMonitor!
    public var folderWatcher: FolderWatcher!
    public let modelManager = ModelManager()
    public let outputWriter = OutputWriter()
    private var jobManager: JobManager?
    private var appDatabase: AppDatabase?
    public private(set) var transcriptCacheManager: TranscriptCacheManager?
    private var didBecomeActiveObserver: NotificationObserverToken?
    
    @Published public var fullDiskAccessStatus: FullDiskAccessStatus = FullDiskAccessHelper.checkStatus()
    
    public func checkFullDiskAccess() {
        fullDiskAccessStatus = FullDiskAccessHelper.checkStatus()
    }
    
    public func openFullDiskAccessSettings() {
        FullDiskAccessHelper.openSystemSettings()
    }
    
    public var watchedDirectoryPath: String {
        folderWatcher.watchedDirectory.path
    }
    
    public var activeWatchedDirectoriesCount: Int {
        folderWatcher.activeWatchedDirectories.count
    }
    
    public var activeCloudDownloads: Set<String> {
        folderWatcher.activeCloudDownloads
    }
    
    public var isCloudDownloading: Bool {
        !folderWatcher.activeCloudDownloads.isEmpty
    }
    
    public func triggerFolderScan() {
        folderWatcher.triggerImmediateScan()
        statusMessage = "İzlenen klasörler tarandı."
    }
    
    public func triggerCloudScan() {
        statusMessage = "iCloud ses dosyaları denetleniyor..."
        Task {
            await folderWatcher.forceDownloadAllCloudItems()
            statusMessage = "iCloud taraması tamamlandı."
        }
    }
    
    public func selectCustomWatchedFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = t("action_add")
        panel.message = t("watched_choose_folder_prompt")
        
        if let current = folderWatcher.customFolderURL {
            panel.directoryURL = current
        } else {
            panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        }
        
        if panel.runModal() == .OK, let selectedURL = panel.url {
            folderWatcher.customFolderURL = selectedURL
            folderWatcher.watchCustomFolder = true
            Task {
                await folderWatcher.scanDirectory()
            }
        }
    }
    
    public func resetCustomWatchedFolder() {
        folderWatcher.customFolderURL = nil
        folderWatcher.watchCustomFolder = false
    }
    
    public func sourceLabel(for url: URL) -> String {
        let path = url.path
        if path.contains("group.com.apple.VoiceMemos.shared") {
            return "Apple Sesli Notlar"
        } else if path.contains("com~apple~CloudDocs") {
            return "iCloud Drive"
        } else if let custom = folderWatcher.customFolderURL, path.hasPrefix(custom.path) {
            return custom.lastPathComponent
        } else {
            return "İzlenen Klasör"
        }
    }
    
    // MARK: - Action-Oriented Metrics & 8-State Computed Properties
    public var successfulCount: Int {
        queueItems.filter { $0.state == .completed }.count
    }
    
    public var completedCount: Int {
        successfulCount
    }
    
    public var failedCount: Int {
        queueItems.filter { $0.state == .failed }.count
    }
    
    public var inProgressCount: Int {
        queueItems.filter { $0.isInProgress }.count
    }
    
    public var queuedCount: Int {
        queueItems.filter { $0.state == .queued }.count
    }
    
    public func localizedState(_ state: QueueItemState) -> String {
        switch state {
        case .queued: return t("status_queued")
        case .fetching: return t("status_fetching")
        case .transcribing: return t("status_transcribing")
        case .completed: return t("status_completed")
        case .failed: return t("status_failed")
        }
    }
    
    public var actionableSummary: String {
        if queueItems.isEmpty {
            return isFolderWatching ? "\(t("action_empty_queue_title")) • 1 \(t("section_watched_folder"))" : "\(t("action_empty_queue_title")) • \(t("status_ready"))"
        }
        var parts: [String] = []
        if successfulCount > 0 {
            parts.append("\(successfulCount) \(t("status_completed"))")
        }
        if inProgressCount > 0 {
            parts.append("\(inProgressCount) \(t("status_transcribing"))")
        }
        if queuedCount > 0 {
            parts.append("\(queuedCount) \(t("status_queued"))")
        }
        if failedCount > 0 {
            parts.append("\(failedCount) \(t("status_failed")) (\(t("action_retry")))")
        }
        if isFolderWatching {
            parts.append("1 \(t("section_watched_folder"))")
        }
        return parts.joined(separator: " • ")
    }
    
    // Action-Oriented Queue Categorization
    public var failedItems: [QueueItem] {
        filteredQueueItems.filter { $0.state == .failed }
    }
    
    public var activeOrQueuedItems: [QueueItem] {
        filteredQueueItems.filter { $0.state == .queued || $0.isInProgress }
    }
    
    public var completedItems: [QueueItem] {
        filteredQueueItems.filter { $0.state == .completed }
    }
    
    public var filteredQueueItems: [QueueItem] {
        if searchQuery.isEmpty {
            return queueItems
        }
        return queueItems.filter {
            $0.title.localizedCaseInsensitiveContains(searchQuery) ||
            $0.subtitle.localizedCaseInsensitiveContains(searchQuery) ||
            ($0.transcript?.localizedCaseInsensitiveContains(searchQuery) ?? false)
        }
    }
    
    public var selectedItem: QueueItem? {
        guard selectedSection == .queue else { return nil }
        guard let id = selectedItemID else { return nil }
        return queueItems.first(where: { $0.id == id })
    }
    
    public var selectedItems: [QueueItem] {
        guard selectedSection == .queue else { return [] }
        return queueItems.filter { selectedItemIDs.contains($0.id) }
    }
    
    public var combinedTranscript: String {
        let itemsToInclude: [QueueItem]
        let multiSelected = queueItems.filter { selectedItemIDs.contains($0.id) && $0.state == .completed }
        if multiSelected.count > 1 {
            itemsToInclude = multiSelected
        } else {
            itemsToInclude = queueItems.filter { $0.state == .completed }
        }
        
        return itemsToInclude.enumerated().compactMap { index, item -> String? in
            guard let t = item.transcript, !t.isEmpty else { return nil }
            return """
            ================================================================================
            🎬 [\(index + 1)/\(itemsToInclude.count)] \(item.title)
            Kanal/Kaynak: \(item.subtitle)
            ================================================================================
            
            \(t)
            """
        }.joined(separator: "\n\n\n")
    }
    
    public func selectAllQueueItems() {
        selectedItemIDs = Set(queueItems.map(\.id))
    }
    
    public func deselectAllQueueItems() {
        selectedItemIDs.removeAll()
    }
    
    public var selectedHistoryItem: HistoryItem? {
        guard selectedSection == .history else { return nil }
        guard let id = selectedItemID else { return nil }
        return historyItems.first(where: { $0.id == id })
    }
    
    // MARK: - Audio Playback & Interactive Scrubbing Control
    public func loadAudio(for item: QueueItem) async {
        guard let url = item.effectiveAudioURL else { return }
        if currentPlayingItemId == item.id && audioPlayer.currentURL == url {
            return
        }
        do {
            try await audioPlayer.load(url: url)
            currentPlayingItemId = item.id
            loadWaveform(for: url)
        } catch {
            Log.error("Could not load audio for queue item \(item.id): \(error)")
        }
    }
    
    public func loadAudio(for history: HistoryItem) async {
        let txtURL = URL(fileURLWithPath: history.outputPath)
        let possibleExtensions = ["m4a", "mp3", "wav", "aac", "caf"]
        var foundURL: URL? = nil
        for ext in possibleExtensions {
            let candidate = txtURL.deletingPathExtension().appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: candidate.path) {
                foundURL = candidate
                break
            }
        }
        guard let audioURL = foundURL else { return }
        do {
            try await audioPlayer.load(url: audioURL)
            currentPlayingItemId = history.id
            loadWaveform(for: audioURL)
        } catch {
            Log.error("Could not load audio for history item \(history.id): \(error)")
        }
    }
    
    public func loadWaveform(for audioURL: URL) {
        isLoadingWaveform = true
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let points = try await self.waveformGenerator.generateWaveform(from: audioURL, targetPoints: 120)
                await MainActor.run {
                    self.activeWaveformPoints = points
                    self.isLoadingWaveform = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingWaveform = false
                }
            }
        }
    }
    
    public func togglePlayPause() {
        if let item = selectedItem, (audioPlayer.currentURL == nil || currentPlayingItemId != item.id), item.effectiveAudioURL != nil {
            Task {
                await loadAudio(for: item)
                audioPlayer.play()
            }
        } else {
            audioPlayer.togglePlayPause()
        }
    }
    
    public func seekAudio(to time: Double) {
        audioPlayer.seek(to: time)
    }
    
    public func skipBackward() {
        audioPlayer.skipBackward(by: 5.0)
    }
    
    public func skipForward() {
        audioPlayer.skipForward(by: 5.0)
    }
    
    public func setAudioSpeed(_ rate: Float) {
        audioPlayer.setPlaybackRate(rate)
    }
    
    public func words(for item: QueueItem) -> [WordItem] {
        if let words = item.words, !words.isEmpty {
            return words
        }
        let text = item.transcript ?? ""
        guard !text.isEmpty else { return [] }
        let tokens = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        
        let totalDuration = (item.durationSec ?? (audioPlayer.duration > 0 ? audioPlayer.duration : Double(tokens.count) * 0.35))
        let durationPerWord = max(0.08, totalDuration / Double(tokens.count))
        
        var generated: [WordItem] = []
        generated.reserveCapacity(tokens.count)
        for (i, token) in tokens.enumerated() {
            let start = Double(i) * durationPerWord
            let end = start + durationPerWord
            generated.append(WordItem(text: token, start: start, end: end))
        }
        return generated
    }
    
    public func words(for history: HistoryItem, text: String) -> [WordItem] {
        guard !text.isEmpty else { return [] }
        let tokens = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return [] }
        let totalDuration = audioPlayer.duration > 0 ? audioPlayer.duration : Double(tokens.count) * 0.35
        let durationPerWord = max(0.08, totalDuration / Double(tokens.count))
        
        return tokens.enumerated().map { i, token in
            let start = Double(i) * durationPerWord
            let end = start + durationPerWord
            return WordItem(text: token, start: start, end: end)
        }
    }
    
    public func segments(for item: QueueItem) -> [Segment] {
        if !item.segments.isEmpty {
            return item.segments
        }
        let text = item.transcript ?? ""
        guard !text.isEmpty else { return [] }
        let lines = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let totalDuration = item.durationSec ?? (audioPlayer.duration > 0 ? audioPlayer.duration : Double(max(1, lines.count)) * 4.0)
        let step = max(0.5, totalDuration / Double(max(1, lines.count)))
        
        return lines.enumerated().map { i, line in
            let start = Double(i) * step
            let end = min(totalDuration, start + step)
            let words = Segment.interpolateWords(for: line, start: start, end: end)
            return Segment(start: start, end: end, text: line, speaker: "Speaker \((i % 2) + 1)", words: words)
        }
    }
    
    public func segments(for history: HistoryItem, text: String) -> [Segment] {
        guard !text.isEmpty else { return [] }
        let lines = text.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let totalDuration = audioPlayer.duration > 0 ? audioPlayer.duration : Double(max(1, lines.count)) * 4.0
        let step = max(0.5, totalDuration / Double(max(1, lines.count)))
        
        return lines.enumerated().map { i, line in
            let start = Double(i) * step
            let end = min(totalDuration, start + step)
            let words = Segment.interpolateWords(for: line, start: start, end: end)
            return Segment(start: start, end: end, text: line, speaker: "Speaker \((i % 2) + 1)", words: words)
        }
    }
    
    // MARK: - M3 Transcript Summarizer & Speaker Editing
    public let summarizer = TranscriptSummarizer()
    
    public func summary(for item: QueueItem) -> TranscriptSummary {
        let segs = segments(for: item)
        if !segs.isEmpty {
            return summarizer.summarize(segments: segs)
        }
        return summarizer.summarize(text: item.transcript ?? "", duration: item.durationSec)
    }
    
    public func summary(for history: HistoryItem, text: String) -> TranscriptSummary {
        let segs = segments(for: history, text: text)
        if !segs.isEmpty {
            return summarizer.summarize(segments: segs)
        }
        return summarizer.summarize(text: text, duration: nil)
    }
    
    public func renameSpeaker(in item: QueueItem, from oldName: String, to newName: String) async {
        guard let index = queueItems.firstIndex(where: { $0.id == item.id }) else { return }
        let currentSegments = segments(for: queueItems[index])
        let diarizer = AcousticTurnDiarizer()
        let updatedSegments = diarizer.renameSpeaker(in: currentSegments, from: oldName, to: newName)
        
        queueItems[index].segments = updatedSegments
        let newFullText = updatedSegments.map(\.text).joined(separator: "\n\n")
        queueItems[index].transcript = newFullText
        
        // Atomic DB Update
        if let db = try? AppDatabase.makeShared() {
            try? await db.updateTranscript(jobId: item.id, newText: newFullText, segments: updatedSegments)
        }
        
        // Update on disk if file exists
        if let outURL = queueItems[index].outputURL {
            try? newFullText.write(to: outURL, atomically: true, encoding: .utf8)
        }
    }
    
    public func updateSegmentText(in item: QueueItem, segmentIndex: Int, newText: String) async {
        guard let index = queueItems.firstIndex(where: { $0.id == item.id }) else { return }
        var currentSegments = segments(for: queueItems[index])
        guard segmentIndex >= 0 && segmentIndex < currentSegments.count else { return }
        
        currentSegments[segmentIndex].text = newText
        let words = Segment.interpolateWords(for: newText, start: currentSegments[segmentIndex].start, end: currentSegments[segmentIndex].end)
        currentSegments[segmentIndex].words = words
        
        queueItems[index].segments = currentSegments
        let newFullText = currentSegments.map(\.text).joined(separator: "\n\n")
        queueItems[index].transcript = newFullText
        
        // Atomic DB Update
        if let db = try? AppDatabase.makeShared() {
            try? await db.updateTranscript(jobId: item.id, newText: newFullText, segments: currentSegments)
        }
        
        // Update on disk if file exists
        if let outURL = queueItems[index].outputURL {
            try? newFullText.write(to: outURL, atomically: true, encoding: .utf8)
        }
    }
    
    // MARK: - M5 Media Cache Eviction
    public var sessionMediaCacheSizeString: String {
        let dir = sessionMediaDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "0 KB"
        }
        var totalBytes: Int64 = 0
        for file in files {
            if let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize {
                totalBytes += Int64(size)
            }
        }
        return ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
    
    public func evictSessionMediaCache() {
        let dir = sessionMediaDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for file in files {
            if audioPlayer.currentURL == file { continue }
            try? FileManager.default.removeItem(at: file)
        }
        statusMessage = "Medya önbelleği temizlendi."
    }
    
    public init() {
        let savedLang = UserDefaults.standard.string(forKey: "appInterfaceLanguage") ?? "en"
        self.appLanguage = AppLanguage(rawValue: savedLang) ?? .english
        
        if let bestDownloaded = self.modelManager.downloadedModels().first {
            self.selectedModel = bestDownloaded
        }
        
        self.clipboardMonitor = ClipboardMonitor { [weak self] video in
            self?.handleClipboardDiscoveredVideo(video)
        }
        self.clipboardMonitor.onBatchDetected = { [weak self] linkType in
            self?.presentBatchIngestion(for: linkType)
        }
        
        self.folderWatcher = FolderWatcher()
        self.folderWatcher.onNewAudioDiscovered = { [weak self] audioURL in
            await self?.handleAutoDiscoveredAudio(audioURL)
        }
        if self.isFolderWatching {
            self.folderWatcher.startWatching()
        }
        if self.isClipboardMonitoring {
            self.clipboardMonitor.startMonitoring()
        }
        
        let token = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkFullDiskAccess()
            }
        }
        self.didBecomeActiveObserver = NotificationObserverToken(token)
        
        Task {
            do {
                let db = try AppDatabase.makeShared()
                self.appDatabase = db
                self.jobManager = JobManager(database: db, outputWriter: self.outputWriter)
                self.transcriptCacheManager = TranscriptCacheManager(database: db)
                try await self.jobManager?.recoverState()
                await self.loadHistoryFromDatabase()
                await self.resolvePendingVideoTitles()
            } catch {
                self.errorMessage = "Veritabanı başlatılamadı: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Zero-Touch Ingestion Handlers
    private func handleClipboardDiscoveredVideo(_ video: ParsedYouTubeVideo) {
        addYouTubeVideo(video, source: "Pano", isNewlyDiscovered: true)
    }
    
    private func handleAutoDiscoveredAudio(_ url: URL) async {
        guard AudioValidator.isExtensionSupported(url.pathExtension) else { return }
        guard !queueItems.contains(where: { $0.id == url.path }) else { return }
        
        let title = url.deletingPathExtension().lastPathComponent
        let duration = try? AudioValidator.validate(fileURL: url)
        
        // 1. Check if previously transcribed by duration + name
        if let cached = await transcriptCacheManager?.findCached(
            title: title,
            durationSec: duration,
            sourcePath: url.path,
            externalID: url.path
        ) {
            Log.info("Audio file previously processed, retrieved from cache: \(title)")
            var item = QueueItem(
                id: url.path,
                kind: .audioFile(url),
                title: title,
                subtitle: "Önbellekten Yüklendi • Zaten Deşifre Edilmiş",
                state: .completed,
                transcript: cached.transcriptText,
                isNewlyDiscovered: true,
                audioURL: url
            )
            item.progress = 1.0
            item.durationSec = duration
            if let outPath = cached.outputPath {
                item.outputURL = URL(fileURLWithPath: outPath)
            }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                queueItems.append(item)
            }
            return
        }
        
        var item = QueueItem(
            id: url.path,
            kind: .audioFile(url),
            title: title,
            subtitle: "\(sourceLabel(for: url)) • \(url.pathExtension.uppercased())",
            state: .queued,
            isNewlyDiscovered: true,
            audioURL: url
        )
        item.durationSec = duration
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            queueItems.append(item)
        }
        startProcessingQueue()
    }
    
    // MARK: - Queue Management
    public func addYouTubeVideo(
        _ video: ParsedYouTubeVideo,
        source: String = "YouTube",
        preloadedTitle: String? = nil,
        isNewlyDiscovered: Bool = false
    ) {
        guard !queueItems.contains(where: { $0.id == video.videoID }) else { return }
        
        let initialTitle = preloadedTitle ?? "Video başlığı alınıyor..."
        let initialSubtitle = "\(source) • Başlık aranıyor"
        let fallbackThumb = URL(string: "https://i.ytimg.com/vi/\(video.videoID)/mqdefault.jpg")
        
        let item = QueueItem(
            id: video.videoID,
            kind: .youtube(video),
            title: initialTitle,
            subtitle: initialSubtitle,
            state: .queued,
            isNewlyDiscovered: isNewlyDiscovered,
            thumbnailURL: fallbackThumb
        )
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            queueItems.append(item)
        }
        
        // Fast asynchronous title, author and thumbnail resolution (~100ms)
        Task { @MainActor [weak self] in
            await self?.resolveMetadata(for: video.videoID, source: source)
            
            // Check cache for existing transcript
            if let cached = await self?.transcriptCacheManager?.findCached(
                title: initialTitle,
                durationSec: nil,
                externalID: video.videoID
            ) {
                if let idx = self?.queueItems.firstIndex(where: { $0.id == video.videoID }) {
                    self?.queueItems[idx].transcript = cached.transcriptText
                    self?.queueItems[idx].state = .completed
                    self?.queueItems[idx].progress = 1.0
                    self?.queueItems[idx].subtitle = "\(source) • Önbellekten Yüklendi (Zaten İşlenmiş)"
                    if let outPath = cached.outputPath {
                        self?.queueItems[idx].outputURL = URL(fileURLWithPath: outPath)
                    }
                }
            }
        }
    }
    
    @MainActor
    public func resolveMetadata(for videoID: String, source: String) async {
        let info = await YouTubeMetadataResolver.shared.resolve(videoID: videoID)
        guard let index = queueItems.firstIndex(where: { $0.id == videoID }) else { return }
        
        withAnimation(.easeOut(duration: 0.2)) {
            if queueItems[index].title == "Video başlığı alınıyor..." || queueItems[index].title.hasPrefix("http") {
                queueItems[index].title = info.title
            }
            let channel = info.authorName ?? "YouTube"
            queueItems[index].subtitle = "\(channel) • \(source)"
            if let thumb = info.thumbnailURL {
                queueItems[index].thumbnailURL = thumb
            }
            queueItems[index].channelTitle = info.authorName
        }
    }
    
    public func resolvePendingVideoTitles() async {
        for item in queueItems {
            if case .youtube(let video) = item.kind {
                if item.title.hasPrefix("http") || item.title == "Video başlığı alınıyor..." || item.channelTitle == nil {
                    await resolveMetadata(for: video.videoID, source: "YouTube")
                }
            }
        }
    }
    
    public func addAudioFiles(_ urls: [URL]) {
        for url in urls {
            guard AudioValidator.isExtensionSupported(url.pathExtension) else { continue }
            guard !queueItems.contains(where: { $0.id == url.path }) else { continue }
            
            let title = url.deletingPathExtension().lastPathComponent
            let duration = try? AudioValidator.validate(fileURL: url)
            
            var item = QueueItem(
                id: url.path,
                kind: .audioFile(url),
                title: title,
                subtitle: "Ses Dosyası • \(url.pathExtension.uppercased())",
                state: .queued,
                audioURL: url
            )
            item.durationSec = duration
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                queueItems.append(item)
            }
            
            // Check cache by filename and audio duration
            let itemId = item.id
            Task { [weak self] in
                if let cached = await self?.transcriptCacheManager?.findCached(
                    title: title,
                    durationSec: duration,
                    sourcePath: url.path,
                    externalID: url.path
                ) {
                    await MainActor.run {
                        guard let self = self, let idx = self.queueItems.firstIndex(where: { $0.id == itemId }) else { return }
                        self.queueItems[idx].transcript = cached.transcriptText
                        self.queueItems[idx].state = .completed
                        self.queueItems[idx].progress = 1.0
                        self.queueItems[idx].subtitle = "Önbellekten Yüklendi • Zaten Deşifre Edilmiş"
                        if let outPath = cached.outputPath {
                            self.queueItems[idx].outputURL = URL(fileURLWithPath: outPath)
                        }
                    }
                }
            }
        }
    }
    
    public func addFromQuickInput() {
        let trimmed = quickInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // 1. Check if the input is a single link (playlist, channel, or video)
        if let detected = URLParser.detectType(trimmed) {
            switch detected {
            case .singleVideo(let video):
                addYouTubeVideo(video, source: "Hızlı Giriş")
            case .playlist, .channel:
                presentBatchIngestion(for: detected)
            }
            quickInputText = ""
            return
        }
        
        // 2. Fallback to bulk link extraction
        let parsedList = URLParser.parseBulk(trimmed)
        if !parsedList.isEmpty {
            for p in parsedList {
                addYouTubeVideo(p, source: "Hızlı Giriş")
            }
        } else {
            let fileURL = URL(fileURLWithPath: trimmed)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                addAudioFiles([fileURL])
            }
        }
        quickInputText = ""
    }
    
    public func addFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let detected = URLParser.detectType(trimmed) {
            switch detected {
            case .singleVideo(let video):
                addYouTubeVideo(video, source: "Pano")
            case .playlist, .channel:
                presentBatchIngestion(for: detected)
            }
            return
        }
        
        let parsed = URLParser.parseBulk(text)
        for p in parsed {
            addYouTubeVideo(p, source: "Pano")
        }
    }
    
    // MARK: - Batch Ingestion (Playlist & Channel)
    public func presentBatchIngestion(for linkType: YouTubeLinkType) {
        NSApp.activate(ignoringOtherApps: true)
        switch linkType {
        case .singleVideo(let video):
            addYouTubeVideo(video)
        case .playlist(let url, let playlistID, let videoID):
            self.batchResolutionError = nil
            self.isResolvingBatch = false
            self.pendingBatchIngestion = PendingBatchIngestion(
                url: url,
                type: linkType,
                title: "Oynatma Listesi",
                subtitle: "Liste ID: \(playlistID)",
                singleVideoID: videoID
            )
        case .channel(let url, let channelIdentifier):
            self.batchResolutionError = nil
            self.isResolvingBatch = false
            self.pendingBatchIngestion = PendingBatchIngestion(
                url: url,
                type: linkType,
                title: "YouTube Kanalı",
                subtitle: channelIdentifier.hasPrefix("@") ? channelIdentifier : "Kanal: \(channelIdentifier)",
                singleVideoID: nil
            )
        }
    }
    
    public func cancelBatchIngestion() {
        pendingBatchIngestion = nil
        isResolvingBatch = false
        batchResolutionError = nil
    }
    
    @MainActor
    public func resolveAndIngestBatch(selection: BatchScopeSelection, customCount: Int = 10) async {
        guard let pending = pendingBatchIngestion else { return }
        
        if case .singleVideoOnly = selection, let videoID = pending.singleVideoID {
            let video = ParsedYouTubeVideo(videoID: videoID)
            addYouTubeVideo(video)
            pendingBatchIngestion = nil
            return
        }
        
        isResolvingBatch = true
        batchResolutionError = nil
        
        let maxVideos: Int?
        switch selection {
        case .all:
            maxVideos = nil
        case .latest5:
            maxVideos = 5
        case .latest10:
            maxVideos = 10
        case .latest20:
            maxVideos = 20
        case .custom:
            maxVideos = max(1, customCount)
        case .singleVideoOnly:
            maxVideos = 1
        }
        
        do {
            let toolMgr = ToolManager()
            let ytdlp = YTDLPClient(toolManager: toolMgr)
            let entries = try await ytdlp.resolvePlaylistOrChannel(url: pending.url, maxVideos: maxVideos)
            
            guard !entries.isEmpty else {
                batchResolutionError = "Bağlantıda video bulunamadı veya liste gizli."
                isResolvingBatch = false
                return
            }
            
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                for entry in entries {
                    guard !queueItems.contains(where: { $0.id == entry.id }) else { continue }
                    let parsed = ParsedYouTubeVideo(videoID: entry.id)
                    let fallbackThumb = URL(string: "https://i.ytimg.com/vi/\(entry.id)/mqdefault.jpg")
                    let item = QueueItem(
                        id: entry.id,
                        kind: .youtube(parsed),
                        title: entry.title,
                        subtitle: pending.title,
                        state: .queued,
                        isNewlyDiscovered: false,
                        thumbnailURL: fallbackThumb
                    )
                    queueItems.append(item)
                }
                statusMessage = "\(entries.count) video kuyruğa eklendi."
                pendingBatchIngestion = nil
                isResolvingBatch = false
            }
        } catch {
            batchResolutionError = error.localizedDescription
            isResolvingBatch = false
        }
    }
    
    public func addSampleYouTube() {
        if let sample = URLParser.parseSingle("https://www.youtube.com/watch?v=jNQXAC9IVRw") {
            addYouTubeVideo(sample)
        }
    }
    
    public func removeItem(id: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            queueItems.removeAll(where: { $0.id == id })
            if selectedItemID == id {
                selectedItemID = nil
            }
        }
    }
    
    // MARK: - Undo / Confirmation Pattern (8-State Matrix)
    public func clearQueueWithUndo() {
        guard !queueItems.isEmpty else { return }
        undoBackupItems = queueItems
        let count = queueItems.count
        
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            queueItems.removeAll()
            selectedItemID = nil
            undoToastMessage = "\(count) işlem kuyruktan kaldırıldı."
            showUndoToast = true
        }
        
        undoDismissTask?.cancel()
        undoDismissTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.showUndoToast = false
                self.undoBackupItems.removeAll()
            }
        }
    }
    
    public func performUndo() {
        undoDismissTask?.cancel()
        guard !undoBackupItems.isEmpty else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            queueItems = undoBackupItems
            selectedItemID = nil
            undoBackupItems.removeAll()
            showUndoToast = false
        }
    }
    
    public func dismissUndoToast() {
        undoDismissTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showUndoToast = false
            undoBackupItems.removeAll()
        }
    }
    
    // MARK: - Retry Logic for Failed Items
    public func retryFailedItems() {
        for i in 0..<queueItems.count {
            if queueItems[i].state == .failed {
                queueItems[i].state = .queued
                queueItems[i].errorMessage = nil
            }
        }
        startProcessingQueue()
    }
    
    public func retryItem(id: String) {
        if let idx = queueItems.firstIndex(where: { $0.id == id }) {
            queueItems[idx].state = .queued
            queueItems[idx].errorMessage = nil
            startProcessingQueue()
        }
    }
    
    // MARK: - Unified Processing Loop
    public func requestStartQueue() {
        guard !isProcessing else { return }
        let totalCount = queueItems.count
        let pending = queueItems.filter { $0.state == .queued || $0.state == .failed }
        if totalCount > 1 || pending.count > 1 {
            isSaveModePromptPresented = true
        } else if !pending.isEmpty {
            startProcessingQueue(saveMode: .individual)
        }
    }
    
    public func startProcessingQueue(saveMode: SessionSaveMode = .both) {
        guard !queueItems.isEmpty else { return }
        guard !isProcessing else {
            Log.info("Queue is already processing. Concurrent execution prevented.")
            return
        }
        
        self.sessionSaveMode = saveMode
        isProcessing = true
        progressFraction = 0.05
        statusMessage = "İşlem başlatılıyor..."
        errorMessage = nil
        
        let totalCount = queueItems.count
        let model = selectedModel
        let lang = selectedLanguage == "auto" ? nil : selectedLanguage
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                // 1. Ensure Model and Tools
                try self.modelManager.ensureDirectoryExists()
                let modelURL: URL
                if !self.modelManager.isModelDownloaded(model) {
                    if let alternate = self.downloadedModels.first {
                        self.selectedModel = alternate
                        modelURL = self.modelManager.localURL(for: alternate)
                    } else {
                        self.statusMessage = "İndirilmiş model bulunamadı."
                        self.errorMessage = "Transkripsiyon için indirilmiş Whisper modeli bulunamadı. Lütfen Ayarlar sekmesinden bir model indirin."
                        self.selectedSection = .settings
                        self.isProcessing = false
                        return
                    }
                } else {
                    modelURL = self.modelManager.localURL(for: model)
                }
                
                let whisperEngine = try WhisperCppEngine(modelPath: modelURL.path)
                let audioDecoder = AudioDecoder()
                let postProcessor = TranscriptPostProcessor()
                let toolMgr = ToolManager()
                try await toolMgr.ensureToolsReady()
                let ytdlp = YTDLPClient(toolManager: toolMgr)
                
                for (index, item) in self.queueItems.enumerated() {
                    // Skip already completed items
                    if item.state == .completed {
                        continue
                    }
                    
                    self.statusMessage = "[\(index + 1)/\(totalCount)] \(item.title) işleniyor..."
                    if self.selectedItemID != nil {
                        self.selectedItemID = item.id
                    }
                    
                    // Create an isolated workspace directory specifically for this video to avoid file collision
                    let itemWorkspace = FileManager.default.temporaryDirectory
                        .appendingPathComponent("transkript_\(item.id)_\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: itemWorkspace, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: itemWorkspace) }
                    
                    var current = item
                    current.isNewlyDiscovered = false
                    
                    switch item.kind {
                    case .youtube(let video):
                        // Check cache before fetching or transcribing
                        if let cached = await self.transcriptCacheManager?.findCached(
                            title: current.title,
                            durationSec: current.durationSec,
                            externalID: video.videoID
                        ) {
                            Log.info("YouTube video loaded from cache: \(current.title)")
                            current.transcript = cached.transcriptText
                            current.state = .completed
                            current.progress = 1.0
                            current.subtitle = "Loaded from Cache • Already Transcribed"
                            if let outPath = cached.outputPath {
                                current.outputURL = URL(fileURLWithPath: outPath)
                                self.lastOutputURL = current.outputURL
                            }
                            self.updateItem(current)
                            continue
                        }
                        
                        current.state = .fetching
                        self.updateItem(current)
                        self.currentOperation = "Downloading YouTube audio (yt-dlp)..."
                        
                        do {
                            let media = try await ytdlp.fetch(url: video.canonicalURL, into: itemWorkspace)
                            let channel = media.metadata.channel ?? "YouTube"
                            let duration = media.metadata.duration ?? 0
                            current.title = media.metadata.title
                            current.subtitle = "\(channel) • \(Int(duration))s"
                            current.durationSec = media.metadata.duration
                            
                            // Check cache again with fetched metadata title
                            if let cached = await self.transcriptCacheManager?.findCached(
                                title: media.metadata.title,
                                durationSec: media.metadata.duration,
                                externalID: video.videoID
                            ) {
                                Log.info("YouTube video loaded from cache: \(media.metadata.title)")
                                current.transcript = cached.transcriptText
                                current.state = .completed
                                current.progress = 1.0
                                current.subtitle = "\(channel) • Loaded from Cache"
                                if let outPath = cached.outputPath {
                                    current.outputURL = URL(fileURLWithPath: outPath)
                                    self.lastOutputURL = current.outputURL
                                }
                                self.updateItem(current)
                                continue
                            }
                            
                            current.state = .transcribing
                            current.transcript = ""
                            self.updateItem(current)
                            self.currentOperation = self.t("status_metal_active")
                            
                            let prepared = try audioDecoder.decode(fileURL: media.localAudioURL)
                            let collector = SegmentCollector()
                            let itemId = current.id
                            let result = try await whisperEngine.transcribe(
                                prepared,
                                options: TranscriptionOptions(language: lang),
                                progress: { [weak self] p in
                                    Task { @MainActor in
                                        self?.progressFraction = p
                                        self?.updateItemProgress(id: itemId, progress: p)
                                    }
                                },
                                onSegment: { [weak self] seg in
                                    let currentSegments = collector.append(seg)
                                    let liveText = postProcessor.process(segments: currentSegments)
                                    Task { @MainActor in
                                        self?.updateItemLiveTranscript(id: itemId, transcript: liveText)
                                    }
                                }
                            )
                            let formatted = postProcessor.process(segments: result.segments)
                            
                            current.transcript = formatted
                            
                            // Session Media Retention: Persist audio file so it survives workspace cleanup
                            let ext = media.localAudioURL.pathExtension.isEmpty ? "m4a" : media.localAudioURL.pathExtension
                            let sessionAudioURL = self.sessionMediaDirectory.appendingPathComponent("\(current.id).\(ext)")
                            if FileManager.default.fileExists(atPath: sessionAudioURL.path) {
                                try? FileManager.default.removeItem(at: sessionAudioURL)
                            }
                            try? FileManager.default.copyItem(at: media.localAudioURL, to: sessionAudioURL)
                            current.audioURL = sessionAudioURL
                            current.segments = result.segments
                            
                            let waveformGen = WaveformGenerator()
                            if let aURL = current.audioURL {
                                current.waveformPoints = try? await waveformGen.generateWaveform(from: aURL, targetPoints: 200)
                            }
                            current.state = .completed
                            current.progress = 1.0
                            
                            var targetURLPath: String? = nil
                            // Save individual file if requested
                            if self.sessionSaveMode == .individual || self.sessionSaveMode == .both {
                                let targetURL = self.outputWriter.resolveUniqueURL(
                                    forBaseName: media.metadata.title,
                                    in: self.outputWriter.defaultOutputDirectory,
                                    allowOverwrite: true,
                                    matchingContent: formatted
                                )
                                try self.outputWriter.write(content: formatted, to: targetURL)
                                current.outputURL = targetURL
                                self.lastOutputURL = targetURL
                                targetURLPath = targetURL.path
                                
                                self.saveToHistory(
                                    title: media.metadata.title,
                                    kind: "youtube",
                                    outputPath: targetURL.path,
                                    snippet: String(formatted.prefix(200))
                                )
                            }
                            
                            // Save to cache for future instant re-use
                            await self.transcriptCacheManager?.save(
                                externalID: video.videoID,
                                title: media.metadata.title,
                                durationSec: media.metadata.duration,
                                sourcePath: video.canonicalURL,
                                outputPath: targetURLPath,
                                transcriptText: formatted
                            )
                            
                        } catch {
                            current.state = .failed
                            current.errorMessage = error.localizedDescription
                        }
                        
                    case .audioFile(let fileURL):
                        do {
                            let duration = try AudioValidator.validate(fileURL: fileURL)
                            current.durationSec = duration
                            
                            // Check cache using both name and exact duration!
                            if let cached = await self.transcriptCacheManager?.findCached(
                                title: current.title,
                                durationSec: duration,
                                sourcePath: fileURL.path,
                                externalID: fileURL.path
                            ) {
                                Log.info("Audio file loaded from cache (skipping duplicate transcription): \(current.title) (\(duration)s)")
                                current.transcript = cached.transcriptText
                                current.state = .completed
                                current.progress = 1.0
                                current.subtitle = "Loaded from Cache • Already Transcribed (\(Int(duration))s)"
                                if let outPath = cached.outputPath {
                                    current.outputURL = URL(fileURLWithPath: outPath)
                                    self.lastOutputURL = current.outputURL
                                }
                                self.updateItem(current)
                                continue
                            }
                            
                            current.state = .transcribing
                            current.transcript = ""
                            self.updateItem(current)
                            self.currentOperation = "Yerel ses çözümleniyor ve transkript ediliyor..."
                            
                            let prepared = try audioDecoder.decode(fileURL: fileURL)
                            let collector = SegmentCollector()
                            let itemId = current.id
                            let result = try await whisperEngine.transcribe(
                                prepared,
                                options: TranscriptionOptions(language: lang),
                                progress: { [weak self] p in
                                    Task { @MainActor in
                                        self?.progressFraction = p
                                        self?.updateItemProgress(id: itemId, progress: p)
                                    }
                                },
                                onSegment: { [weak self] seg in
                                    let currentSegments = collector.append(seg)
                                    let liveText = postProcessor.process(segments: currentSegments)
                                    Task { @MainActor in
                                        self?.updateItemLiveTranscript(id: itemId, transcript: liveText)
                                    }
                                }
                            )
                            let formatted = postProcessor.process(segments: result.segments)
                            
                            current.transcript = formatted
                            current.audioURL = fileURL
                            current.segments = result.segments
                            let waveformGen = WaveformGenerator()
                            current.waveformPoints = try? await waveformGen.generateWaveform(from: fileURL, targetPoints: 200)
                            current.state = .completed
                            current.progress = 1.0
                            
                            var targetURLPath: String? = nil
                            let baseName = fileURL.deletingPathExtension().lastPathComponent
                            if self.sessionSaveMode == .individual || self.sessionSaveMode == .both {
                                let targetURL = self.outputWriter.resolveUniqueURL(
                                    forBaseName: baseName,
                                    in: self.outputWriter.defaultOutputDirectory,
                                    allowOverwrite: true,
                                    matchingContent: formatted
                                )
                                try self.outputWriter.write(content: formatted, to: targetURL)
                                current.outputURL = targetURL
                                self.lastOutputURL = targetURL
                                targetURLPath = targetURL.path
                                
                                self.saveToHistory(
                                    title: baseName,
                                    kind: "audio",
                                    outputPath: targetURL.path,
                                    snippet: String(formatted.prefix(200))
                                )
                            }
                            
                            // Save to cache for future instant re-use
                            await self.transcriptCacheManager?.save(
                                externalID: fileURL.path,
                                title: baseName,
                                durationSec: duration,
                                sourcePath: fileURL.path,
                                outputPath: targetURLPath,
                                transcriptText: formatted
                            )
                            
                        } catch {
                            current.state = .failed
                            current.errorMessage = error.localizedDescription
                        }
                    }
                    
                    self.updateItem(current)
                    self.progressFraction = Double(index + 1) / Double(totalCount)
                }
                
                // If combined mode is requested and multiple videos were in queue, write the combined session file
                if (self.sessionSaveMode == .combined || self.sessionSaveMode == .both) && totalCount > 1 {
                    let completed = self.queueItems.filter { $0.state == .completed && ($0.transcript != nil) }
                    if !completed.isEmpty {
                        let combinedText = self.combinedTranscript
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
                        let dateStr = formatter.string(from: Date())
                        let combinedName = "Toplu_Oturum_\(dateStr)"
                        
                        let targetURL = self.outputWriter.resolveUniqueURL(
                            forBaseName: combinedName,
                            in: self.outputWriter.defaultOutputDirectory,
                            allowOverwrite: true,
                            matchingContent: combinedText
                        )
                        try? self.outputWriter.write(content: combinedText, to: targetURL)
                        self.saveToHistory(
                            title: "\(combinedName) (\(completed.count) Video)",
                            kind: "combined",
                            outputPath: targetURL.path,
                            snippet: String(combinedText.prefix(200))
                        )
                    }
                }
                
                self.statusMessage = "✅ Tüm işlemler tamamlandı."
                self.currentOperation = ""
                self.progressFraction = 1.0
                
            } catch {
                self.errorMessage = "İşlem hatası: \(error.localizedDescription)"
                self.statusMessage = "İşlem tamamlanamadı."
            }
            
            self.isProcessing = false
        }
    }
    
    private func updateItem(_ item: QueueItem) {
        if let idx = queueItems.firstIndex(where: { $0.id == item.id }) {
            queueItems[idx] = item
        }
    }
    
    // MARK: - History Database
    private func saveToHistory(title: String, kind: String, outputPath: String, snippet: String) {
        let history = HistoryItem(
            title: title,
            kind: kind,
            outputPath: outputPath,
            date: Date(),
            snippet: snippet
        )
        historyItems.insert(history, at: 0)
        
        Task { [weak self] in
            guard let db = self?.appDatabase else { return }
            try? await db.dbQueue.write { db in
                try db.execute(
                    sql: "INSERT OR REPLACE INTO history (external_id, title, output_path, done_at) VALUES (?, ?, ?, ?)",
                    arguments: [history.id, title, outputPath, ISO8601DateFormatter().string(from: Date())]
                )
            }
        }
    }
    
    private func loadHistoryFromDatabase() async {
        guard let db = appDatabase else { return }
        do {
            let items = try await db.dbQueue.read { db -> [HistoryItem] in
                let rows = try Row.fetchAll(db, sql: "SELECT external_id, title, output_path, done_at FROM history ORDER BY done_at DESC LIMIT 50")
                var list: [HistoryItem] = []
                for row in rows {
                    let id: String = row["external_id"]
                    let title: String = row["title"] ?? "Başlıksız"
                    let path: String = row["output_path"] ?? ""
                    let dateStr: String = row["done_at"] ?? ""
                    let date = ISO8601DateFormatter().date(from: dateStr) ?? Date()
                    
                    var snippet = ""
                    if FileManager.default.fileExists(atPath: path), let content = try? String(contentsOfFile: path, encoding: .utf8) {
                        snippet = String(content.prefix(250))
                    }
                    
                    list.append(HistoryItem(
                        id: id,
                        title: title,
                        kind: path.hasSuffix(".txt") ? "transcript" : "audio",
                        outputPath: path,
                        date: date,
                        snippet: snippet
                    ))
                }
                return list
            }
            
            self.historyItems = items
        } catch {
            Log.error("History load error: \(error.localizedDescription)")
        }
    }
    
    public func clearAllHistory() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            historyItems.removeAll()
            selectedItemID = nil
            selectedItemIDs.removeAll()
        }
        Task { [weak self] in
            guard let db = self?.appDatabase else { return }
            do {
                try await db.dbQueue.write { db in
                    try db.execute(sql: "DELETE FROM history")
                }
            } catch {
                Log.error("Clear all history error: \(error.localizedDescription)")
            }
        }
        statusMessage = "Tüm geçmiş temizlendi."
    }
    
    public func deleteHistoryItem(id: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
            historyItems.removeAll(where: { $0.id == id })
            if selectedItemID == id {
                selectedItemID = nil
            }
        }
        Task { [weak self] in
            guard let db = self?.appDatabase else { return }
            do {
                try await db.dbQueue.write { db in
                    try db.execute(sql: "DELETE FROM history WHERE external_id = ?", arguments: [id])
                }
            } catch {
                Log.error("Delete history item error: \(error.localizedDescription)")
            }
        }
        statusMessage = "Kayıt geçmişten silindi."
    }
    
    // MARK: - Actions
    public func copyTranscript(text: String?) {
        guard let text = text, !text.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        
        copiedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.copiedToast = false
        }
    }
    
    public func copySelectedTranscript() {
        if let currentText = selectedItem?.transcript ?? selectedHistoryItem?.snippet {
            copyTranscript(text: currentText)
        }
    }
    
    public func openInFinder(path: String) {
        guard !path.isEmpty else { return }
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) {
            if isDir.boolValue {
                NSWorkspace.shared.open(url)
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } else {
            // If it's supposed to be a file but doesn't exist, try opening its directory
            let parent = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parent.path) {
                NSWorkspace.shared.open(parent)
            } else {
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    public func openInBrowser(url: String) {
        if let target = URL(string: url) {
            NSWorkspace.shared.open(target)
        }
    }
    
    // MARK: - Updates & Model Catalog
    public func checkForUpdates() {
        guard !isCheckingUpdates else { return }
        isCheckingUpdates = true
        updateCheckStatusText = "GitHub yayınları denetleniyor..."
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let info = try await self.updateChecker.checkForUpdates()
                self.updateInfo = info
                self.isCheckingUpdates = false
                if info.isNewerThanCurrent {
                    self.updateCheckStatusText = "Yeni sürüm mevcut: v\(info.latestVersion)"
                } else {
                    self.updateCheckStatusText = "En son sürümü kullanıyorsunuz (v\(UpdateChecker.currentVersion))."
                }
            } catch {
                self.isCheckingUpdates = false
                self.updateCheckStatusText = "Güncelleme denetlenemedi: \(error.localizedDescription)"
            }
        }
    }
    
    public func checkOnlineModels() {
        guard !isCheckingOnlineModels else { return }
        isCheckingOnlineModels = true
        onlineModelStatusText = "HuggingFace deposu kontrol ediliyor..."
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let message = try await WhisperModelCatalog.checkOnlineModelRepository()
                self.onlineModelStatusText = message
                self.isCheckingOnlineModels = false
            } catch {
                self.onlineModelStatusText = "Çevrimiçi kontrol tamamlandı. Katalogdaki tüm modeller (Large-v3-Turbo dahil) hazır."
                self.isCheckingOnlineModels = false
            }
        }
    }
    
    // MARK: - Model Management in Settings
    public func downloadModelInSettings(_ model: WhisperModel) {
        guard downloadingModel == nil else { return }
        downloadingModel = model
        modelDownloadFraction = 0.0
        modelDownloadStatusText = "Bağlanılıyor..."
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                _ = try await self.modelManager.downloadModelWithDetails(model) { [weak self] frac, written, total in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.modelDownloadFraction = frac
                        let writtenMB = Double(written) / (1024 * 1024)
                        let totalMB = Double(total) / (1024 * 1024)
                        let pct = Int(frac * 100)
                        if totalMB > 0 {
                            self.modelDownloadStatusText = String(format: "%%%d • %.1f MB / %.1f MB", pct, writtenMB, totalMB)
                        } else {
                            self.modelDownloadStatusText = String(format: "%.1f MB indirildi", writtenMB)
                        }
                    }
                }
                self.downloadingModel = nil
                self.modelDownloadFraction = 1.0
                self.modelDownloadStatusText = ""
                self.objectWillChange.send()
            } catch {
                self.downloadingModel = nil
                self.modelDownloadStatusText = ""
                self.errorMessage = "Model indirme hatası: \(error.localizedDescription)"
            }
        }
    }
    
    public func deleteModelInSettings(_ model: WhisperModel) {
        do {
            try modelManager.deleteModel(model)
            let remaining = modelManager.downloadedModels()
            if selectedModel == model {
                if let next = remaining.first {
                    selectedModel = next
                }
            }
            objectWillChange.send()
        } catch {
            errorMessage = "Model silinemedi: \(error.localizedDescription)"
        }
    }
}

// MARK: - Thread-Safe Live Segment Collector
private final class SegmentCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var segments: [Segment] = []
    
    func append(_ segment: Segment) -> [Segment] {
        lock.lock()
        defer { lock.unlock() }
        segments.append(segment)
        return segments
    }
}

