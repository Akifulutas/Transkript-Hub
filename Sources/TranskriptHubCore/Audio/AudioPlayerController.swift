import Foundation
import AVFoundation
import Combine

public enum AudioPlaybackStatus: Sendable, Equatable {
    case idle
    case loading(URL)
    case ready
    case playing
    case paused
    case ended
    case failed(String)
}

public enum AudioPlayerError: Error, LocalizedError, Sendable {
    case fileNotFound(URL)
    case unplayable(String)
    case assetLoadFailed(String)
    case seekFailed
    
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Ses dosyası bulunamadı: \(url.path)"
        case .unplayable(let reason):
            return "Ses dosyası oynatılamıyor: \(reason)"
        case .assetLoadFailed(let reason):
            return "Ses varlığı yüklenemedi: \(reason)"
        case .seekFailed:
            return "Ses arama işlemi başarısız oldu."
        }
    }
}

@MainActor
public final class AudioPlayerController: ObservableObject, AudioPlaybackControlling {
    // MARK: - Published Properties
    @Published public private(set) var currentTime: Double = 0.0
    @Published public private(set) var duration: Double = 0.0
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var status: AudioPlaybackStatus = .idle
    @Published public private(set) var currentURL: URL? = nil
    
    @Published public var playbackRate: Float = 1.0 {
        didSet {
            guard let player = player else { return }
            if isPlaying {
                player.rate = playbackRate
            }
        }
    }
    
    @Published public var volume: Float = 1.0 {
        didSet {
            player?.volume = volume
        }
    }
    
    // MARK: - Scrubbing & Seeking State
    @Published public private(set) var isScrubbing: Bool = false
    private var wasPlayingBeforeScrub: Bool = false
    private var inFlightSeekTime: Double? = nil
    private var seekGeneration: Int = 0
    
    // MARK: - Internal AVPlayer & Observers
    private var player: AVPlayer?
    private var timeObserverToken: Any?
    private var endObserverToken: (any NSObjectProtocol)?
    
    public let timeUpdateInterval: CMTime
    
    public init(timeUpdateInterval: CMTime = CMTime(seconds: 0.05, preferredTimescale: 600)) {
        self.timeUpdateInterval = timeUpdateInterval
    }
    
    // MARK: - AudioPlaybackControlling API
    
    public func load(url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AudioPlayerError.fileNotFound(url)
        }
        
        stop()
        status = .loading(url)
        currentURL = url
        
