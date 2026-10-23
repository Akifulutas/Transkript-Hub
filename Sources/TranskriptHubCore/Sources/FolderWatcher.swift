import Foundation

@MainActor
public final class FolderWatcher: ObservableObject {
    @Published public var isWatching: Bool = false
    @Published public var watchedDirectory: URL
    @Published public var processedFilesCount: Int = 0
    @Published public var lastProcessedFile: String? = nil
    
    // Configurable Sources
    @Published public var watchiCloudDrive: Bool {
        didSet {
            UserDefaults.standard.set(watchiCloudDrive, forKey: "FolderWatcher.watchiCloudDrive")
            if watchiCloudDrive {
                resetProcessedPaths(under: Self.iCloudRootDirectory)
            }
            triggerImmediateScan()
        }
    }
    
    @Published public var watchiCloudRoot: Bool {
        didSet {
            UserDefaults.standard.set(watchiCloudRoot, forKey: "FolderWatcher.watchiCloudRoot")
            if watchiCloudRoot {
                resetProcessedPaths(under: Self.iCloudRootDirectory)
            }
            triggerImmediateScan()
        }
    }
    
    @Published public var watchVoiceMemos: Bool {
        didSet {
            UserDefaults.standard.set(watchVoiceMemos, forKey: "FolderWatcher.watchVoiceMemos")
            if watchVoiceMemos {
                resetProcessedPaths(under: Self.voiceMemosDirectory)
            }
            triggerImmediateScan()
        }
    }
    
    @Published public var watchCustomFolder: Bool {
        didSet {
            // Cannot watch custom folder if no valid custom folders are configured
            if watchCustomFolder && customFolderURLs.isEmpty {
                watchCustomFolder = false
                return
            }
            UserDefaults.standard.set(watchCustomFolder, forKey: "FolderWatcher.watchCustomFolder")
            if watchCustomFolder {
                for url in customFolderURLs {
                    resetProcessedPaths(under: url)
                }
            }
            triggerImmediateScan()
        }
    }
    
    @Published public var customFolderURLs: [URL] {
        didSet {
            let paths = customFolderURLs.map(\.path)
            UserDefaults.standard.set(paths, forKey: "FolderWatcher.customFolderPaths")
            UserDefaults.standard.set(customFolderURLs.first?.path, forKey: "FolderWatcher.customFolderPath")
            for url in customFolderURLs {
                resetProcessedPaths(under: url)
            }
            if customFolderURLs.isEmpty {
                watchCustomFolder = false
            } else if !watchCustomFolder {
                watchCustomFolder = true
            }
            triggerImmediateScan()
        }
    }
    
    public var customFolderURL: URL? {
        get { customFolderURLs.first }
        set {
            if let val = newValue {
                if !customFolderURLs.contains(where: { $0.path == val.path }) {
                    customFolderURLs = [val]
                }
            } else {
                customFolderURLs = []
            }
        }
    }
    
    public func addCustomFolder(_ url: URL) {
        guard !customFolderURLs.contains(where: { $0.path == url.path }) else { return }
        customFolderURLs.append(url)
        if !watchCustomFolder {
            watchCustomFolder = true
        }
    }
    
    public func removeCustomFolder(_ url: URL) {
        customFolderURLs.removeAll(where: { $0.path == url.path })
        if customFolderURLs.isEmpty {
            watchCustomFolder = false
        }
    }
    
    /// Whether newly discovered audio files in watched folders should be transcribed immediately
    /// without waiting for the user to manually start the queue. Defaults to true.
    @Published public var autoTranscribe: Bool {
        didSet {
            UserDefaults.standard.set(autoTranscribe, forKey: "FolderWatcher.autoTranscribe")
            onAutoTranscribeChanged?(autoTranscribe)
        }
    }
    
    private var timer: Timer?
    private var followUpScanTask: Task<Void, Never>?
    private var knownFiles: [String: Int64] = [:] // Path -> size
    private var processedPaths: Set<String> = []
    private var dismissedPaths: Set<String> = []
    
