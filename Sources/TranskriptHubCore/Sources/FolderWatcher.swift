import Foundation

@MainActor
public final class FolderWatcher: ObservableObject {
    @Published public var isWatching: Bool = false
    @Published public var watchedDirectory: URL
    @Published public var processedFilesCount: Int = 0
    @Published public var lastProcessedFile: String? = nil
    
    private var timer: Timer?
    private var knownFiles: [String: Int64] = [:] // Path -> size
    private var processedPaths: Set<String> = []
    
    public var onNewAudioDiscovered: ((URL) async -> Void)?
    
    public init(watchedDirectory: URL? = nil) {
        if let dir = watchedDirectory {
            self.watchedDirectory = dir
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Transkript", isDirectory: true)
            self.watchedDirectory = iCloud
        }
        
        let saved = UserDefaults.standard.stringArray(forKey: "FolderWatcher.processedPaths") ?? []
        self.processedPaths = Set(saved)
    }
    
    public func startWatching() {
        guard !isWatching else { return }
        isWatching = true
        
        // Scan immediately
        Task {
            await scanDirectory()
        }
        
        // Periodic check every 3.0 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.scanDirectory()
            }
        }
        Log.info("FolderWatcher başlatıldı: \(watchedDirectory.path)")
    }
    
    public func stopWatching() {
        isWatching = false
        timer?.invalidate()
        timer = nil
        Log.info("FolderWatcher durduruldu.")
    }
    
    public var voiceMemosDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings", isDirectory: true)
    }
    
    public var isVoiceMemosDirectlyAccessible: Bool {
        FileManager.default.fileExists(atPath: voiceMemosDirectory.path) &&
        FileManager.default.isReadableFile(atPath: voiceMemosDirectory.path)
    }
    
    public func scanDirectory() async {
        var directoriesToScan = [watchedDirectory]
        if isVoiceMemosDirectlyAccessible {
            directoriesToScan.append(voiceMemosDirectory)
        }
        
        for dir in directoriesToScan {
            await scanSingleDirectory(dir)
        }
    }
    
    private func scanSingleDirectory(_ directory: URL) async {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .ubiquitousItemDownloadingStatusKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        
        for fileURL in items {
            let filename = fileURL.lastPathComponent
            
            // 1. Check extensions & exclusions
            if filename.hasPrefix(".") || filename.hasSuffix(".part") || filename.hasSuffix(".download") {
                continue
            }
            
            // iCloud dataless handling
            if filename.hasSuffix(".icloud") {
                try? fm.startDownloadingUbiquitousItem(at: fileURL)
                continue
            }
            
            let ext = fileURL.pathExtension.lowercased()
            guard AudioValidator.isExtensionSupported(ext) else { continue }
            
            let path = fileURL.path
            guard !processedPaths.contains(path) else { continue }
            
            // 2. Size stability check (2 measurements, > 0)
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let currentSize = attrs[.size] as? Int64,
                  currentSize > 0 else { continue }
            
            if let previousSize = knownFiles[path] {
                if previousSize == currentSize {
                    // Size is stable! Validate audio
                    if let _ = try? AudioValidator.validate(fileURL: fileURL) {
                        processedPaths.insert(path)
                        UserDefaults.standard.set(Array(processedPaths), forKey: "FolderWatcher.processedPaths")
                        knownFiles.removeValue(forKey: path)
                        processedFilesCount += 1
                        lastProcessedFile = filename
                        
                        Log.info("Yeni ses dosyası algılandı: \(filename)")
                        await onNewAudioDiscovered?(fileURL)
                    }
                } else {
                    knownFiles[path] = currentSize
                }
            } else {
                knownFiles[path] = currentSize
            }
        }
    }
}