        let asset = AVURLAsset(url: url)
        do {
            let (isPlayable, durationCM) = try await asset.load(.isPlayable, .duration)
            guard isPlayable else {
                let err = AudioPlayerError.unplayable("Format desteklenmiyor veya oynatılamıyor.")
                status = .failed(err.localizedDescription)
                throw err
            }
            
            let seconds = durationCM.seconds
            guard seconds.isFinite && !seconds.isNaN && seconds > 0 else {
                let err = AudioPlayerError.unplayable("Geçersiz ses süresi (0 sn).")
                status = .failed(err.localizedDescription)
                throw err
            }
            
            let item = AVPlayerItem(asset: asset)
            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.rate = 0.0
            newPlayer.volume = self.volume
            
            self.player = newPlayer
            self.duration = seconds
            self.currentTime = 0.0
            self.isPlaying = false
            self.status = .ready
            self.inFlightSeekTime = nil
            self.isScrubbing = false
            self.wasPlayingBeforeScrub = false
            self.seekGeneration += 1
            
            attachTimeObserver()
            attachEndObserver(for: item)
        } catch let err as AudioPlayerError {
            throw err
        } catch {
            let err = AudioPlayerError.assetLoadFailed(error.localizedDescription)
            status = .failed(err.localizedDescription)
            throw err
        }
    }
    
    public func play() {
        guard let player = player, status == .ready || status == .paused || status == .ended else { return }
        
        if status == .ended || currentTime >= duration {
            seek(to: 0.0)
        }
        
        player.rate = playbackRate
        isPlaying = true
        status = .playing
    }
    
    public func pause() {
        guard let player = player else { return }
        player.pause()
        isPlaying = false
        status = .paused
    }
    
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    public func skipForward(by seconds: Double = 5.0) {
        guard !seconds.isNaN && seconds.isFinite else { return }
        seek(to: currentTime + seconds)
    }
    
    public func skipBackward(by seconds: Double = 5.0) {
        guard !seconds.isNaN && seconds.isFinite else { return }
        seek(to: currentTime - seconds)
    }
    
    public func seek(to time: Double) {
        guard let player = player, player.currentItem != nil,
              status == .ready || status == .playing || status == .paused || status == .ended else {
            self.inFlightSeekTime = nil
            return
        }
        
        guard !time.isNaN else { return }
        
        let safeTime: Double
        if time <= 0.0 || time == -.infinity {
            safeTime = 0.0
        } else if time >= duration || time == .infinity {
            safeTime = duration
        } else {
            safeTime = time
        }
        
        self.currentTime = safeTime
        self.inFlightSeekTime = safeTime
        
        seekGeneration += 1
        let targetGeneration = seekGeneration
        
        let cmTime = CMTime(seconds: safeTime, preferredTimescale: 1000)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if self.seekGeneration == targetGeneration {
                    self.inFlightSeekTime = nil
                }
            }
        }
    }
    
    @discardableResult
    public func seek(to time: Double, tolerance: CMTime) async -> Bool {
        guard let player = player, player.currentItem != nil,
              status == .ready || status == .playing || status == .paused || status == .ended else {
            self.inFlightSeekTime = nil
            return false
        }
        
        guard !time.isNaN else { return false }
        
        let safeTime: Double
        if time <= 0.0 || time == -.infinity {
            safeTime = 0.0
        } else if time >= duration || time == .infinity {
            safeTime = duration
        } else {
            safeTime = time
        }
        
        self.currentTime = safeTime
        self.inFlightSeekTime = safeTime
        
        seekGeneration += 1
        let targetGeneration = seekGeneration
        
        let cmTime = CMTime(seconds: safeTime, preferredTimescale: 1000)
        return await withCheckedContinuation { continuation in
            player.seek(to: cmTime, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
                Task { @MainActor [weak self] in
                    guard let self = self else {
                        continuation.resume(returning: finished)
                        return
                    }
                    if self.seekGeneration == targetGeneration {
                        self.inFlightSeekTime = nil
                    }
                    continuation.resume(returning: finished)
                }
            }
        }
    }
    
    public func stop() {
        if let player = player, let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        if let endToken = endObserverToken {
            NotificationCenter.default.removeObserver(endToken)
            endObserverToken = nil
        }
        
        player?.pause()
        player = nil
        isPlaying = false
        currentTime = 0.0
        duration = 0.0
        status = .idle
        currentURL = nil
        isScrubbing = false
        wasPlayingBeforeScrub = false
        inFlightSeekTime = nil
        seekGeneration += 1
    }
    
    // MARK: - Teardown & Lifecycle
    
    isolated deinit {
        stop()
    }
    
    // MARK: - Scrubbing Ergonomics (Anti-Jitter)
    
    public func beginScrubbing() {
        guard !isScrubbing else { return }
        isScrubbing = true
        wasPlayingBeforeScrub = isPlaying
        if isPlaying {
            player?.pause()
        }
    }
    
    public func endScrubbing(resumePlayback: Bool = true) {
        guard isScrubbing else { return }
        isScrubbing = false
        if wasPlayingBeforeScrub && resumePlayback {
            play()
        }
        wasPlayingBeforeScrub = false
    }
    
    public func setPlaybackRate(_ rate: Float) {
        let clamped = max(0.25, min(rate, 3.0))
        self.playbackRate = clamped
    }
    
    // MARK: - Observer Management
    
    private func attachTimeObserver() {
        guard let player = player else { return }
        
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: timeUpdateInterval,
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                guard !self.isScrubbing, self.inFlightSeekTime == nil else { return }
                let sec = time.seconds
                if sec.isFinite && !sec.isNaN && sec >= 0 {
                    self.currentTime = sec
                    if sec >= self.duration - 0.02 && self.isPlaying {
                        self.isPlaying = false
                        self.status = .ended
                        self.currentTime = self.duration
                    }
                }
            }
        }
    }
    
    private func attachEndObserver(for item: AVPlayerItem) {
        endObserverToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self = self else { return }
                self.isPlaying = false
                self.status = .ended
                self.currentTime = self.duration
            }
        }
    }
    
    // MARK: - Formatting Helpers
    
    nonisolated public static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN && seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let s = total % 60
        let m = (total / 60) % 60
        let h = total / 3600
        
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
    
    nonisolated public static func formatTimeWithMilliseconds(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN && seconds >= 0 else { return "00:00.00" }
        let roundedHundredths = Int((seconds * 100.0).rounded())
        let ms = roundedHundredths % 100
        let totalSeconds = roundedHundredths / 100
        let s = totalSeconds % 60
        let m = (totalSeconds / 60) % 60
        let h = totalSeconds / 3600
        
        if h > 0 {
            return String(format: "%d:%02d:%02d.%02d", h, m, s, ms)
        } else {
            return String(format: "%02d:%02d.%02d", m, s, ms)
        }
    }
}
