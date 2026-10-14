import Foundation
import SwiftUI
import AppKit
import TranskriptHubCore

public struct PreviewData: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let text: String
    public let fileURL: URL?
    
    public init(id: String = UUID().uuidString, title: String, text: String, fileURL: URL? = nil) {
        self.id = id
        self.title = title
        self.text = text
        self.fileURL = fileURL
    }
}

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public var sessionVideos: [ParsedYouTubeVideo] = []
    @Published public var localAudioFiles: [URL] = []
    @Published public var bulkText: String = ""
    @Published public var selectedLanguage: String = "auto"
    @Published public var selectedModel: WhisperModel = .tiny
    
    // Status per video ID: "queued", "fetching", "transcribing", "completed", "failed"
    @Published public var videoStatuses: [String: String] = [:]
    
    // Processing state
    @Published public var isProcessing: Bool = false
    @Published public var progressFraction: Double = 0.0
    @Published public var statusMessage: String = "Boşta"
    @Published public var currentJobProgress: String = ""
    @Published public var lastOutputURL: URL? = nil
    @Published public var errorMessage: String? = nil
    @Published public var copiedToast: Bool = false
    
    // Preview modal
    @Published public var previewData: PreviewData? = nil
    
    // Clipboard Monitor toggle
    @Published public var isClipboardMonitoring: Bool = false {
        didSet {
            if isClipboardMonitoring {
                clipboardMonitor.startMonitoring()
            } else {
                clipboardMonitor.stopMonitoring()
            }
        }
    }
    
    // Folder Watcher toggle
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
    private var jobManager: JobManager?
    private let outputWriter = OutputWriter()
    private let modelManager = ModelManager()
    
    public var watchedDirectoryPath: String {
        folderWatcher.watchedDirectory.path
    }
    
    public init() {
        self.clipboardMonitor = ClipboardMonitor { [weak self] video in
            self?.addVideo(video)
        }
        
        self.folderWatcher = FolderWatcher()
        self.folderWatcher.onNewAudioDiscovered = { [weak self] audioURL in
            await self?.processSingleLocalAudio(audioURL, showNotification: true)
        }
        
        Task {
            do {
                let db = try AppDatabase.makeShared()
                self.jobManager = JobManager(database: db)
                try await self.jobManager?.recoverState()
            } catch {
                self.errorMessage = "Veritabanı başlatılamadı: \(error.localizedDescription)"
            }
        }
    }
    
    // MARK: - Video Queue Management
    public func addVideo(_ video: ParsedYouTubeVideo) {
        guard !sessionVideos.contains(where: { $0.videoID == video.videoID }) else { return }
        sessionVideos.append(video)
        videoStatuses[video.videoID] = "queued"
    }
    
    public func addBulkPastedText() {
        guard !bulkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let parsed = URLParser.parseBulk(bulkText)
        for p in parsed {
            addVideo(p)
        }
        bulkText = ""
    }
    
    public func addFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        let parsed = URLParser.parseBulk(text)
        for p in parsed {
            addVideo(p)
        }
    }
    
    public func addSampleLink() {
        let sample = "https://www.youtube.com/watch?v=jNQXAC9IVRw"
        if let parsed = URLParser.parseSingle(sample) {
            addVideo(parsed)
        }
    }
    
    public func removeVideo(at offsets: IndexSet) {
        let idsToRemove = offsets.map { sessionVideos[$0].videoID }
        sessionVideos.remove(atOffsets: offsets)
        for id in idsToRemove {
            videoStatuses.removeValue(forKey: id)
        }
    }
    
    public func removeVideo(id: String) {
        sessionVideos.removeAll(where: { $0.videoID == id })
        videoStatuses.removeValue(forKey: id)
    }
    
    public func clearAllVideos() {
        sessionVideos.removeAll()
        videoStatuses.removeAll()
    }
    
    // MARK: - Local Audio Files Management
    public func addLocalFiles(_ urls: [URL]) {
        for url in urls {
            if !localAudioFiles.contains(url) && AudioValidator.isExtensionSupported(url.pathExtension) {
                localAudioFiles.append(url)
            }
        }
    }
    
    public func removeLocalFile(at offsets: IndexSet) {
        localAudioFiles.remove(atOffsets: offsets)
    }
    
    public func removeLocalFile(_ url: URL) {
        localAudioFiles.removeAll(where: { $0 == url })
    }
    
    public func clearAllLocalFiles() {
        localAudioFiles.removeAll()
    }
    
    // MARK: - Helpers & Actions
    public func openInBrowser(url: String) {
        if let target = URL(string: url) {
            NSWorkspace.shared.open(target)
        }
    }
    
    public func copyTranscriptToClipboard() {
        guard let url = lastOutputURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        
        copiedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.copiedToast = false
        }
    }
    
    public func showPreview() {
        guard let url = lastOutputURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        previewData = PreviewData(
            title: url.deletingPathExtension().lastPathComponent,
            text: text,
            fileURL: url
        )
    }
    
    // MARK: - Batch YouTube Transcription
    public func startBatchTranscription() {
        guard !sessionVideos.isEmpty else { return }
        guard let manager = jobManager else {
            errorMessage = "İş yöneticisi hazır değil."
            return
        }
        
        isProcessing = true
        progressFraction = 0.05
        statusMessage = "İşlem başlatılıyor..."
        errorMessage = nil
        lastOutputURL = nil
        
        let urls = sessionVideos.map(\.canonicalURL)
        let totalCount = urls.count
        let lang = selectedLanguage == "auto" ? nil : selectedLanguage
        let model = selectedModel
        
        for v in sessionVideos {
            videoStatuses[v.videoID] = "queued"
        }
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let batch = try await manager.createYouTubeBatch(urls: urls, language: lang)
                self.statusMessage = "İşleniyor (Toplam: \(totalCount) Video)"
                
                let result = try await manager.processBatch(batchID: batch.id, model: model) { [weak self] job in
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        let title = job.title ?? job.externalID ?? "Bilinmiyor"
                        self.currentJobProgress = "[\(job.sequence)/\(totalCount)] \(title): \(job.state.uppercased())"
                        
                        if let extID = job.externalID {
                            self.videoStatuses[extID] = job.state
                        }
                        
                        let finishedCount = self.videoStatuses.values.filter { $0 == "completed" || $0 == "failed" }.count
                        self.progressFraction = min(0.95, Double(finishedCount) / Double(totalCount))
                    }
                }
                
                self.progressFraction = 1.0
                switch result {
                case .assembled(let outputURL, let isPartial):
                    self.lastOutputURL = outputURL
                    self.statusMessage = isPartial ? "⚠️ Kısmi Tamamlandı (Bazı videolar hariç toplandı)" : "✅ Eksiksiz Tamamlandı"
                    self.currentJobProgress = "\(outputURL.lastPathComponent) kaydedildi."
                    self.clearAllVideos()
                case .waiting(let pending):
                    self.statusMessage = "Bekliyor (\(pending) video)"
                case .empty:
                    self.statusMessage = "Sonuç bulunamadı."
                }
                
            } catch {
                self.errorMessage = "Hata: \(error.localizedDescription)"
                self.statusMessage = "İşlem başarısız oldu."
            }
            
            self.isProcessing = false
        }
    }
    
    // MARK: - Local Audio Files Transcription
    public func startLocalAudioTranscription() {
        guard !localAudioFiles.isEmpty else { return }
        
        isProcessing = true
        progressFraction = 0.05
        statusMessage = "Yerel ses dosyaları hazırlanıyor..."
        errorMessage = nil
        lastOutputURL = nil
        
        let files = localAudioFiles
        let model = selectedModel
        let lang = selectedLanguage == "auto" ? nil : selectedLanguage
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
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
                
                var lastURL: URL? = nil
                let total = files.count
                
                for (index, fileURL) in files.enumerated() {
                    let filename = fileURL.lastPathComponent
                    self.statusMessage = "[\(index + 1)/\(total)] \(filename) işleniyor..."
                    self.currentJobProgress = "Ses çözümleniyor ve GPU Metal ile yazıya aktarılıyor..."
                    
                    // Validate
                    _ = try AudioValidator.validate(fileURL: fileURL)
                    
                    // Decode to 16 kHz Float32 PCM
                    let prepared = try audioDecoder.decode(fileURL: fileURL)
                    
                    // Transcribe via Whisper
                    let options = TranscriptionOptions(language: lang)
                    let result = try await whisperEngine.transcribe(prepared, options: options)
                    
                    // Post-process
                    let formatted = postProcessor.process(segments: result.segments)
                    
                    // Write output TXT
                    let baseName = fileURL.deletingPathExtension().lastPathComponent
                    let targetURL = self.outputWriter.resolveUniqueURL(
                        forBaseName: baseName,
                        in: self.outputWriter.defaultOutputDirectory
                    )
                    try self.outputWriter.write(content: formatted, to: targetURL)
                    lastURL = targetURL
                    
                    self.progressFraction = Double(index + 1) / Double(total)
                }
                
                self.lastOutputURL = lastURL
                self.progressFraction = 1.0
                self.statusMessage = "✅ \(total) adet ses dosyası başarıyla transkript edildi!"
                self.currentJobProgress = lastURL != nil ? "\(lastURL!.lastPathComponent) kaydedildi." : ""
                self.clearAllLocalFiles()
                
            } catch {
                self.errorMessage = "Ses transkript hatası: \(error.localizedDescription)"
                self.statusMessage = "İşlem başarısız oldu."
            }
            
            self.isProcessing = false
        }
    }
    
    // Process single audio file (e.g. from folder watcher)
    private func processSingleLocalAudio(_ fileURL: URL, showNotification: Bool = false) async {
        do {
            let model = selectedModel
            let modelURL: URL
            if !modelManager.isModelDownloaded(model) {
                modelURL = try await modelManager.downloadModel(model)
            } else {
                modelURL = modelManager.localURL(for: model)
            }
            
            let whisperEngine = try WhisperCppEngine(modelPath: modelURL.path)
            let audioDecoder = AudioDecoder()
            let postProcessor = TranscriptPostProcessor()
            
            _ = try AudioValidator.validate(fileURL: fileURL)
            let prepared = try audioDecoder.decode(fileURL: fileURL)
            let options = TranscriptionOptions(language: selectedLanguage == "auto" ? nil : selectedLanguage)
            let result = try await whisperEngine.transcribe(prepared, options: options)
            let formatted = postProcessor.process(segments: result.segments)
            
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            let targetURL = outputWriter.resolveUniqueURL(forBaseName: baseName, in: outputWriter.defaultOutputDirectory)
            try outputWriter.write(content: formatted, to: targetURL)
            
            self.lastOutputURL = targetURL
            self.statusMessage = "✅ Otomatik transkript tamamlandı: \(targetURL.lastPathComponent)"
        } catch {
            Log.error("Klasör izleme transkripsiyon hatası: \(error.localizedDescription)")
        }
    }
}
