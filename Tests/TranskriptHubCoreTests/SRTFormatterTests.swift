import Foundation
import Testing
@testable import TranskriptHubCore

@Suite("SRTFormatter Comprehensive Test Suite")
struct SRTFormatterTests {

    @Test("Timestamp formatting precision, rollover rounding, clamping, and >=100h support")
    func testFormatTimestampEdgeCases() {
        #expect(SRTFormatter.formatTimestamp(0.0) == "00:00:00,000")
        #expect(SRTFormatter.formatTimestamp(-5.25) == "00:00:00,000")
        #expect(SRTFormatter.formatTimestamp(.nan) == "00:00:00,000")
        #expect(SRTFormatter.formatTimestamp(.infinity) == "00:00:00,000")
        #expect(SRTFormatter.formatTimestamp(65.432) == "00:01:05,432")
        // 59.9996 rounds to 60000ms -> must roll over cleanly to 00:01:00,000, never 00:00:59,1000
        #expect(SRTFormatter.formatTimestamp(59.9996) == "00:01:00,000")
        #expect(SRTFormatter.formatTimestamp(360000.5) == "100:00:00,500")
    }

    @Test("Empty array returns empty string and whitespace-only segments are skipped with contiguous indices")
    func testEmptyAndContiguousIndexing() {
        #expect(SRTFormatter.format(segments: []).isEmpty)

        let segments = [
            Segment(start: 0.0, end: 1.5, text: "   \n\t "),
            Segment(start: 2.0, end: 4.0, text: "Erster Satz."),
            Segment(start: 4.5, end: 5.0, text: ""),
            Segment(start: 5.5, end: 7.5, text: "Zweiter Satz.")
        ]

        let srt = SRTFormatter.format(segments: segments)
        let blocks = srt.components(separatedBy: "\n\n")
        #expect(blocks.count == 2)
        #expect(blocks[0].hasPrefix("1\n00:00:02,000 --> 00:00:04,000\nErster Satz."))
        #expect(blocks[1].hasPrefix("2\n00:00:05,500 --> 00:00:07,500\nZweiter Satz."))
    }

    @Test("Zero and inverted durations clamp end to start + 0.1s")
    func testZeroAndInvertedDurationClamped() {
        let segments = [
            Segment(start: 10.0, end: 10.0, text: "Null Dauer."),
            Segment(start: 20.0, end: 18.0, text: "Invertierte Dauer.")
        ]

        let srt = SRTFormatter.format(segments: segments)
        let blocks = srt.components(separatedBy: "\n\n")
        #expect(blocks.count == 2)
        #expect(blocks[0].contains("00:00:10,000 --> 00:00:10,100"))
        #expect(blocks[1].contains("00:00:20,000 --> 00:00:20,100"))
    }

    @Test("Short segment <= 42 chars stays on 1 line; 43..84 chars wraps naturally onto 2 lines")
    func testShortAndMediumLineWrapping() {
        let shortText = "Das Turbinenrad dreht sich gleichmäßig."
        #expect(shortText.count <= 42)
        let shortSRT = SRTFormatter.format(segments: [Segment(start: 0.0, end: 2.0, text: shortText)])
        let shortLines = shortSRT.components(separatedBy: "\n")
        #expect(shortLines.count == 3) // index + timestamp + 1 line
        #expect(shortLines[2] == shortText)

        let mediumText = "Das Gittermodell für das Turbinenrad hat eine feine Auflösung."
        #expect(mediumText.count > 42 && mediumText.count <= 84)
        let mediumSRT = SRTFormatter.format(segments: [Segment(start: 0.0, end: 4.0, text: mediumText)])
        let mediumLines = mediumSRT.components(separatedBy: "\n")
        #expect(mediumLines.count == 4) // index + timestamp + 2 lines
        #expect(mediumLines[2].count <= 42)
        #expect(mediumLines[3].count <= 42)
        #expect("\(mediumLines[2]) \(mediumLines[3])" == mediumText)
    }

    @Test("Long segment > 84 chars splits into sequential cues <= 2 lines and <= 42 chars/line with zero dropped words")
    func testLongSegmentSplitsIntoSequentialCuesPreservingAllWords() {
        let longText = "Bei der aerodynamischen Strömungssimulation des Turbinenrads prüfen wir zuerst die Netzgenerierung im Kurbelgehäuse und danach den Drehmomentverlauf am Zylinderkopf."
        let segments = [Segment(start: 10.0, end: 22.0, text: longText)]

        let srt = SRTFormatter.format(segments: segments)
        let blocks = srt.components(separatedBy: "\n\n")
        #expect(blocks.count >= 2)

        var reconstructedWords: [String] = []
        for (idx, block) in blocks.enumerated() {
            let lines = block.components(separatedBy: "\n")
            #expect(lines[0] == "\(idx + 1)")
            #expect(lines[1].contains(" --> "))
            let textLines = Array(lines.dropFirst(2))
            #expect(textLines.count >= 1 && textLines.count <= 2)
            for line in textLines {
                #expect(line.count <= 42)
                reconstructedWords.append(contentsOf: line.split(separator: " ").map(String.init))
            }
        }

        let originalWords = longText.split(separator: " ").map(String.init)
        #expect(reconstructedWords == originalWords)
    }

