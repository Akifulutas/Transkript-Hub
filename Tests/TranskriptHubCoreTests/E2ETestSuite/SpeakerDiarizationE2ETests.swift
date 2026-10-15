import Foundation
import Testing
@testable import TranskriptHubCore

// MARK: - Models and Palette Types (PROJECT.md)

public struct DiarizedSegment: Codable, Sendable, Equatable {
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
        // Deterministic hash based on speaker name string
        let hash = abs(speakerIdentifier.hashValue)
        let colorIndex = hash % colors.count
        return colors[colorIndex]
    }
    
    public static func color(forSpeakerIndex index: Int) -> HIGBadgeColor {
        let safeIndex = abs(index) % colors.count
        return colors[safeIndex]
    }
}

// MARK: - Acoustic Turn Diarizer Engine Harness

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
                    // Turn change detected across silence boundary
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
            return segments // Reject empty renaming
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

// MARK: - Test Suite

@Suite("Speaker Diarization & Badge Assignments E2E Test Suite")
struct SpeakerDiarizationE2ETests {
    
    @Test("Silence boundary clustering distinguishes speaker turns when pause >= 0.8s")
    func testSilenceBoundaryTurnClustering() {
        let diarizer = AcousticTurnDiarizer(silenceThreshold: 0.8)
        
        let rawSegments = [
            DiarizedSegment(start: 0.0, end: 2.0, text: "Merhaba, nasılsınız?"),
            DiarizedSegment(start: 2.2, end: 4.0, text: "Ben de iyiyim, teşekkürler."), // Gap: 0.2s -> same speaker
            DiarizedSegment(start: 5.5, end: 7.5, text: "Bugünkü gündem maddelerimiz nelerdir?"), // Gap: 1.5s >= 0.8s -> turn change
            DiarizedSegment(start: 7.7, end: 9.0, text: "İlk olarak bütçe raporunu inceleyeceğiz.") // Gap: 0.2s -> same speaker
        ]
        
        let diarized = diarizer.clusterTurns(segments: rawSegments)
        #expect(diarized.count == 4)
        
        #expect(diarized[0].speaker == "Speaker 1")
        #expect(diarized[1].speaker == "Speaker 1", "Gap of 0.2s should maintain Speaker 1")
        #expect(diarized[2].speaker == "Speaker 2", "Gap of 1.5s should trigger turn change to Speaker 2")
        #expect(diarized[3].speaker == "Speaker 2", "Gap of 0.2s should maintain Speaker 2")
    }
    
    @Test("Rapid alternating conversational turns cluster into exactly 2 unique speakers")
    func testAlternatingConversationClustering() {
        let diarizer = AcousticTurnDiarizer(silenceThreshold: 0.8)
        
        let alternatingSegments = [
            DiarizedSegment(start: 0.0, end: 1.5, text: "Soru 1"),
            DiarizedSegment(start: 2.5, end: 4.0, text: "Cevap 1"), // Gap 1.0s
            DiarizedSegment(start: 5.0, end: 6.5, text: "Soru 2"), // Gap 1.0s
            DiarizedSegment(start: 7.5, end: 9.0, text: "Cevap 2"), // Gap 1.0s
            DiarizedSegment(start: 10.0, end: 11.5, text: "Soru 3"), // Gap 1.0s
            DiarizedSegment(start: 12.5, end: 14.0, text: "Cevap 3")  // Gap 1.0s
        ]
        
        let diarized = diarizer.clusterTurns(segments: alternatingSegments)
        let uniqueSpeakers = Set(diarized.compactMap(\.speaker))
        
        #expect(uniqueSpeakers.count == 2)
        #expect(uniqueSpeakers.contains("Speaker 1"))
        #expect(uniqueSpeakers.contains("Speaker 2"))
        
        #expect(diarized[0].speaker == "Speaker 1")
        #expect(diarized[1].speaker == "Speaker 2")
        #expect(diarized[2].speaker == "Speaker 1")
        #expect(diarized[3].speaker == "Speaker 2")
        #expect(diarized[4].speaker == "Speaker 1")
        #expect(diarized[5].speaker == "Speaker 2")
    }
    
    @Test("Colored speaker badge palette assignments are deterministic and non-colliding")
    func testColoredBadgePaletteAssignment() {
        let color1 = AppleHIGPalette.color(forSpeakerIndex: 0)
        let color2 = AppleHIGPalette.color(forSpeakerIndex: 1)
        let color3 = AppleHIGPalette.color(forSpeakerIndex: 2)
        let color4 = AppleHIGPalette.color(forSpeakerIndex: 3)
        
        #expect(color1.name == "Blue")
        #expect(color2.name == "Purple")
        #expect(color3.name == "Orange")
        #expect(color4.name == "Green")
        
        #expect(color1 != color2)
        #expect(color2 != color3)
        #expect(color3 != color4)
        
        // Determinism check: multiple lookups for same speaker yield identical color
        let repeatLookup = AppleHIGPalette.color(forSpeakerIndex: 1)
        #expect(repeatLookup == color2)
        
        // Wrap-around modulo check for high speaker indices
        let wrappedColor = AppleHIGPalette.color(forSpeakerIndex: 8)
        #expect(wrappedColor == color1)
    }
    
