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
    
    @Published public var activeCloudDownloads: Set<String> = [] // Filenames currently being downloaded from iCloud
    
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
        Log.info("FolderWatcher started: \(watchedDirectory.path)")
    }
    
    public func stopWatching() {
        isWatching = false
        timer?.invalidate()
        timer = nil
        Log.info("FolderWatcher stopped.")
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
    
    public func forceDownloadAllCloudItems() async {
        await scanDirectory()
    }
    
    private func scanSingleDirectory(_ directory: URL) async {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        
        // DO NOT skip hidden files, because iCloud Drive placeholders start with '.' (e.g. .ses_kaydi.m4a.icloud)
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey
            ],
            options: []
        ) else { return }
        
        for fileURL in items {
            let filename = fileURL.lastPathComponent
            
            // Exclude system meta files
            if filename == ".DS_Store" || filename.hasPrefix("._") || filename == "." || filename == ".." {
                continue
            }
            
            // 1. Check for iCloud Drive placeholder files (.something.m4a.icloud)
            if filename.hasSuffix(".icloud") {
                var baseName = filename
                if baseName.hasPrefix(".") {
                    baseName = String(baseName.dropFirst())
                }
                if baseName.hasSuffix(".icloud") {
                    baseName = String(baseName.dropLast(".icloud".count))
                }
                
                let candidateExt = (baseName as NSString).pathExtension.lowercased()
                guard AudioValidator.isExtensionSupported(candidateExt) else {
                    continue
                }
                
                // Automatically force iCloud to start downloading this audio file to the local disk
                do {
                    try fm.startDownloadingUbiquitousItem(at: fileURL)
                } catch {
                    let targetURL = directory.appendingPathComponent(baseName)
                    try? fm.startDownloadingUbiquitousItem(at: targetURL)
                }
                
                activeCloudDownloads.insert(baseName)
                continue
            }
            
            // 2. Check for ubiquitous item whose download is pending locally
            if let res = try? fileURL.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey
            ]), let status = res.ubiquitousItemDownloadingStatus {
                if status == .notDownloaded {
                    try? fm.startDownloadingUbiquitousItem(at: fileURL)
                    activeCloudDownloads.insert(filename)
                    Log.info("iCloud file not yet downloaded locally, initiated automatic download: \(filename)")
                    continue
                } else if status != .current && status != .downloaded {
                    activeCloudDownloads.insert(filename)
                    continue
                }
            }
            
            // 3. Regular exclusions (non-icloud hidden files and incomplete browser downloads)
            if filename.hasPrefix(".") || filename.hasSuffix(".part") || filename.hasSuffix(".download") {
                continue
            }
            
            let ext = fileURL.pathExtension.lowercased()
            guard AudioValidator.isExtensionSupported(ext) else { continue }
            
            // File is locally present and downloaded! Remove from active downloads
            activeCloudDownloads.remove(filename)
            
            let path = fileURL.path
            guard !processedPaths.contains(path) else { continue }
            
            // 4. Size stability check (2 measurements, > 0)
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
                        
                        Log.info("New audio file detected: \(filename)")
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
