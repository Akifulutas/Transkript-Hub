import Foundation

public struct DiarizedSegment: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(start)-\(end)-\(speaker ?? "unknown")" }
    public var start: Double
    public var end: Double
    public var text: String
    public var speaker: String?
    public var words: [WordItem]
    
    public init(
        start: Double,
        end: Double,
        text: String,
        speaker: String? = nil,
        words: [WordItem] = []
    ) {
        self.start = start
        self.end = end
        self.text = text
        self.speaker = speaker
        self.words = words
    }
}

public struct HIGBadgeColor: Sendable, Equatable {
    public let name: String
    public let hex: String
    public let index: Int
    
    public init(name: String, hex: String, index: Int) {
        self.name = name
        self.hex = hex
        self.index = index
    }
}

public enum AppleHIGPalette {
    public static let colors: [HIGBadgeColor] = [
        HIGBadgeColor(name: "Blue", hex: "#007AFF", index: 0),
        HIGBadgeColor(name: "Purple", hex: "#AF52DE", index: 1),
        HIGBadgeColor(name: "Orange", hex: "#FF9500", index: 2),
        HIGBadgeColor(name: "Green", hex: "#34C759", index: 3),
        HIGBadgeColor(name: "Pink", hex: "#FF2D55", index: 4),
        HIGBadgeColor(name: "Teal", hex: "#30B0C7", index: 5),
        HIGBadgeColor(name: "Indigo", hex: "#5856D6", index: 6),
        HIGBadgeColor(name: "Yellow", hex: "#FFCC00", index: 7)
    ]
    
    public static func color(for speakerIdentifier: String) -> HIGBadgeColor {
        // Deterministic FNV-1a hash across process launches
        var hash: UInt32 = 2166136261
        for byte in speakerIdentifier.utf8 {
            hash ^= UInt32(byte)
            hash &*= 16777619
        }
        let colorIndex = Int(hash % UInt32(colors.count))
        return colors[colorIndex]
    }
    
    public static func color(forSpeakerIndex index: Int) -> HIGBadgeColor {
        let safeIndex = abs(index) % colors.count
        return colors[safeIndex]
    }
}

public final class AcousticTurnDiarizer: Sendable {
    public let silenceThreshold: Double // seconds
    
    public init(silenceThreshold: Double = 0.8) {
        self.silenceThreshold = silenceThreshold
    }
    
    /// Clusters segments into speaker turns based on silence boundary transitions
    public func clusterTurns(segments: [DiarizedSegment], maxAlternatingSpeakers: Int = 2) -> [DiarizedSegment] {
        guard !segments.isEmpty else { return [] }
        
        var result: [DiarizedSegment] = []
        result.reserveCapacity(segments.count)
        
        var currentSpeakerIndex = 1
        var previousEnd: Double = segments[0].start
        
        for (idx, seg) in segments.enumerated() {
            var updated = seg
            
            if idx > 0 {
                let pauseDuration = seg.start - previousEnd
                if pauseDuration >= silenceThreshold {
                    currentSpeakerIndex = (currentSpeakerIndex % maxAlternatingSpeakers) + 1
                }
            }
            
            updated.speaker = "Speaker \(currentSpeakerIndex)"
            previousEnd = seg.end
            result.append(updated)
        }
        
        return result
    }
    
    /// In-place speaker renaming propagation across all matching segments
    public func renameSpeaker(
        in segments: [DiarizedSegment],
        from oldName: String,
        to newName: String
    ) -> [DiarizedSegment] {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return segments
        }
        
        return segments.map { seg in
            var copy = seg
            if copy.speaker == oldName {
                copy.speaker = newName
            }
            return copy
        }
    }
    
    /// Clusters standard Segment array into speaker turns based on silence boundary transitions
    public func clusterTurns(segments: [Segment], maxAlternatingSpeakers: Int = 2) -> [Segment] {
        guard !segments.isEmpty else { return [] }
        
        var result: [Segment] = []
        result.reserveCapacity(segments.count)
        
        var currentSpeakerIndex = 1
        var previousEnd: Double = segments[0].start
        
        for (idx, seg) in segments.enumerated() {
            var updated = seg
            
            if idx > 0 {
                let pauseDuration = seg.start - previousEnd
                if pauseDuration >= silenceThreshold {
                    currentSpeakerIndex = (currentSpeakerIndex % maxAlternatingSpeakers) + 1
                }
            }
            
            updated.speaker = "Speaker \(currentSpeakerIndex)"
            previousEnd = seg.end
            result.append(updated)
        }
        
        return result
    }
    
    /// In-place speaker renaming propagation across all matching standard Segments
    public func renameSpeaker(
        in segments: [Segment],
        from oldName: String,
        to newName: String
    ) -> [Segment] {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return segments
        }
        
        return segments.map { seg in
            var copy = seg
            if copy.speaker == oldName {
                copy.speaker = newName
            }
            return copy
        }
    }
}