    @Test("Inline speaker renaming propagates across all matching segments while preserving timestamps")
    func testSpeakerRenamingPropagation() {
        let diarizer = AcousticTurnDiarizer()
        
        let segments = [
            DiarizedSegment(start: 0.0, end: 2.0, text: "Giriş konuşması", speaker: "Speaker 1", words: [
                WordItem(text: "Giriş", start: 0.0, end: 0.8),
                WordItem(text: "konuşması", start: 0.9, end: 2.0)
            ]),
            DiarizedSegment(start: 2.5, end: 5.0, text: "Açıklama yapıyorum", speaker: "Speaker 2"),
            DiarizedSegment(start: 5.5, end: 8.0, text: "İkinci yorumum", speaker: "Speaker 1", words: [
                WordItem(text: "İkinci", start: 5.5, end: 6.5),
                WordItem(text: "yorumum", start: 6.6, end: 8.0)
            ])
        ]
        
        // User renames "Speaker 1" -> "Av. Kemal Bey"
        let renamed = diarizer.renameSpeaker(in: segments, from: "Speaker 1", to: "Av. Kemal Bey")
        
        #expect(renamed[0].speaker == "Av. Kemal Bey")
        #expect(renamed[1].speaker == "Speaker 2", "Speaker 2 must not be modified")
        #expect(renamed[2].speaker == "Av. Kemal Bey")
        
        // Verify timestamps and word tokens are strictly preserved
        #expect(renamed[0].start == 0.0)
        #expect(renamed[0].end == 2.0)
        #expect(renamed[0].words.count == 2)
        #expect(renamed[0].words[0].text == "Giriş")
        #expect(renamed[2].words[1].text == "yorumum")
        
        // Empty renaming rejection test
        let rejectEmpty = diarizer.renameSpeaker(in: renamed, from: "Speaker 2", to: "   ")
        #expect(rejectEmpty[1].speaker == "Speaker 2")
    }
    
    @Test("Monologue speech with short pauses remains under single speaker")
    func testMonologueSingleSpeakerClustering() {
        let diarizer = AcousticTurnDiarizer(silenceThreshold: 1.0)
        
        let lectureSegments = (0..<6).map { i in
            DiarizedSegment(
                start: Double(i) * 3.0,
                end: Double(i) * 3.0 + 2.5,
                text: "Ders bölümü \(i + 1)"
            )
        }
        
        let diarized = diarizer.clusterTurns(segments: lectureSegments)
        let uniqueSpeakers = Set(diarized.compactMap(\.speaker))
        
        #expect(uniqueSpeakers.count == 1)
        #expect(uniqueSpeakers.first == "Speaker 1")
    }
    
    @Test("JSON serialization and deserialization of diarized segments preserves words and speaker")
    func testSegmentSerializationWithSpeakerAndWordsRoundTrip() throws {
        let originalSegments = [
            DiarizedSegment(
                start: 1.25,
                end: 4.50,
                text: "Apple Silicon M3 Max mimarisi",
                speaker: "Mühendis Ali",
                words: [
                    WordItem(text: "Apple", start: 1.25, end: 1.80, confidence: 0.98),
                    WordItem(text: "Silicon", start: 1.85, end: 2.60, confidence: 0.95),
                    WordItem(text: "M3", start: 2.65, end: 3.10, confidence: 0.99),
                    WordItem(text: "Max", start: 3.15, end: 3.60, confidence: 0.97),
                    WordItem(text: "mimarisi", start: 3.65, end: 4.50, confidence: 0.94)
                ]
            )
        ]
        
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(originalSegments)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            Issue.record("Failed to create JSON string")
            return
        }
        
        #expect(jsonString.contains("Mühendis Ali"))
        #expect(jsonString.contains("Apple"))
        
        let decoder = JSONDecoder()
        let decodedSegments = try decoder.decode([DiarizedSegment].self, from: jsonData)
        
        #expect(decodedSegments == originalSegments)
        #expect(decodedSegments[0].speaker == "Mühendis Ali")
        #expect(decodedSegments[0].words.count == 5)
        #expect(decodedSegments[0].words[2].text == "M3")
        #expect(decodedSegments[0].words[2].confidence == 0.99)
    }
}
