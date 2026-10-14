import Foundation
import AppKit

@MainActor
public final class ClipboardMonitor: ObservableObject {
    @Published public var isMonitoring: Bool = false
    @Published public var lastCapturedURL: String? = nil
    
    private var timer: Timer?
    private var lastChangeCount: Int = NSPasteboard.general.changeCount
    private let onURLDetected: (ParsedYouTubeVideo) -> Void
    public var onBatchDetected: ((YouTubeLinkType) -> Void)?
    
    public init(onURLDetected: @escaping (ParsedYouTubeVideo) -> Void) {
        self.onURLDetected = onURLDetected
    }
    
    public func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true
        lastChangeCount = -1
        checkPasteboard()
        
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkPasteboard()
            }
        }
    }
    
    public func stopMonitoring() {
        isMonitoring = false
        timer?.invalidate()
        timer = nil
    }
    
    public func toggle() {
        if isMonitoring {
            stopMonitoring()
        } else {
            startMonitoring()
        }
    }
    
    private func checkPasteboard() {
        let pasteboard = NSPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else { return }
        lastChangeCount = currentChangeCount
        
        // Check for password manager concealed/transient types
        if let types = pasteboard.types {
            let typeIdentifiers = Set(types.map(\.rawValue))
            if typeIdentifiers.contains("org.nspasteboard.ConcealedType") ||
               typeIdentifiers.contains("org.nspasteboard.TransientType") ||
               typeIdentifiers.contains("com.agilebits.onepassword") {
                return
            }
        }
        
        guard let text = pasteboard.string(forType: .string) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // First check if the text is a direct playlist, channel or single video link
        if let detected = URLParser.detectType(trimmed) {
            switch detected {
            case .singleVideo(let video):
                lastCapturedURL = video.canonicalURL
                onURLDetected(video)
                return
            case .playlist, .channel:
                lastCapturedURL = trimmed
                if let onBatch = onBatchDetected {
                    onBatch(detected)
                    return
                }
            }
        }
        
        // Fallback to bulk parsing for multi-line or mixed text
        let parsedVideos = URLParser.parseBulk(text)
        for video in parsedVideos {
            lastCapturedURL = video.canonicalURL
            onURLDetected(video)
        }
    }
}
