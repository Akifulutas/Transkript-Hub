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

@MainActor
public final class AppViewModel: ObservableObject {
    // Navigation & Selection
    @Published public var selectedSection: SidebarSection = .queue
    @Published public var selectedItemID: String? = nil
    @Published public var searchQuery: String = ""
    @Published public var transcriptFontSize: Double = 13.0
    
    // Unified Active Queue (YouTube links & local audio files)
    @Published public var queueItems: [QueueItem] = []
    @Published public var historyItems: [HistoryItem] = []
    
    // Quick Add Inputs
    @Published public var quickInputText: String = ""
    @Published public var isDropTargetActive: Bool = false
    
    // Model & Language Selection
    @Published public var selectedModel: WhisperModel = .tiny
    @Published public var selectedLanguage: String = "auto"
    
    // Processing & Progress
    @Published public var isProcessing: Bool = false
    @Published public var progressFraction: Double = 0.0
    @Published public var statusMessage: String = "Hazır"
    @Published public var currentOperation: String = ""
    @Published public var lastOutputURL: URL? = nil
    @Published public var errorMessage: String? = nil
    @Published public var copiedToast: Bool = false
    
    // System Monitors
    @Published public var isClipboardMonitoring: Bool = false {
        didSet {
            if isClipboardMonitoring {
                clipboardMonitor.startMonitoring()
            } else {
                clipboardMonitor.stopMonitoring()
            }
        }
    }
    
    @Published public var isFolderWatching: Bool = false {
        didSet {
            if isFolderWatching {
                folderWatcher.startWatching()
            } else {
                folderWatcher.stopWatching()
            }
        }
    }
    
    public private(set) var clipboardMonitor: ClipboardMonitor!
    public private(set) var folderWatcher: FolderWatcher!
    public let modelManager = ModelManager()
    public let outputWriter = OutputWriter()
    private var jobManager: JobManager?
    private var appDatabase: AppDatabase?
    
    public var watchedDirectoryPath: String {
        folderWatcher.watchedDirectory.path
    }
    
    public var selectedItem: QueueItem? {
        guard let id = selectedItemID else { return queueItems.first }
        return queueItems.first(where: { $0.id == id })
    }
    
    public var selectedHistoryItem: HistoryItem? {
        guard let id = selectedItemID else { return historyItems.first }
        return historyItems.first(where: { $0.id == id })
    }
    
    public init() {
        self.clipboardMonitor = ClipboardMonitor { [weak self] video in
            self?.addYouTubeVideo(video)
        }
        
        self.folderWatcher = FolderWatcher()
        self.folderWatcher.onNewAudioDiscovered = { [weak self] audioURL in
            await self?.handleAutoDiscoveredAudio(audioURL)
        }
        
        Task {
            do {
                let db = try AppDatabase.makeShared()
                self.appDatabase = db
                self.jobManager = JobManager(database: db, outputWriter: self.outputWriter)
                try await self.jobManager?.recoverState()
                await self.loadHistoryFromDatabase()
            } catch {
                self.errorMessage = "Veritabanı başlatılamadı: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Queue Management
    public func addYouTubeVideo(_ video: ParsedYouTubeVideo) {
        guard !queueItems.contains(where: { $0.id == video.videoID }) else { return }
        let item = QueueItem(
            id: video.videoID,
            kind: .youtube(video),
            title: video.canonicalURL,
            subtitle: "YouTube • ID: \(video.videoID)",
            state: .queued
        )
        queueItems.append(item)
        if selectedItemID == nil {
            selectedItemID = item.id
        }
    }
    
    public func addAudioFiles(_ urls: [URL]) {
        for url in urls {
            guard AudioValidator.isExtensionSupported(url.pathExtension) else { continue }
            guard !queueItems.contains(where: { $0.id == url.path }) else { continue }
            
            let item = QueueItem(
                id: url.path,
                kind: .audioFile(url),
                title: url.deletingPathExtension().lastPathComponent,
                subtitle: "Ses Dosyası • \(url.pathExtension.uppercased())",
                state: .queued
            )
            queueItems.append(item)
            if selectedItemID == nil {
                selectedItemID = item.id
            }
        }
    }
    
    public func addFromQuickInput() {
        let trimmed = quickInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let parsedList = URLParser.parseBulk(trimmed)
        if !parsedList.isEmpty {
            for p in parsedList {
                addYouTubeVideo(p)
            }
        } else {
            // Check if it's a file path
            let fileURL = URL(fileURLWithPath: trimmed)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                addAudioFiles([fileURL])
            }
        }
        quickInputText = ""
    }
    
    public func addFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let parsed = URLParser.parseBulk(text)
        for p in parsed {
            addYouTubeVideo(p)
        }
    }
    
    public func addSampleYouTube() {
        if let sample = URLParser.parseSingle("https://www.youtube.com/watch?v=jNQXAC9IVRw") {
            addYouTubeVideo(sample)
        }
    }
    
    public func removeItem(id: String) {
        queueItems.removeAll(where: { $0.id == id })
        if selectedItemID == id {
            selectedItemID = queueItems.first?.id
        }
    }
    
    public func clearQueue() {
        queueItems.removeAll()
        selectedItemID = nil
    }
    
    // MARK: - Unified Batch & Audio Processing
    public func startProcessingQueue() {
        guard !queueItems.isEmpty else { return }
        
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
                    self.statusMessage = "Whisper modeli indiriliyor (\(model.filename))..."
                    modelURL = try await self.modelManager.downloadModel(model)
                } else {
                    modelURL = self.modelManager.localURL(for: model)
                }
                
                let whisperEngine = try WhisperCppEngine(modelPath: modelURL.path)
                let audioDecoder = AudioDecoder()
                let postProcessor = TranscriptPostProcessor()
                let toolMgr = ToolManager()
                try await toolMgr.ensureToolsReady()
                let ytdlp = YTDLPClient(toolManager: toolMgr)
                
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }
                
