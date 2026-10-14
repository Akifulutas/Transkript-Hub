import Foundation
import SwiftUI
import TranskriptHubCore

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public var sessionVideos: [ParsedYouTubeVideo] = []
    @Published public var localAudioFiles: [URL] = []
    @Published public var bulkText: String = ""
    @Published public var selectedLanguage: String = "auto"
    @Published public var selectedModel: WhisperModel = .tiny
    
    // Processing state
    @Published public var isProcessing: Bool = false
    @Published public var statusMessage: String = "Boşta"
    @Published public var currentJobProgress: String = ""
    @Published public var lastOutputURL: URL? = nil
    @Published public var errorMessage: String? = nil
    
    @Published public var isClipboardMonitoring: Bool = false {
        didSet {
            if isClipboardMonitoring {
                clipboardMonitor.startMonitoring()
            } else {
                clipboardMonitor.stopMonitoring()
            }
        }
    }
    
    public private(set) var clipboardMonitor: ClipboardMonitor!
    private var jobManager: JobManager?
    
    public init() {
        self.clipboardMonitor = ClipboardMonitor { [weak self] video in
            self?.addVideo(video)
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
    
    public func addVideo(_ video: ParsedYouTubeVideo) {
        guard !sessionVideos.contains(where: { $0.videoID == video.videoID }) else { return }
        sessionVideos.append(video)
    }
    
    public func addBulkPastedText() {
        guard !bulkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let parsed = URLParser.parseBulk(bulkText)
        for p in parsed {
            addVideo(p)
        }
        bulkText = ""
    }
    
    public func removeVideo(at offsets: IndexSet) {
        sessionVideos.remove(atOffsets: offsets)
    }
    
    public func removeVideo(id: String) {
        sessionVideos.removeAll(where: { $0.videoID == id })
    }
    
    public func clearAllVideos() {
        sessionVideos.removeAll()
    }
    
    public func addLocalFiles(_ urls: [URL]) {
        for url in urls {
            if !localAudioFiles.contains(url) {
                localAudioFiles.append(url)
            }
        }
    }
    
    public func removeLocalFile(at offsets: IndexSet) {
        localAudioFiles.remove(atOffsets: offsets)
    }
    
    public func clearAllLocalFiles() {
        localAudioFiles.removeAll()
    }
    
    public func startBatchTranscription() {
        guard !sessionVideos.isEmpty else { return }
        guard let manager = jobManager else {
            errorMessage = "İş yöneticisi hazır değil."
            return
        }
        
        isProcessing = true
        statusMessage = "İşlem başlatılıyor..."
        errorMessage = nil
        lastOutputURL = nil
        
        let urls = sessionVideos.map(\.canonicalURL)
        let lang = selectedLanguage == "auto" ? nil : selectedLanguage
        let model = selectedModel
        
        Task { [weak self] in
            guard let self = self else { return }
            do {
                let batch = try await manager.createYouTubeBatch(urls: urls, language: lang)
                self.statusMessage = "İşleniyor (Toplam: \(urls.count) Video)"
                
                let result = try await manager.processBatch(batchID: batch.id, model: model) { [weak self] job in
                    Task { @MainActor [weak self] in
                        let title = job.title ?? job.externalID ?? "Bilinmiyor"
                        self?.currentJobProgress = "[\(job.sequence)/\(urls.count)] \(title): \(job.state.uppercased())"
                    }
                }
                
                switch result {
                case .assembled(let outputURL, let isPartial):
                    self.lastOutputURL = outputURL
                    self.statusMessage = isPartial ? "⚠️ Kısmi Tamamlandı (Eksik videolar raporda belirtildi)" : "✅ Eksiksiz Tamamlandı"
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
}