    @Published public var activeCloudDownloads: Set<String> = [] // Filenames currently being downloaded from iCloud
    
    public var onNewAudioDiscovered: (@MainActor (URL) async -> Void)?
    public var onAutoTranscribeChanged: (@MainActor (Bool) -> Void)?
    
    public static var iCloudRootDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }
    
    public static var iCloudTranskriptDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Transkript", isDirectory: true)
    }
    
    public static var voiceMemosDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings", isDirectory: true)
    }
    
    public var isICloudDriveAvailable: Bool {
        let path = Self.iCloudRootDirectory.path
        guard FileManager.default.fileExists(atPath: path) else { return false }
        if let dir = opendir(path) {
            closedir(dir)
            return true
        }
        return false
    }
    
    public var isICloudTranskriptFolderReady: Bool {
        let path = Self.iCloudTranskriptDirectory.path
        return FileManager.default.fileExists(atPath: path)
    }
    
    @discardableResult
    public func setupICloudTranskriptFolder() throws -> URL {
        let dir = Self.iCloudTranskriptDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    public func existingVoiceMemosFiles() -> [URL] {
        guard isVoiceMemosDirectlyAccessible else { return [] }
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: Self.voiceMemosDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return items.filter { AudioValidator.isExtensionSupported($0.pathExtension) && !isPathDismissed($0.path) }
            .sorted { (u1, u2) -> Bool in
                let d1 = (try? u1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let d2 = (try? u2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return d1 > d2
            }
    }
    
    public func markPathsAsProcessed(_ paths: [String]) {
        for path in paths {
            processedPaths.insert(path)
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
            processedPaths.insert(resolved)
        }
        persistProcessedPaths()
    }
    
    public func isPathProcessed(_ path: String) -> Bool {
        if processedPaths.contains(path) { return true }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        return processedPaths.contains(resolved)
    }

    public func markPathsAsDismissed(_ paths: [String]) {
        for path in paths {
            dismissedPaths.insert(path)
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
            dismissedPaths.insert(resolved)
            processedPaths.insert(path)
            processedPaths.insert(resolved)
        }
        persistDismissedPaths()
        persistProcessedPaths()
    }

    public func unmarkPathsAsDismissed(_ paths: [String]) {
        for path in paths {
            dismissedPaths.remove(path)
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
            dismissedPaths.remove(resolved)
        }
        persistDismissedPaths()
    }

    public func isPathDismissed(_ path: String) -> Bool {
        if dismissedPaths.contains(path) { return true }
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
        return dismissedPaths.contains(resolved)
    }

    private func persistProcessedPaths() {
        if processedPaths.count > 5000 {
            let trimmed = Array(processedPaths.suffix(3000))
            processedPaths = Set(trimmed)
        }
        UserDefaults.standard.set(Array(processedPaths), forKey: "FolderWatcher.processedPaths")
    }

    private func persistDismissedPaths() {
        if dismissedPaths.count > 5000 {
            let trimmed = Array(dismissedPaths.suffix(3000))
            dismissedPaths = Set(trimmed)
        }
        UserDefaults.standard.set(Array(dismissedPaths), forKey: "FolderWatcher.dismissedPaths")
    }

    public var isVoiceMemosDirectlyAccessible: Bool {
        let path = Self.voiceMemosDirectory.path
        guard FileManager.default.fileExists(atPath: path) else { return false }
        if let dir = opendir(path) {
            closedir(dir)
            return true
        }
        return false
    }
    
    public var activeWatchedDirectories: [URL] {
        var dirs: [URL] = []
        if watchiCloudDrive {
            dirs.append(Self.iCloudRootDirectory)
        }
        if watchVoiceMemos && isVoiceMemosDirectlyAccessible {
            dirs.append(Self.voiceMemosDirectory)
        }
        if watchCustomFolder {
            dirs.append(contentsOf: customFolderURLs)
        }
        if dirs.isEmpty {
            dirs.append(watchedDirectory)
        }
        return dirs
    }
    
    public init(watchedDirectory: URL? = nil) {
        let defaultiCloud = Self.iCloudTranskriptDirectory
        if let dir = watchedDirectory {
            self.watchedDirectory = dir
        } else {
            self.watchedDirectory = defaultiCloud
        }
        
        let ud = UserDefaults.standard
        self.watchiCloudDrive = ud.object(forKey: "FolderWatcher.watchiCloudDrive") == nil ? true : ud.bool(forKey: "FolderWatcher.watchiCloudDrive")
        self.watchiCloudRoot = ud.object(forKey: "FolderWatcher.watchiCloudRoot") == nil ? true : ud.bool(forKey: "FolderWatcher.watchiCloudRoot")
        self.watchVoiceMemos = ud.object(forKey: "FolderWatcher.watchVoiceMemos") == nil ? true : ud.bool(forKey: "FolderWatcher.watchVoiceMemos")
        self.autoTranscribe = ud.object(forKey: "FolderWatcher.autoTranscribe") == nil ? true : ud.bool(forKey: "FolderWatcher.autoTranscribe")
        
        var loadedCustom: [URL] = []
        if let paths = ud.stringArray(forKey: "FolderWatcher.customFolderPaths") {
            for p in paths {
                let u = URL(fileURLWithPath: p, isDirectory: true)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
                    loadedCustom.append(u)
                }
            }
        }
        if loadedCustom.isEmpty, let customPath = ud.string(forKey: "FolderWatcher.customFolderPath"), !customPath.isEmpty {
            let url = URL(fileURLWithPath: customPath, isDirectory: true)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                loadedCustom.append(url)
            }
        }
        self.customFolderURLs = loadedCustom
        self.watchCustomFolder = !loadedCustom.isEmpty && ud.bool(forKey: "FolderWatcher.watchCustomFolder")
        
        if let saved = ud.stringArray(forKey: "FolderWatcher.processedPaths") {
            self.processedPaths = Set(saved)
        } else {
            self.processedPaths = []
        }
        if let savedDismissed = ud.stringArray(forKey: "FolderWatcher.dismissedPaths") {
            self.dismissedPaths = Set(savedDismissed)
        } else {
            self.dismissedPaths = []
        }
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
        Log.info("FolderWatcher started. Monitoring \(activeWatchedDirectories.count) directories.")
    }
    
    public func stopWatching() {
        isWatching = false
        timer?.invalidate()
        timer = nil
        followUpScanTask?.cancel()
        followUpScanTask = nil
        Log.info("FolderWatcher stopped.")
    }
    
    public func triggerImmediateScan() {
        Task {
            await scanDirectory()
        }
    }
    
    public func resetProcessedPaths() {
        processedPaths.removeAll()
        knownFiles.removeAll()
        UserDefaults.standard.removeObject(forKey: "FolderWatcher.processedPaths")
        Log.info("FolderWatcher processed paths reset.")
        triggerImmediateScan()
    }
    
    public func resetProcessedPaths(under directory: URL) {
        let rawPrefix = directory.standardizedFileURL.path
        let resolvedPrefix = directory.resolvingSymlinksInPath().standardizedFileURL.path
        let matchesPrefix: (String) -> Bool = { path in
            let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
            return path.hasPrefix(rawPrefix) ||
                   path.hasPrefix(resolvedPrefix) ||
                   resolvedPath.hasPrefix(rawPrefix) ||
                   resolvedPath.hasPrefix(resolvedPrefix)
        }
        processedPaths = processedPaths.filter { !matchesPrefix($0) }
        knownFiles = knownFiles.filter { !matchesPrefix($0.key) }
        persistProcessedPaths()
    }
    
    public func forceDownloadAllCloudItems() async {
        await scanDirectory()
    }
    
    public func scanDirectory() async {
        let dirs = activeWatchedDirectories
        for dir in dirs {
            await scanSingleDirectory(dir)
        }
    }
    
    private func scanSingleDirectory(_ directory: URL, isSubdirectory: Bool = false) async {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return }
        
        // DO NOT skip hidden files, because iCloud Drive placeholders start with '.' (e.g. .ses_kaydi.m4a.icloud)
        guard let items = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .contentModificationDateKey,
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey
            ],
            options: []
        ) else { return }
        
        let sortedItems = items.sorted { (u1, u2) -> Bool in
            let d1 = (try? u1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let d2 = (try? u2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return d1 > d2
        }
        
        for fileURL in sortedItems {
            let filename = fileURL.lastPathComponent
            
            // Exclude system meta files
            if filename == ".DS_Store" || filename.hasPrefix("._") || filename == "." || filename == ".." || filename == ".Trash" {
                continue
            }
            
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
                // If scanning iCloud Drive root, scan child directories (except Transkript output and hidden/app folders)
                if !isSubdirectory && directory.standardizedFileURL.path == Self.iCloudRootDirectory.standardizedFileURL.path {
                    if !filename.hasPrefix(".") && filename != "Transkript" && !filename.hasSuffix(".app") {
                        await scanSingleDirectory(fileURL, isSubdirectory: true)
                    }
                }
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
            
            // 2. Regular exclusions (non-icloud hidden files and incomplete browser downloads)
            if filename.hasPrefix(".") || filename.hasSuffix(".part") || filename.hasSuffix(".download") {
                continue
            }
            
            let ext = fileURL.pathExtension.lowercased()
            guard AudioValidator.isExtensionSupported(ext) else { continue }
            
            // 3. Check for ubiquitous item whose download is pending locally
            if let res = try? fileURL.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .ubiquitousItemIsDownloadingKey
            ]), let status = res.ubiquitousItemDownloadingStatus {
                if status == .notDownloaded {
                    try? fm.startDownloadingUbiquitousItem(at: fileURL)
                    activeCloudDownloads.insert(filename)
                    Log.info("iCloud audio file not yet downloaded locally, initiated automatic download: \(filename)")
                    continue
                } else if status != .current && status != .downloaded {
                    activeCloudDownloads.insert(filename)
                    continue
                }
            }
            
            // File is locally present and downloaded! Remove from active downloads
            activeCloudDownloads.remove(filename)
            
            let path = fileURL.path
            guard !isPathProcessed(path) && !isPathDismissed(path) else { continue }
            
            // 4. Size stability check (> 0 bytes)
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  let currentSize = attrs[.size] as? Int64,
                  currentSize > 0 else { continue }
            
            let modDate = (attrs[.modificationDate] as? Date) ?? Date()
            let isOldEnough = Date().timeIntervalSince(modDate) > 4.0
            
            let isStable: Bool
            if isOldEnough {
                isStable = true
            } else if let previousSize = knownFiles[path], previousSize == currentSize {
                isStable = true
            } else {
                isStable = false
                knownFiles[path] = currentSize
            }
            
            if isStable {
                // Size is stable! Validate audio
                if let _ = try? AudioValidator.validate(fileURL: fileURL) {
                    markPathsAsProcessed([path])
                    knownFiles.removeValue(forKey: path)
                    processedFilesCount += 1
                    lastProcessedFile = filename
                    
                    Log.info("New audio file detected: \(filename)")
                    await onNewAudioDiscovered?(fileURL)
                }
            } else {
                scheduleFollowUpScanIfNeeded()
            }
        }
    }
    
    private func scheduleFollowUpScanIfNeeded() {
        guard followUpScanTask == nil else { return }
        followUpScanTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self = self else { return }
            self.followUpScanTask = nil
            if !self.knownFiles.isEmpty {
                await self.scanDirectory()
            }
        }
    }
}
