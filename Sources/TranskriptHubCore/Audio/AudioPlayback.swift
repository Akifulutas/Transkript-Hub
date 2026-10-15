import Foundation
import Combine

@MainActor
public protocol AudioPlaybackControlling: AnyObject, ObservableObject {
    var currentTime: Double { get }
    var duration: Double { get }
    var isPlaying: Bool { get }
    func load(url: URL) async throws
    func play()
    func pause()
    func togglePlayPause()
    func seek(to time: Double)
}

public struct WordItem: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: String { "\(start)-\(end)-\(text)" }
    public let text: String
    public let start: Double // seconds
    public let end: Double   // seconds
    public let confidence: Float
    
    public init(text: String, start: Double, end: Double, confidence: Float = 1.0) {
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

public struct KaraokeWordSynchronizer: Sendable {
    public let words: [WordItem]
    
    public init(words: [WordItem]) {
        self.words = words.sorted { $0.start < $1.start }
    }
    
    /// Finds active word index for a given playhead time using binary search
    public func activeWordIndex(at time: Double) -> Int? {
        guard !words.isEmpty else { return nil }
        
        var low = 0
        var high = words.count - 1
        
        while low <= high {
            let mid = (low + high) / 2
            let word = words[mid]
            
            if time >= word.start && time <= word.end {
                return mid
            } else if time < word.start {
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        
        return nil
    }
    
    /// Given a click on word at index, returns the seek target timestamp
    public func seekTarget(forWordIndex index: Int) -> Double? {
        guard words.indices.contains(index) else { return nil }
        return words[index].start
    }
}