    @Test("Unbroken German compound words > 42 chars format safely without exceeding line width")
    func testOversizedGermanCompoundWords() {
        let hyphenated = "Strömungssimulations-Gittermodell-Validierungsprozess"
        let unhyphenated = "Donaudampfschifffahrtselektrizitätenhauptbetriebswerkbauunterbeamtengesellschaft"

        let srt = SRTFormatter.format(segments: [
            Segment(start: 0.0, end: 3.0, text: hyphenated),
            Segment(start: 4.0, end: 7.0, text: unhyphenated)
        ])

        let blocks = srt.components(separatedBy: "\n\n")
        #expect(blocks.count >= 2)
        for block in blocks {
            let textLines = block.components(separatedBy: "\n").dropFirst(2)
            #expect(textLines.count <= 2)
            for line in textLines {
                #expect(line.count <= 42)
            }
        }
        let rejoined = blocks
            .flatMap { $0.components(separatedBy: "\n").dropFirst(2) }
            .joined()
        #expect(rejoined.contains("Strömungssimulations-Gittermodell-Validierungsprozess"))
        #expect(rejoined.contains(unhyphenated))
    }

    @Test("Special characters and internal newlines are normalized cleanly")
    func testUnicodeAndInternalNewlinesNormalized() {
        let segments = [
            Segment(start: 0.0, end: 3.0, text: "Prüfung der Öl-Strömung\r\nim Gehäuse: şğüöçıİ.")
        ]

        let srt = SRTFormatter.format(segments: segments)
        let blocks = srt.components(separatedBy: "\n\n")
        #expect(blocks.count == 1)
        let lines = blocks[0].components(separatedBy: "\n")
        #expect(lines.count <= 4)
        #expect(srt.contains("Öl-Strömung"))
        #expect(srt.contains("şğüöçıİ"))
    }

    @Test("Integration: PostProcessor.processSegments feeds cleanly into SRTFormatter")
    func testPostProcessorToSRTFormatterIntegration() {
        let processor = TranscriptPostProcessor()
        let raw = [
            Segment(start: 0.0, end: 2.0, text: "Vielen Dank."),
            Segment(start: 2.5, end: 5.5, text: "Das Gittermodell ist fertig."),
            Segment(start: 6.0, end: 8.5, text: "Es heilt die göttliche Kraft!"),
            Segment(start: 9.0, end: 12.0, text: "Jetzt starten wir die Berechnung.")
        ]

        let cleaned = processor.processSegments(segments: raw)
        let srt = SRTFormatter.format(segments: cleaned)
        let blocks = srt.components(separatedBy: "\n\n")

        #expect(blocks.count == 2)
        #expect(blocks[0] == "1\n00:00:02,500 --> 00:00:05,500\nDas Gittermodell ist fertig.")
        #expect(blocks[1] == "2\n00:00:09,000 --> 00:00:12,000\nJetzt starten wir die Berechnung.")
    }

    @Test("Hyphenated and slashed compound words exceeding maxLineLength coalesce without spurious spaces")
    func testCompoundWordOversizedPieceNoSpuriousSpace() {
        let hyphenCompound = "Strömungssimulationsgittermodellgenerierungs-Verfahren"
        let slashCompound = "Strömungssimulationsgittermodellgenerierungs/Verfahren"
        let boundaryHyphen = String(repeating: "x", count: 42) + "-" + String(repeating: "y", count: 42)
        let midOversized = "a-" + String(repeating: "b", count: 43) + "-c"

        for word in [hyphenCompound, slashCompound, boundaryHyphen, midOversized] {
            let srt = SRTFormatter.format(segments: [Segment(start: 0.0, end: 4.0, text: word)])
            let blocks = srt.components(separatedBy: "\n\n")
            let textLines = blocks.flatMap { $0.components(separatedBy: "\n").dropFirst(2) }
            for line in textLines {
                #expect(line.count <= 42, "Line exceeded 42 chars: \(line)")
                #expect(!line.contains(" "), "No spurious space allowed inside single compound word: \(line)")
            }
            #expect(textLines.joined() == word, "Rejoined compound word must match original '\(word)', got '\(textLines.joined())'")
        }

        let hypSRT = SRTFormatter.format(segments: [Segment(start: 0.0, end: 3.0, text: hyphenCompound)])
        #expect(hypSRT.contains("gs-Verfahren"))
        #expect(!hypSRT.contains("gs- Verfahren"))
    }

    @Test("High-cue-count clamped segment timestamps remain strictly non-overlapping and positive-duration")
    func testHighCueCountSubCueTimestampsMonotonic() {
        let massiveText = (1...3000).map { "W\($0)" }.joined(separator: " ")
        let srt = SRTFormatter.format(segments: [Segment(start: 10.0, end: 10.0, text: massiveText)])
        let blocks = srt.components(separatedBy: "\n\n")
        #expect(blocks.count > 100)

        func parseMs(_ ts: String) -> Int? {
            let parts = ts.components(separatedBy: ",")
            guard parts.count == 2, let ms = Int(parts[1]) else { return nil }
            let hms = parts[0].components(separatedBy: ":").compactMap(Int.init)
            guard hms.count == 3 else { return nil }
            return ((hms[0] * 3600 + hms[1] * 60 + hms[2]) * 1000) + ms
        }

        var previousEndMs = -1
        for (idx, block) in blocks.enumerated() {
            let lines = block.components(separatedBy: "\n")
            #expect(lines[0] == "\(idx + 1)")
            let times = lines[1].components(separatedBy: " --> ")
            #expect(times.count == 2)
            if times.count == 2, let startMs = parseMs(times[0]), let endMs = parseMs(times[1]) {
                #expect(endMs > startMs, "Cue \(idx + 1) must have strictly positive duration")
                #expect(startMs >= previousEndMs, "Cue \(idx + 1) overlaps previous cue (\(startMs) < \(previousEndMs))")
                previousEndMs = endMs
            }
        }
    }
}