                for (index, item) in self.queueItems.enumerated() {
                    self.statusMessage = "[\(index + 1)/\(totalCount)] \(item.title) işleniyor..."
                    self.selectedItemID = item.id
                    
                    var current = item
                    
                    switch item.kind {
                    case .youtube(let video):
                        current.state = .fetching
                        self.updateItem(current)
                        self.currentOperation = "YouTube sesi indiriliyor (yt-dlp)..."
                        
                        do {
                            let media = try await ytdlp.fetch(url: video.canonicalURL, into: tempDir)
                            let channel = media.metadata.channel ?? "YouTube"
                            let duration = media.metadata.duration ?? 0
                            current.title = media.metadata.title
                            current.subtitle = "\(channel) • \(Int(duration)) sn"
                            current.durationSec = media.metadata.duration
                            
                            current.state = .transcribing
                            self.updateItem(current)
                            self.currentOperation = "Apple Silicon GPU Metal ile transkript ediliyor..."
                            
                            let prepared = try audioDecoder.decode(fileURL: media.localAudioURL)
                            let result = try await whisperEngine.transcribe(prepared, options: TranscriptionOptions(language: lang))
                            let formatted = postProcessor.process(segments: result.segments)
                            
                            current.transcript = formatted
                            current.state = .completed
                            current.progress = 1.0
                            
                            // Save file
                            let targetURL = self.outputWriter.resolveUniqueURL(
                                forBaseName: media.metadata.title,
                                in: self.outputWriter.defaultOutputDirectory
                            )
                            try self.outputWriter.write(content: formatted, to: targetURL)
                            current.outputURL = targetURL
                            self.lastOutputURL = targetURL
                            
                            self.saveToHistory(
                                title: media.metadata.title,
                                kind: "youtube",
                                outputPath: targetURL.path,
                                snippet: String(formatted.prefix(200))
                            )
                            
                        } catch {
                            current.state = .failed
                            current.errorMessage = error.localizedDescription
                        }
                        
                    case .audioFile(let fileURL):
                        current.state = .transcribing
                        self.updateItem(current)
                        self.currentOperation = "Yerel ses çözümleniyor ve transkript ediliyor..."
                        
                        do {
                            _ = try AudioValidator.validate(fileURL: fileURL)
                            let prepared = try audioDecoder.decode(fileURL: fileURL)
                            let result = try await whisperEngine.transcribe(prepared, options: TranscriptionOptions(language: lang))
                            let formatted = postProcessor.process(segments: result.segments)
                            
                            current.transcript = formatted
                            current.state = .completed
                            current.progress = 1.0
                            
                            let baseName = fileURL.deletingPathExtension().lastPathComponent
                            let targetURL = self.outputWriter.resolveUniqueURL(
                                forBaseName: baseName,
                                in: self.outputWriter.defaultOutputDirectory
                            )
                            try self.outputWriter.write(content: formatted, to: targetURL)
                            current.outputURL = targetURL
                            self.lastOutputURL = targetURL
                            
                            self.saveToHistory(
                                title: baseName,
                                kind: "audio",
                                outputPath: targetURL.path,
                                snippet: String(formatted.prefix(200))
                            )
                            
                        } catch {
                            current.state = .failed
                            current.errorMessage = error.localizedDescription
                        }
                    }
                    
                    self.updateItem(current)
                    self.progressFraction = Double(index + 1) / Double(totalCount)
                }
                
                self.statusMessage = "✅ Tüm işlemler tamamlandı."
                self.currentOperation = ""
                self.progressFraction = 1.0
                
            } catch {
                self.errorMessage = "İşlem hatası: \(error.localizedDescription)"
                self.statusMessage = "İşlem başarısız oldu."
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
            Log.error("Geçmiş yükleme hatası: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Auto Discovered Audio (Watched Folder)
    private func handleAutoDiscoveredAudio(_ url: URL) async {
        addAudioFiles([url])
        startProcessingQueue()
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
    
    public func openInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    
    public func openInBrowser(url: String) {
        if let target = URL(string: url) {
            NSWorkspace.shared.open(target)
        }
    }
}
