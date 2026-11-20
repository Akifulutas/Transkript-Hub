import Foundation
import Testing
@testable import TranskriptHubCore

@Suite("TranscriptPostProcessor Hardening & Anti-Hallucination Test Suite")
struct TranscriptPostProcessorTests {

    @Test("processSegments preserves start, end, speaker, noSpeechProb, and words")
    func testProcessSegmentsPreservesMetadataAndTimestamps() {
        let processor = TranscriptPostProcessor()
        let words1 = [
            Word(text: "Das", start: 0.0, end: 0.3, confidence: 0.99),
            Word(text: "Turbinenrad", start: 0.4, end: 1.1, confidence: 0.97),
            Word(text: "läuft.", start: 1.2, end: 1.8, confidence: 0.98)
        ]
        let segments = [
            Segment(start: 0.0, end: 2.0, text: "Das Turbinenrad läuft.", speaker: "Speaker 1", words: words1, noSpeechProb: 0.05),
            Segment(start: 2.5, end: 5.0, text: "Es heilt die göttliche Kraft!", speaker: "Speaker 1", noSpeechProb: 0.85),
            Segment(start: 5.5, end: 8.0, text: "Die Netzgenerierung ist abgeschlossen.", speaker: "Speaker 2", noSpeechProb: 0.02)
        ]

        let cleaned = processor.processSegments(segments: segments)
        #expect(cleaned.count == 2)
        #expect(cleaned[0].start == 0.0)
        #expect(cleaned[0].end == 2.0)
        #expect(cleaned[0].speaker == "Speaker 1")
        #expect(cleaned[0].words == words1)
        #expect(cleaned[0].noSpeechProb == 0.05)

        #expect(cleaned[1].start == 5.5)
        #expect(cleaned[1].end == 8.0)
        #expect(cleaned[1].speaker == "Speaker 2")
        #expect(cleaned[1].text == "Die Netzgenerierung ist abgeschlossen.")
    }

    @Test("Tier A pure hallucinations and dynamic credits are pruned on single occurrence")
    func testTierAPureAndDynamicCreditPruning() {
        let processor = TranscriptPostProcessor()
        let hallucinations = [
            "...ES HEILT DIE GÖTTLICHE KRAFT!!!",
            "Ich hoffe, es hilft, es heilt die göttliche Kraft.",
            "Altyazı M.K.",
            "Subtitles by the Amara.org community",
            "Untertitel von Stephanie Geiges.",
            "Untertitel im Auftrag des ZDF.",
            "Übersetzung von Max Mustermann.",
            "Copyright WDR 2024.",
            "© 2024 Example Studio",
            "All rights reserved.",
            "Alle Rechte vorbehalten."
        ]

        for phrase in hallucinations {
            let result = processor.processSegments(segments: [Segment(start: 0.0, end: 2.0, text: phrase)])
            #expect(result.isEmpty, "Expected Tier A hallucination to be pruned: '\(phrase)'")
        }
    }

    @Test("Tier A pure hallucination sentence stripped from mixed segment while preserving real speech")
    func testMixedSegmentStripsOnlyHallucinationSentence() throws {
        let processor = TranscriptPostProcessor()
        let segments = [
            Segment(start: 1.0, end: 5.0, text: "Das Gittermodell ist konvergiert. Es heilt die göttliche Kraft!")
        ]

        let cleaned = processor.processSegments(segments: segments)
        let first = try #require(cleaned.first)
        #expect(cleaned.count == 1)
        #expect(first.text == "Das Gittermodell ist konvergiert.")
        #expect(first.start == 1.0)
        #expect(first.end == 5.0)
    }

    @Test("Tier B standalone boilerplate is pruned ONLY on exact normalized match")
    func testTierBStandaloneBoilerplateExactMatchOnly() {
        let processor = TranscriptPostProcessor()
        let boilerplate = [
            "Vielen Dank.",
            "Vielen Dank für Ihre Aufmerksamkeit.",
            "Vielen Dank fürs Zuschauen!",
            "Amen.",
            "Thank you.",
            "Thank you for watching...",
            "Lütfen abone olun."
        ]

        for phrase in boilerplate {
            let result = processor.processSegments(segments: [Segment(start: 0.0, end: 2.0, text: phrase)])
            #expect(result.isEmpty, "Expected standalone boilerplate to be pruned: '\(phrase)'")
        }

        // Disabling filterStandaloneBoilerplate preserves standalone Tier B
        let disabledOpts = PostProcessorOptions(filterStandaloneBoilerplate: false)
        let kept = processor.processSegments(segments: [Segment(start: 0.0, end: 2.0, text: "Vielen Dank.")], options: disabledOpts)
        #expect(kept.count == 1)
    }

    @Test("Legitimate German technical sentences starting with boilerplate-like words are NEVER dropped")
    func testNoFalsePositiveOnRealTechnicalSpeech() {
        let processor = TranscriptPostProcessor()
        let realSpeech = [
            Segment(start: 0.0, end: 3.0, text: "Vielen Dank für die Erklärung zur Schaufelgeometrie des Turbinenrads."),
            Segment(start: 3.5, end: 6.0, text: "Thank you, the CAD mesh is converged."),
            Segment(start: 6.5, end: 9.0, text: "Untertitel im Video zeigen das Gittermodell."),
            Segment(start: 9.5, end: 11.0, text: "Ja."),
            Segment(start: 11.5, end: 13.0, text: "Genau.")
        ]

        let cleaned = processor.processSegments(segments: realSpeech)
        #expect(cleaned.count == realSpeech.count)
        #expect(cleaned[0].text.contains("Schaufelgeometrie"))
        #expect(cleaned[1].text.contains("CAD mesh"))
        #expect(cleaned[2].text.contains("Gittermodell"))
        #expect(cleaned[3].text == "Ja.")
        #expect(cleaned[4].text == "Genau.")
    }

    @Test("Intra-segment phrase deduplication collapses 3+ single words and >20-word repeated clauses")
    func testIntraSegmentPhraseAndSentenceDeduplication() {
        let processor = TranscriptPostProcessor()

        // 3 single words -> <= 2
        let threeJa = processor.deduplicatePhrases("Ja. Ja. Ja.")
        let jaCount = threeJa.components(separatedBy: "Ja").count - 1
        #expect(jaCount <= 2)

        // 25-word clause repeated twice (> previous 20-word limit)
        let longClause = "Bei der Strömungssimulation am Turbinenrad müssen wir die Grenzschichtauflösung entlang der Schaufelgeometrie im Gittermodell noch einmal deutlich verfeinern und alle Randbedingungen im Kurbelgehäuse prüfen."
        let doubled = "\(longClause) \(longClause)"
        let deduped = processor.deduplicatePhrases(doubled)
        let clauseCount = deduped.components(separatedBy: "Strömungssimulation am Turbinenrad").count - 1
        #expect(clauseCount == 1)
    }

    @Test("Zlib compression ratio and n-gram diversity catch entropy collapse while preserving dense German prose")
    func testCompressionRatioEntropyCollapseVsRealTechnicalProse() {
        let processor = TranscriptPostProcessor()

        // Non-consecutive varied-filler loop that defeats simple consecutive word windows
        let collapsedText = (1...20).map { i in
            "und dann ist es wieder und dann so \(i % 2 == 0 ? "ja" : "genau") und dann ist es wieder"
        }.joined(separator: " ")

        let realTechnicalText = "Für das Kurbelgehäuse und den Zylinderkopf verwenden wir ein hybrides Tetraeder-Hexaeder-Netz mit lokaler Verfeinerung an den Kühlkanälen, damit der Drehmomentverlauf und die thermische Belastung in der Strömungssimulation präzise abgebildet werden."

        let segments = [
            Segment(start: 0.0, end: 10.0, text: collapsedText),
            Segment(start: 11.0, end: 22.0, text: realTechnicalText)
        ]

        let cleaned = processor.processSegments(segments: segments)
        #expect(cleaned.count == 1)
        #expect(cleaned[0].text == realTechnicalText)
    }

    @Test("Inter-segment non-boilerplate ping-pong loop (A-B-A-B-A-B) is broken")
    func testInterSegmentPingPongLoopSuppression() {
        let processor = TranscriptPostProcessor()
        let segments = [
            Segment(start: 0.0, end: 2.0, text: "Wir starten die Simulation."),
            Segment(start: 2.0, end: 3.0, text: "Das Netz ist fein."),
            Segment(start: 3.0, end: 4.0, text: "Die Kante ist rund."),
            Segment(start: 4.0, end: 5.0, text: "Das Netz ist fein."),
            Segment(start: 5.0, end: 6.0, text: "Die Kante ist rund."),
            Segment(start: 6.0, end: 7.0, text: "Das Netz ist fein."),
            Segment(start: 7.0, end: 8.0, text: "Die Kante ist rund."),
            Segment(start: 9.0, end: 11.0, text: "Weiter geht es mit dem Rotor.")
        ]

        let cleaned = processor.processSegments(segments: segments)
        let countA = cleaned.filter { $0.text == "Das Netz ist fein." }.count
        let countB = cleaned.filter { $0.text == "Die Kante ist rund." }.count

        #expect(countA <= 2)
        #expect(countB <= 2)
        #expect(cleaned.first?.text == "Wir starten die Simulation.")
        #expect(cleaned.last?.text == "Weiter geht es mit dem Rotor.")
    }

    @Test("Empty and whitespace-only segments are dropped cleanly and option toggles respected")
    func testEmptySegmentsAndOptionToggles() {
        let processor = TranscriptPostProcessor()
        #expect(processor.processSegments(segments: []).isEmpty)

        let whitespaceOnly = [
            Segment(start: 0.0, end: 1.0, text: "   \n\t "),
            Segment(start: 1.0, end: 2.0, text: "")
        ]
        #expect(processor.processSegments(segments: whitespaceOnly).isEmpty)

        let noDedupOpts = PostProcessorOptions(removeNoiseTags: false, deduplicateRepetitions: false)
        let raw = [
            Segment(start: 0.0, end: 1.0, text: "[Music] Test"),
            Segment(start: 1.0, end: 2.0, text: "[Music] Test"),
            Segment(start: 2.0, end: 3.0, text: "[Music] Test")
        ]
        let preserved = processor.processSegments(segments: raw, options: noDedupOpts)
        #expect(preserved.count == 3)
        #expect(preserved[0].text == "[Music] Test")
    }

    @Test("German technical sentences starting with Übersetzung/Untertitel/Copyright/Translated are preserved while real credits are pruned")
    func testTechnicalSentencesPreservedVsRealCreditsPruned() {
        let processor = TranscriptPostProcessor()

        let realTechnical = [
            "Übersetzung von 1 zu 3 im Planetengetriebe.",
            "Übersetzung von Schritt 1 auf Schritt 2 erfolgt über die Schnittstelle.",
            "Untertitel der Baugruppe werden im Export ausgeblendet.",
            "Copyright-Hinweise im Header der STEP-Datei müssen entfernt werden.",
            "Subtitles by default are disabled in the CAD viewer.",
            "Translated by the mesh converter into STEP format."
        ]
        for sentence in realTechnical {
            let out = processor.processSegments(segments: [Segment(start: 0.0, end: 3.0, text: sentence)])
            #expect(out.count == 1, "Technical sentence falsely pruned: '\(sentence)'")
            #expect(out.first?.text == sentence)
        }

        let realCredits = [
            "Übersetzung von Max Mustermann.",
            "»Übersetzung durch KI«",
            "Übersetzung: Max Mustermann",
            "[Untertitel: Max Mustermann]",
            "Untertitel der Redaktion.",
            "Copyright WDR 2024."
        ]
        for credit in realCredits {
            let out = processor.processSegments(segments: [Segment(start: 0.0, end: 2.0, text: credit)])
            #expect(out.isEmpty, "Credit line should be pruned: '\(credit)'")
        }
    }

    @Test("Repeated Tier B boilerplate collapsed by deduplication is pruned and Unicode/soft-hyphen variants are caught")
    func testPostDedupTierBAndUnicodeNormalization() {
        let processor = TranscriptPostProcessor()

        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 2.0, text: "Vielen Dank. Vielen Dank.")
        ]).isEmpty)

        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 2.0, text: "Es heilt die gött\u{00AD}liche Kraft")
        ]).isEmpty)

        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 2.0, text: "ＥＳ ＨＥＩＬＴ ＤＩＥ ＧÖＴＴＬＩＣＨＥ ＫＲＡＦＴ")
        ]).isEmpty)
    }

    @Test("Newline-delimited and comma-delimited mixed segments strip Tier A hallucination while keeping technical speech")
    func testNewlineAndCommaMixedSegments() {
        let processor = TranscriptPostProcessor()

        let newlineMixed = processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.0, text: "Es heilt die göttliche Kraft\nDas CAD-Modell wurde vernetzt.")
        ])
        #expect(newlineMixed.count == 1)
        #expect(newlineMixed.first?.text == "Das CAD-Modell wurde vernetzt.")

        let commaMixed = processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.0, text: "Es heilt die göttliche Kraft, das CAD-Modell wurde vernetzt.")
        ])
        #expect(commaMixed.count == 1)
        #expect(commaMixed.first?.text == "das CAD-Modell wurde vernetzt.")

        let commaTrailing = processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.0, text: "Das CAD-Modell wurde vernetzt, es heilt die göttliche Kraft!")
        ])
        #expect(commaTrailing.count == 1)
        #expect(commaTrailing.first?.text == "Das CAD-Modell wurde vernetzt!")

        let hallPlusTierB = processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.0, text: "Es heilt die göttliche Kraft. Vielen Dank.")
        ])
        #expect(hallPlusTierB.isEmpty)
    }

    @Test("Inter-segment 3-cycle and 1-word ping-pong loops break cleanly while separated 1-word confirmations survive")
    func testInterSegmentCycleAndNaturalConfirmationHandling() {
        let processor = TranscriptPostProcessor()

        // 3-cycle A-B-C x 3 must not leak trailing 7th "Gamma drei."
        let threeCycle = [
            Segment(start: 0, end: 1, text: "Alpha eins."),
            Segment(start: 1, end: 2, text: "Beta zwei."),
            Segment(start: 2, end: 3, text: "Gamma drei."),
            Segment(start: 3, end: 4, text: "Alpha eins."),
            Segment(start: 4, end: 5, text: "Beta zwei."),
            Segment(start: 5, end: 6, text: "Gamma drei."),
            Segment(start: 6, end: 7, text: "Alpha eins."),
            Segment(start: 7, end: 8, text: "Beta zwei."),
            Segment(start: 8, end: 9, text: "Gamma drei.")
        ]
        let threeCycleOut = processor.processSegments(segments: threeCycle).map(\.text)
        #expect(threeCycleOut == ["Alpha eins.", "Beta zwei.", "Gamma drei.", "Alpha eins.", "Beta zwei.", "Gamma drei."])

        // 1-word ping-pong Ja-Nein x 3 must break at 3 segments without consecutive "Ja., Ja."
        let oneWordPingPong = [
            Segment(start: 0, end: 1, text: "Ja."),
            Segment(start: 1, end: 2, text: "Nein."),
            Segment(start: 2, end: 3, text: "Ja."),
            Segment(start: 3, end: 4, text: "Nein."),
            Segment(start: 4, end: 5, text: "Ja."),
            Segment(start: 5, end: 6, text: "Nein.")
        ]
        let pingPongOut = processor.processSegments(segments: oneWordPingPong).map(\.text)
        #expect(pingPongOut == ["Ja.", "Nein.", "Ja."])

        // Natural separated 1-word confirmations across technical sentences must all survive
        let naturalConvo = [
            Segment(start: 0, end: 1, text: "Ja."),
            Segment(start: 1, end: 2, text: "Wir öffnen das Mesh."),
            Segment(start: 2, end: 3, text: "Genau."),
            Segment(start: 3, end: 4, text: "Dann wählen wir Kante."),
            Segment(start: 4, end: 5, text: "Ja."),
            Segment(start: 5, end: 6, text: "Jetzt prüfen wir den Radius."),
            Segment(start: 6, end: 7, text: "Gut."),
            Segment(start: 7, end: 8, text: "Ja.")
        ]
        let naturalOut = processor.processSegments(segments: naturalConvo).map(\.text)
        #expect(naturalOut.count == 8)
    }

    @Test("Entropy collapse salvages valid leading technical sentences and >30-word unpunctuated repeats collapse to 1 copy")
    func testEntropyCollapseSalvageAndLongUnpunctuatedLoop() {
        let processor = TranscriptPostProcessor()

        // 35-word unpunctuated clause repeated 2x and 3x
        let clause35 = (1...35).map { "Wort\($0)" }.joined(separator: " ")
        let doubled = processor.processSegments(segments: [
            Segment(start: 0.0, end: 10.0, text: "\(clause35) \(clause35)")
        ])
        #expect(doubled.count == 1)
        #expect(doubled.first?.text == clause35)

        let tripled = processor.processSegments(segments: [
            Segment(start: 0.0, end: 15.0, text: "\(clause35) \(clause35) \(clause35)")
        ])
        #expect(tripled.count == 1)
        #expect(tripled.first?.text == clause35)

        // Valid leading technical sentence + collapsed hallucinated tail
        let collapsedTail = (1...15).map { i in
            "und dann ja \(i % 2 == 0 ? "so" : "mal") und dann ja"
        }.joined(separator: " ")
        let mixed = "Das Turbinenrad dreht sich mit dreitausend Umdrehungen pro Minute. \(collapsedTail)"
        let mixedOut = processor.processSegments(segments: [
            Segment(start: 0.0, end: 12.0, text: mixed)
        ])
        #expect(mixedOut.count == 1)
        #expect(mixedOut.first?.text == "Das Turbinenrad dreht sich mit dreitausend Umdrehungen pro Minute.")
    }

    @Test("Defect #1: Single-word Tier B repetitions are pruned when standalone while mixed real speech keeps word timestamps")
    func testSingleWordTierBRepetitionsPrunedAndMixedPreserved() throws {
        let processor = TranscriptPostProcessor()

        let standaloneRepeats = [
            "Amen. Amen.",
            "Amen. Amen. Amen.",
            "Amen. Amen. Amen. Amen.",
            "Danke. Danke.",
            "Danke. Danke. Danke.",
            "Dankeschön. Dankeschön. Dankeschön.",
            "Tschüss. Tschüss. Tschüss.",
            "Amen amen amen",
            "Amen, amen, amen!",
            "Es heilt die göttliche Kraft. Amen. Amen. Amen.",
            "Vielen Dank. Danke."
        ]
        for phrase in standaloneRepeats {
            let result = processor.processSegments(segments: [Segment(start: 0.0, end: 2.0, text: phrase)])
            #expect(result.isEmpty, "Standalone Tier B repetition leaked: '\(phrase)' -> \(result.map(\.text))")
        }

        // Mixed real speech + repeated Tier B collapses to 1 trailing Tier B and preserves exact word timestamps
        let words = [
            Word(text: "Das", start: 0.0, end: 0.2, confidence: 0.99),
            Word(text: "Turbinenrad", start: 0.2, end: 0.9, confidence: 0.98),
            Word(text: "dreht", start: 0.9, end: 1.3, confidence: 0.97),
            Word(text: "sich.", start: 1.3, end: 1.7, confidence: 0.96),
            Word(text: "Danke.", start: 1.8, end: 2.2, confidence: 0.95),
            Word(text: "Danke.", start: 2.3, end: 2.7, confidence: 0.90),
            Word(text: "Danke.", start: 2.8, end: 3.2, confidence: 0.88)
        ]
        let mixed = processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.5, text: "Das Turbinenrad dreht sich. Danke. Danke. Danke.", words: words)
        ])
        let surviving = try #require(mixed.first)
        #expect(mixed.count == 1)
        #expect(surviving.text == "Das Turbinenrad dreht sich. Danke.")
        #expect(surviving.words.count == 5)
        #expect(surviving.words[0].start == 0.0 && surviving.words[1].end == 0.9)
        #expect(surviving.words[4].start == 1.8 && surviving.words[4].end == 2.2)

        // Control: non-Tier-B confirmation "Ja." still preserves 1..2 occurrences
        for jaInput in ["Ja. Ja.", "Ja. Ja. Ja."] {
            let out = processor.processSegments(segments: [Segment(start: 0.0, end: 1.5, text: jaInput)])
            #expect(out.count == 1)
            let jaCount = out[0].text.components(separatedBy: "Ja").count - 1
            #expect(jaCount >= 1 && jaCount <= 2)
        }
    }

    @Test("Defect #2: German compound/inflected CAD & gearbox phrases are preserved while genuine credits (including NFKC/ALLCAPS) are pruned")
    func testDynamicCreditGermanCompoundAndTechnicalPreservation() {
        let processor = TranscriptPostProcessor()

        let technicalPhrases = [
            "Übersetzung von Planetengetrieben.",
            "Übersetzung durch Kegelradgetriebe.",
            "Übersetzung von Zahnrädern.",
            "Übersetzung von einem Stirnradgetriebe.",
            "Übersetzung von CAD-Daten.",
            "Übersetzung von Rotor und Stator.",
            "Übersetzung: Kegelradgetriebe",
            "Übersetzung: eins zu drei",
            "Untertitel von Video 1.",
            "Untertitel von links nach rechts.",
            "Untertitel von Hand korrigiert.",
            "Untertitel von Baugruppen.",
            "Untertitel im Auftrag aktivieren.",
            "Untertitel: Baugruppe A",
            "Copyright 2025 prüfen.",
            "Subtitles by clicking export.",
            "Translated by hand.",
            "Translated by the algorithm."
        ]
        for phrase in technicalPhrases {
            let out = processor.processSegments(segments: [Segment(start: 0.0, end: 2.5, text: phrase)])
            #expect(out.count == 1, "German/English technical speech falsely pruned: '\(phrase)'")
            #expect(out.first?.text == phrase)
        }

        let genuineCredits = [
            "Untertitel von Stephanie Geiges.",
            "Untertitel von ﬁnn Müller",
            "UNTERTITEL VON MAX MUSTERMANN",
            "Übersetzung von Max Mustermann.",
            "Übersetzung von Carl Jung.",
            "Subtitles by Example Studio",
            "© 2026 Example Studio",
            "Copyright WDR 2024.",
            "Untertitel im Auftrag des ZDF.",
            "Translated by DeepL."
        ]
        for credit in genuineCredits {
            let out = processor.processSegments(segments: [Segment(start: 0.0, end: 2.0, text: credit)])
            #expect(out.isEmpty, "Genuine credit leaked: '\(credit)' -> \(out.map(\.text))")
        }
    }

    @Test("Defect #3: Multi-sentence 3-word, incrementing-number, cyclic, and varied collapse tails are pruned while valid leads & word timestamps survive")
    func testCollapseTailAndPrimitivePeriodSalvage() throws {
        let processor = TranscriptPostProcessor()
        let lead = "Das Turbinenrad dreht sich mit dreitausend Umdrehungen pro Minute."

        // Case A: Lead + 18x incrementing-number 3-word sentences
        let numberedTail = (1...18).map { i in "Dann \(i % 2 == 0 ? "hier" : "dort") \(i)." }.joined(separator: " ")
        let outA = processor.processSegments(segments: [Segment(start: 0.0, end: 20.0, text: "\(lead) \(numberedTail)")])
        #expect(outA.map(\.text) == [lead])
        #expect(processor.processSegments(segments: [Segment(start: 0.0, end: 15.0, text: numberedTail)]).isEmpty)

        // Case B: Lead + 4 cycles (12 sentences) and 12 cycles (36 sentences) of 3-word 3-sentence cycle
        let cycleUnit = "Dann dort ja. Dann hier mal. Dann dort so."
        let cycle4 = Array(repeating: cycleUnit, count: 4).joined(separator: " ")
        let cycle12 = Array(repeating: cycleUnit, count: 12).joined(separator: " ")
        #expect(processor.processSegments(segments: [Segment(start: 0.0, end: 15.0, text: "\(lead) \(cycle4)")]).map(\.text) == [lead])
        #expect(processor.processSegments(segments: [Segment(start: 0.0, end: 30.0, text: "\(lead) \(cycle12)")]).map(\.text) == [lead])

        // Case C: Lead + 15x varied 3-word filler tail
        let combos = [
            "Dann hier mal.", "Dann dort ja.", "Dann hier so.",
            "Dann dort mal.", "Dann hier ja.", "Dann dort so."
        ]
        let variedTail3 = (0..<15).map { combos[$0 % combos.count] }.joined(separator: " ")
        #expect(processor.processSegments(segments: [Segment(start: 0.0, end: 15.0, text: "\(lead) \(variedTail3)")]).map(\.text) == [lead])

        // 2-word and 1-word varied tails after Lead
        let twoWordCombos = ["Dann ja.", "Dann so.", "Hier mal.", "Dort ja.", "Dann mal."]
        let variedTail2 = (0..<15).map { twoWordCombos[$0 % twoWordCombos.count] }.joined(separator: " ")
        #expect(processor.processSegments(segments: [Segment(start: 0.0, end: 15.0, text: "\(lead) \(variedTail2)")]).map(\.text) == [lead])

        let oneWordCombos = ["Ja.", "So.", "Mal.", "Dann.", "Hier.", "Dort."]
        let variedTail1 = (0..<20).map { oneWordCombos[$0 % oneWordCombos.count] }.joined(separator: " ")
        #expect(processor.processSegments(segments: [Segment(start: 0.0, end: 15.0, text: "\(lead) \(variedTail1)")]).map(\.text) == [lead])

        // Short valid technical lead salvaged with exact Word timestamps
        let shortLead = "Das Netz konvergiert."
        let shortLeadWords = [
            Word(text: "Das", start: 1.0, end: 1.2, confidence: 0.99),
            Word(text: "Netz", start: 1.2, end: 1.6, confidence: 0.98),
            Word(text: "konvergiert.", start: 1.6, end: 2.3, confidence: 0.97)
        ]
        var tailOnlyWords: [Word] = []
        for i in 1...18 {
            let base = Double(2 + i)
            tailOnlyWords.append(Word(text: "Dann", start: base, end: base + 0.2, confidence: 0.5))
            tailOnlyWords.append(Word(text: "dort", start: base + 0.2, end: base + 0.4, confidence: 0.5))
            tailOnlyWords.append(Word(text: "\(i).", start: base + 0.4, end: base + 0.6, confidence: 0.5))
        }
        let shortOut = processor.processSegments(segments: [
            Segment(start: 1.0, end: 21.0, text: "\(shortLead) \(numberedTail)", words: shortLeadWords + tailOnlyWords)
        ])
        let firstShort = try #require(shortOut.first)
        #expect(firstShort.text == shortLead)
        #expect(firstShort.words == shortLeadWords)

        // Valid numbered technical steps & short confirmations preserved 100%
        let validNumbered = "Schritt 1: Wir laden das Turbinenrad in den CAD-Viewer. Schritt 2: Wir prüfen die Schaufelgeometrie im Gittermodell. Schritt 3: Wir starten die Netzgenerierung im Kurbelgehäuse. Schritt 4: Die Strömungssimulation konvergiert sauber."
        #expect(processor.processSegments(segments: [Segment(start: 0.0, end: 12.0, text: validNumbered)]).map(\.text) == [validNumbered])
    }

    @Test("Defect #4 & alignWords: Comma-mixed dynamic credits, multi-comma pure prefixes, and leading-hallucination word alignment")
    func testCommaMixedDynamicCreditsMultiCommaPrefixAndWordAlignment() throws {
        let processor = TranscriptPostProcessor()

        // Comma-mixed dynamic credits
        let creditWords = [
            Word(text: "Die", start: 0.0, end: 0.2, confidence: 0.98),
            Word(text: "Schaufelgeometrie", start: 0.2, end: 1.1, confidence: 0.97),
            Word(text: "wird", start: 1.1, end: 1.4, confidence: 0.99),
            Word(text: "angepasst,", start: 1.4, end: 2.0, confidence: 0.96),
            Word(text: "Untertitel", start: 2.1, end: 2.5, confidence: 0.40),
            Word(text: "von", start: 2.5, end: 2.7, confidence: 0.40),
            Word(text: "Stephanie", start: 2.7, end: 3.1, confidence: 0.40),
            Word(text: "Geiges.", start: 3.1, end: 3.6, confidence: 0.40)
        ]
        let commaCreditOut = processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.6, text: "Die Schaufelgeometrie wird angepasst, Untertitel von Stephanie Geiges.", words: creditWords)
        ])
        let firstCreditOut = try #require(commaCreditOut.first)
        #expect(commaCreditOut.count == 1)
        #expect(firstCreditOut.text == "Die Schaufelgeometrie wird angepasst.")
        #expect(firstCreditOut.words.count == 4)
        #expect(firstCreditOut.words[3].start == 1.4 && firstCreditOut.words[3].end == 2.0)

        let commaCopyrightOut = processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.0, text: "Die Schaufelgeometrie wird angepasst, Copyright WDR 2024.")
        ])
        #expect(commaCopyrightOut.map(\.text) == ["Die Schaufelgeometrie wird angepasst."])

        // Multi-comma pure hallucination prefixes stripped cleanly
        let multiComma1 = processor.processSegments(segments: [
            Segment(start: 0.0, end: 4.0, text: "Das CAD-Modell wurde vernetzt, ich hoffe, es hilft, es heilt die göttliche Kraft.")
        ])
        #expect(multiComma1.map(\.text) == ["Das CAD-Modell wurde vernetzt."])

        let multiComma2 = processor.processSegments(segments: [
            Segment(start: 0.0, end: 4.0, text: "Das CAD-Modell wurde vernetzt, es hilft, es heilt die göttliche Kraft.")
        ])
        #expect(multiComma2.map(\.text) == ["Das CAD-Modell wurde vernetzt."])

        // Benign controls with commas must NEVER be stripped
        for benign in [
            "Das CAD-Modell wurde vernetzt, ich hoffe, es hilft.",
            "Das Bauteil hat, die, Kraft."
        ] {
            let out = processor.processSegments(segments: [Segment(start: 0.0, end: 3.0, text: benign)])
            #expect(out.map(\.text) == [benign])
        }

        // Leading Tier A hallucination sharing words ("die", "Kraft") with surviving speech must align to real speech timestamps
        let sharedWords = [
            Word(text: "Es", start: 0.0, end: 0.2, confidence: 0.30),
            Word(text: "heilt", start: 0.2, end: 0.5, confidence: 0.30),
            Word(text: "die", start: 0.5, end: 0.7, confidence: 0.30),
            Word(text: "göttliche", start: 0.7, end: 1.2, confidence: 0.30),
            Word(text: "Kraft.", start: 1.2, end: 1.6, confidence: 0.30),
            Word(text: "Die", start: 2.0, end: 2.2, confidence: 0.98),
            Word(text: "Kraft", start: 2.2, end: 2.6, confidence: 0.99),
            Word(text: "der", start: 2.6, end: 2.8, confidence: 0.99),
            Word(text: "Turbine", start: 2.8, end: 3.4, confidence: 0.98),
            Word(text: "ist", start: 3.4, end: 3.6, confidence: 0.99),
            Word(text: "hoch.", start: 3.6, end: 4.0, confidence: 0.98)
        ]
        let alignedOut = processor.processSegments(segments: [
            Segment(start: 0.0, end: 4.0, text: "Es heilt die göttliche Kraft. Die Kraft der Turbine ist hoch.", words: sharedWords)
        ])
        let alignedSeg = try #require(alignedOut.first)
        #expect(alignedSeg.text == "Die Kraft der Turbine ist hoch.")
        #expect(alignedSeg.words.count == 6)
        #expect(alignedSeg.words[0].start == 2.0 && alignedSeg.words[1].start == 2.2)
    }

    @Test("Defect #5: Full-window k-cycle suppresses true 3/4-cycles and 1-word bursts while preserving spaced confirmations")
    func testFullWindowPeriodicKCycleAndSpacedConfirmations() {
        let processor = TranscriptPostProcessor()

        // 0, 3, 6 separated "Ja." confirmations across distinct technical sentences -> all 9 preserved
        let spaced3 = [
            Segment(start: 0, end: 1, text: "Ja."),
            Segment(start: 1, end: 2, text: "Erster Satz über das Turbinenrad."),
            Segment(start: 2, end: 3, text: "Zweiter Satz über die Schaufel."),
            Segment(start: 3, end: 4, text: "Ja."),
            Segment(start: 4, end: 5, text: "Dritter Satz über den Stator."),
            Segment(start: 5, end: 6, text: "Vierter Satz über das Gehäuse."),
            Segment(start: 6, end: 7, text: "Ja."),
            Segment(start: 7, end: 8, text: "Fünfter Satz über das Gitter."),
            Segment(start: 8, end: 9, text: "Sechster Satz über die Kante.")
        ]
        #expect(processor.processSegments(segments: spaced3).count == 9)

        // 0, 2, 4 separated "Ja." confirmations -> all 5 preserved
        let spaced2 = [
            Segment(start: 0, end: 1, text: "Ja."),
            Segment(start: 1, end: 2, text: "Wir laden das Kegelradgetriebe."),
            Segment(start: 2, end: 3, text: "Ja."),
            Segment(start: 3, end: 4, text: "Jetzt prüfen wir die Randbedingungen."),
            Segment(start: 4, end: 5, text: "Ja.")
        ]
        #expect(processor.processSegments(segments: spaced2).count == 5)

        // 0, 4, 8 separated "Genau." and 2-word "Ja, genau." confirmations -> all 9 preserved
        for confirmation in ["Genau.", "Ja, genau."] {
            let spaced4 = [
                Segment(start: 0, end: 1, text: confirmation),
                Segment(start: 1, end: 2, text: "Satz 1 über das Netz."),
                Segment(start: 2, end: 3, text: "Satz 2 über den Rotor."),
                Segment(start: 3, end: 4, text: "Satz 3 über das Lager."),
                Segment(start: 4, end: 5, text: confirmation),
                Segment(start: 5, end: 6, text: "Satz 4 über die Welle."),
                Segment(start: 6, end: 7, text: "Satz 5 über das Gehäuse."),
                Segment(start: 7, end: 8, text: "Satz 6 über den Diffusor."),
                Segment(start: 8, end: 9, text: confirmation)
            ]
            #expect(processor.processSegments(segments: spaced4).count == 9)
        }

        // True 4-cycle [A, B, C, D] x 3 breaks at 8 segments
        var fourCycle: [Segment] = []
        for cycle in 0..<3 {
            let base = Double(cycle * 4)
            fourCycle.append(Segment(start: base + 0.0, end: base + 1.0, text: "Alpha eins."))
            fourCycle.append(Segment(start: base + 1.0, end: base + 2.0, text: "Beta zwei."))
            fourCycle.append(Segment(start: base + 2.0, end: base + 3.0, text: "Gamma drei."))
            fourCycle.append(Segment(start: base + 3.0, end: base + 4.0, text: "Delta vier."))
        }
        #expect(processor.processSegments(segments: fourCycle).count == 8)

        // Irregular 1-word burst ["Ja.", "Ja.", S1, "Ja.", "Ja.", S2, "Ja."] -> trailing burst suppressed
        let burst = [
            Segment(start: 0, end: 1, text: "Ja."),
            Segment(start: 1, end: 2, text: "Ja."),
            Segment(start: 2, end: 3, text: "Das Netz konvergiert."),
            Segment(start: 3, end: 4, text: "Ja."),
            Segment(start: 4, end: 5, text: "Ja."),
            Segment(start: 5, end: 6, text: "Der Stator ist vernetzt."),
            Segment(start: 6, end: 7, text: "Ja.")
        ]
        let burstOut = processor.processSegments(segments: burst).map(\.text)
        #expect(burstOut.filter { $0 == "Ja." }.count <= 3)
        #expect(burstOut.contains("Das Netz konvergiert."))
        #expect(burstOut.contains("Der Stator ist vernetzt."))
    }

    @Test("Iteration 4 Defect #1: Multi-word comma-separated and unpunctuated Tier B repetitions are pruned standalone and collapsed when mixed")
    func testMultiWordTierBRepetitionsAndMixedCollapse() {
        let processor = TranscriptPostProcessor()

        let standaloneMultiWordTierB = [
            "Vielen Dank, vielen Dank!",
            "Vielen Dank, vielen Dank.",
            "Vielen Dank vielen Dank",
            "Thank you, thank you.",
            "Thank you, thank you!",
            "Thank you thank you",
            "Danke schön danke schön",
            "Like and subscribe like and subscribe",
            "Danke fürs Zuschauen danke fürs Zuschauen",
            "Vielen Dank, danke!"
        ]
        for phrase in standaloneMultiWordTierB {
            let result = processor.processSegments(segments: [Segment(start: 0.0, end: 2.0, text: phrase)])
            #expect(result.isEmpty, "Multi-word Tier B repetition leaked: '\(phrase)' -> \(result.map(\.text))")
        }

        // Mixed real speech + Tier B repetitions must collapse cleanly without false pruning
        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 2.0, text: "Danke. Bitte.")
        ]).map(\.text) == ["Danke. Bitte."])

        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.0, text: "Das Turbinenrad läuft. Vielen Dank, vielen Dank.")
        ]).map(\.text) == ["Das Turbinenrad läuft. Vielen Dank."])

        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.0, text: "Das Turbinenrad läuft. Vielen Dank, vielen Dank")
        ]).map(\.text) == ["Das Turbinenrad läuft. Vielen Dank"])

        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.0, text: "Das Turbinenrad läuft. Danke, danke.")
        ]).map(\.text) == ["Das Turbinenrad läuft. Danke."])

        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.0, text: "Vielen Dank, vielen Dank, das Turbinenrad läuft.")
        ]).map(\.text) == ["Vielen Dank, das Turbinenrad läuft."])

        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 2.0, text: "Links, rechts, links, rechts")
        ]).map(\.text) == ["Links, rechts, links, rechts"])
    }

    @Test("Iteration 4 Defect #2: Principled credit classifier preserves German numeral/noun pairs & Copyright Teil/Absatz/Datei while pruning colon/initial/comma-continuation credits")
    func testPrincipledCreditClassifierAndCommaContinuations() {
        let processor = TranscriptPostProcessor()

        let preservedTechnical = [
            "Übersetzung von acht Millimetern.",
            "Übersetzung von neun Millimetern.",
            "Übersetzung von zehn Millimetern.",
            "Übersetzung von zwölf Zähnen.",
            "Übersetzung von hundert Zähnen.",
            "Übersetzung von fünfunddreißig Millimetern.",
            "Übersetzung von Kurbelwelle Nockenwelle.",
            "Übersetzung: Antriebswelle Abtriebswelle",
            "Übersetzung: Ritzel Hohlrad",
            "Untertitel: Eingangswelle Ausgangswelle",
            "Übersetzung: Schnelle Welle",
            "Übersetzung: Pumpe Düse",
            "Copyright 2025 Teil.",
            "Copyright 2025 Absatz.",
            "Copyright 2025 Datei.",
            "Copyright Absatz 2024.",
            "Copyright 2025 Version 2."
        ]
        for sentence in preservedTechnical {
            let out = processor.processSegments(segments: [Segment(start: 0.0, end: 3.0, text: sentence)])
            #expect(out.map(\.text) == [sentence], "Technical speech falsely pruned: '\(sentence)'")
        }

        let prunedCredits = [
            "Copyright: WDR 2024",
            "Untertitel von A. Müller",
            "Untertitel von H.-P. Müller",
            "Untertitel von J. K. Rowling.",
            "Untertitel von Dr. Max Mustermann.",
            "Untertitel von Hans-Peter Müller",
            "Untertitel von ﬁnn Müller",
            "Untertitel von Pascal Müller",
            "Untertitel von Max Mustermann, ARD, 2024.",
            "Altyazı M.K.! Copyright ZDF 2025. Danke. Danke. Danke."
        ]
        for credit in prunedCredits {
            let out = processor.processSegments(segments: [Segment(start: 0.0, end: 3.0, text: credit)])
            #expect(out.isEmpty, "Genuine credit leaked: '\(credit)' -> \(out.map(\.text))")
        }

        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.0, text: "Die Schaufelgeometrie wird angepasst, Copyright WDR, 2024.")
        ]).map(\.text) == ["Die Schaufelgeometrie wird angepasst."])

        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.0, text: "Die Schaufelgeometrie wird angepasst, Untertitel von Max Mustermann, ZDF.")
        ]).map(\.text) == ["Die Schaufelgeometrie wird angepasst."])

        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.0, text: "Die Schaufelgeometrie wird angepasst, Untertitel von Max Mustermann, dann prüfen wir das Netz.")
        ]).map(\.text) == ["Die Schaufelgeometrie wird angepasst, dann prüfen wir das Netz."])

        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.0, text: "Die Schaufelgeometrie wird angepasst. Untertitel von A. Müller")
        ]).map(\.text) == ["Die Schaufelgeometrie wird angepasst."])

        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.0, text: "Die Schaufelgeometrie wird angepasst. Option A. Wir prüfen das Netz.")
        ]).map(\.text) == ["Die Schaufelgeometrie wird angepasst. Option A. Wir prüfen das Netz."])

        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.0, text: "Das Gehäuse ist dicht, Altyazı M.K.! Copyright ZDF 2025. Danke. Danke. Danke.")
        ]).map(\.text) == ["Das Gehäuse ist dicht! Danke."])
    }

    @Test("Iteration 4 Defect #3: 5-6+ word collapse tails trim cleanly without absorbing closing prose, while valid short enumerations survive")
    func testLongTailCollapseBackwardExpansionAndShortEnumerationGuard() {
        let processor = TranscriptPostProcessor()
        let lead = "Das Turbinenrad dreht sich mit dreitausend Umdrehungen pro Minute."

        let tail5 = (1...15).map { "Und dann ist es \($0)." }.joined(separator: " ")
        let tail6 = (1...15).map { "Und dann ist es ja \($0)." }.joined(separator: " ")
        #expect(processor.processSegments(segments: [Segment(start: 0.0, end: 15.0, text: "\(lead) \(tail5)")]).map(\.text) == [lead])
        #expect(processor.processSegments(segments: [Segment(start: 0.0, end: 15.0, text: "\(lead) \(tail6)")]).map(\.text) == [lead])
        #expect(processor.processSegments(segments: [Segment(start: 0.0, end: 15.0, text: tail5)]).isEmpty)
        #expect(processor.processSegments(segments: [Segment(start: 0.0, end: 15.0, text: tail6)]).isEmpty)

        // Non-periodic 5-word varied filler tail starting with non-numeric filler sentence
        let varied5 = "Und dann ist es ja. " + (1...14).map { i in
            i % 3 == 0 ? "Und dann ist es mal." : (i % 3 == 1 ? "Und dann ist es so." : "Und dann ist es \(i).")
        }.joined(separator: " ")
        #expect(processor.processSegments(segments: [Segment(start: 0.0, end: 15.0, text: "\(lead) \(varied5)")]).map(\.text) == [lead])

        // Short legitimate closing prose before collapse tail must NOT be absorbed
        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 15.0, text: "Das Turbinenrad dreht sich. Es ist stabil. \(tail5)")
        ]).map(\.text) == ["Das Turbinenrad dreht sich. Es ist stabil."])

        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 15.0, text: "Es ist stabil. \(tail5)")
        ]).map(\.text) == ["Es ist stabil."])

        let netzTail = (1...15).map { "Das Netz ist \($0)." }.joined(separator: " ")
        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 15.0, text: "Das Netz ist stabil. \(netzTail)")
        ]).map(\.text) == ["Das Netz ist stabil."])

        let netzStabilTail = (1...15).map { "Das Netz ist stabil \($0)." }.joined(separator: " ")
        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 15.0, text: "Das Netz ist stabil. \(netzStabilTail)")
        ]).map(\.text) == ["Das Netz ist stabil."])

        let wertTail = (1...15).map { "Wert \($0) da." }.joined(separator: " ")
        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 15.0, text: "Die Welle dreht rund. \(wertTail)")
        ]).map(\.text) == ["Die Welle dreht rund."])

        // Valid short distinct numeric enumerations preserved verbatim
        let validEnumerations = [
            "Schritt 1. Schritt 2. Schritt 3. Schritt 4. Schritt 5. Schritt 6.",
            "Punkt 1. Punkt 2. Punkt 3. Punkt 4. Punkt 5. Punkt 6. Punkt 7. Punkt 8.",
            "Teil 1. Teil 2. Teil 3. Teil 4. Teil 5. Teil 6.",
            "Phase 1 fertig. Phase 2 fertig. Phase 3 fertig. Phase 4 fertig. Phase 5 fertig. Phase 6 fertig.",
            "1. Schritt. 2. Schritt. 3. Schritt. 4. Schritt. 5. Schritt. 6. Schritt."
        ]
        for validEnum in validEnumerations {
            #expect(processor.processSegments(segments: [
                Segment(start: 0.0, end: 10.0, text: validEnum)
            ]).map(\.text) == [validEnum], "Valid enumeration falsely pruned: '\(validEnum)'")
        }

        // Valid short enumeration followed by collapse tail keeps enumeration and trims tail
        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 20.0, text: "Schritt 1. Schritt 2. Schritt 3. Schritt 4. Schritt 5. Schritt 6. \(tail5)")
        ]).map(\.text) == ["Schritt 1. Schritt 2. Schritt 3. Schritt 4. Schritt 5. Schritt 6."])

        // Negative controls: periodic loop collapses to 1 copy; non-periodic repeating numbers are pruned
        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 8.0, text: "Schritt 1. Schritt 2. Schritt 1. Schritt 2. Schritt 1. Schritt 2.")
        ]).map(\.text) == ["Schritt 1. Schritt 2."])
        #expect(processor.processSegments(segments: [
            Segment(start: 0.0, end: 8.0, text: "Schritt 1. Schritt 2. Schritt 3. Schritt 1. Schritt 2. Schritt 1.")
        ]).isEmpty)
    }

    @Test("Iteration 4 Defect #4: Spaced 2-word confirmations survive at 0,2,4 / 0,2,4,6 / 0,3,6 / 0,4,8 and DP alignWords avoids Tier-A word theft")
    func testSpacedTwoWordConfirmationsAndDPWordAlignment() throws {
        let processor = TranscriptPostProcessor()

        // 0, 2, 4 "Ja, genau." -> 5/5 preserved
        let spaced024 = [
            Segment(start: 0, end: 1, text: "Ja, genau."),
            Segment(start: 1, end: 2, text: "Wir prüfen die Schaufelgeometrie."),
            Segment(start: 2, end: 3, text: "Ja, genau."),
            Segment(start: 3, end: 4, text: "Jetzt starten wir das Gitter."),
            Segment(start: 4, end: 5, text: "Ja, genau.")
        ]
        #expect(processor.processSegments(segments: spaced024).count == 5)

        // 0, 2, 4, 6 "Ja, genau." -> 7/7 preserved
        let spaced0246 = spaced024 + [
            Segment(start: 5, end: 6, text: "Die Randbedingungen passen."),
            Segment(start: 6, end: 7, text: "Ja, genau.")
        ]
        #expect(processor.processSegments(segments: spaced0246).count == 7)

        // 0, 3, 6 "Ja, genau." -> 9/9 preserved
        let spaced036 = [
            Segment(start: 0, end: 1, text: "Ja, genau."),
            Segment(start: 1, end: 2, text: "Erster Schritt."),
            Segment(start: 2, end: 3, text: "Zweiter Schritt."),
            Segment(start: 3, end: 4, text: "Ja, genau."),
            Segment(start: 4, end: 5, text: "Dritter Schritt."),
            Segment(start: 5, end: 6, text: "Vierter Schritt."),
            Segment(start: 6, end: 7, text: "Ja, genau."),
            Segment(start: 7, end: 8, text: "Fünfter Schritt."),
            Segment(start: 8, end: 9, text: "Sechster Schritt.")
        ]
        #expect(processor.processSegments(segments: spaced036).count == 9)

        // Dense 2-word burst caps "Ja, genau." to <= 3 while preserving technical turns
        let denseBurst = [
            Segment(start: 0, end: 1, text: "Ja, genau."),
            Segment(start: 1, end: 2, text: "Ja, genau."),
            Segment(start: 2, end: 3, text: "Das Netz konvergiert."),
            Segment(start: 3, end: 4, text: "Ja, genau."),
            Segment(start: 4, end: 5, text: "Ja, genau."),
            Segment(start: 5, end: 6, text: "Der Stator ist vernetzt."),
            Segment(start: 6, end: 7, text: "Ja, genau.")
        ]
        let burstOut = processor.processSegments(segments: denseBurst).map(\.text)
        #expect(burstOut.filter { $0 == "Ja, genau." }.count <= 3)
        #expect(burstOut.contains("Das Netz konvergiert."))
        #expect(burstOut.contains("Der Stator ist vernetzt."))

        // 1-word surviving token after stripped Tier A hallucination must align to real word (2.5..3.0), not stripped word (1.0..1.4)
        let trailingRealWords = [
            Word(text: "Es", start: 0.0, end: 0.2, confidence: 0.3),
            Word(text: "heilt", start: 0.2, end: 0.5, confidence: 0.3),
            Word(text: "die", start: 0.5, end: 0.7, confidence: 0.3),
            Word(text: "göttliche", start: 0.7, end: 1.0, confidence: 0.3),
            Word(text: "Kraft.", start: 1.0, end: 1.4, confidence: 0.3),
            Word(text: "Kraft.", start: 2.5, end: 3.0, confidence: 0.99)
        ]
        let trailingReal = try #require(processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.0, text: "Es heilt die göttliche Kraft. Kraft.", words: trailingRealWords)
        ]).first)
        #expect(trailingReal.text == "Kraft.")
        #expect(trailingReal.words == [Word(text: "Kraft.", start: 2.5, end: 3.0, confidence: 0.99)])

        // Leading 1-word real speech before stripped Tier A hallucination keeps leading timestamp (0.0..0.5)
        let leadingRealWords = [
            Word(text: "Kraft.", start: 0.0, end: 0.5, confidence: 0.99),
            Word(text: "Es", start: 1.0, end: 1.2, confidence: 0.3),
            Word(text: "heilt", start: 1.2, end: 1.5, confidence: 0.3),
            Word(text: "die", start: 1.5, end: 1.7, confidence: 0.3),
            Word(text: "göttliche", start: 1.7, end: 2.0, confidence: 0.3),
            Word(text: "Kraft.", start: 2.0, end: 2.5, confidence: 0.3)
        ]
        let leadingReal = try #require(processor.processSegments(segments: [
            Segment(start: 0.0, end: 2.5, text: "Kraft. Es heilt die göttliche Kraft.", words: leadingRealWords)
        ]).first)
        #expect(leadingReal.text == "Kraft.")
        #expect(leadingReal.words == [Word(text: "Kraft.", start: 0.0, end: 0.5, confidence: 0.99)])

        // Middle Tier A hallucination sharing words ("Die", "Kraft") with following real sentence
        let middleSharedWords = [
            Word(text: "Das", start: 0.0, end: 0.2, confidence: 0.98),
            Word(text: "Netz", start: 0.2, end: 0.5, confidence: 0.98),
            Word(text: "läuft.", start: 0.5, end: 0.8, confidence: 0.98),
            Word(text: "Es", start: 1.0, end: 1.2, confidence: 0.3),
            Word(text: "heilt", start: 1.2, end: 1.4, confidence: 0.3),
            Word(text: "die", start: 1.4, end: 1.5, confidence: 0.3),
            Word(text: "göttliche", start: 1.5, end: 1.8, confidence: 0.3),
            Word(text: "Kraft.", start: 1.8, end: 2.0, confidence: 0.3),
            Word(text: "Die", start: 2.2, end: 2.4, confidence: 0.99),
            Word(text: "Kraft", start: 2.4, end: 2.8, confidence: 0.99),
            Word(text: "ist", start: 2.8, end: 3.0, confidence: 0.99),
            Word(text: "hoch.", start: 3.0, end: 3.4, confidence: 0.99)
        ]
        let middleShared = try #require(processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.4, text: "Das Netz läuft. Es heilt die göttliche Kraft. Die Kraft ist hoch.", words: middleSharedWords)
        ]).first)
        #expect(middleShared.text == "Das Netz läuft. Die Kraft ist hoch.")
        #expect(middleShared.words.count == 7)
        #expect(middleShared.words[3].start == 2.2 && middleShared.words[3].end == 2.4)
        #expect(middleShared.words[4].start == 2.4 && middleShared.words[4].end == 2.8)

        // Comma-split copyright continuation with exact surviving word timestamps (via shared evaluateCommaClauseStripMask)
        let commaCopyrightWords = [
            Word(text: "Die", start: 0.0, end: 0.2, confidence: 0.99),
            Word(text: "Schaufelgeometrie", start: 0.2, end: 1.1, confidence: 0.99),
            Word(text: "wird", start: 1.1, end: 1.4, confidence: 0.99),
            Word(text: "angepasst,", start: 1.4, end: 2.0, confidence: 0.99),
            Word(text: "Copyright", start: 2.1, end: 2.5, confidence: 0.3),
            Word(text: "WDR,", start: 2.5, end: 2.8, confidence: 0.3),
            Word(text: "2024.", start: 2.8, end: 3.2, confidence: 0.3)
        ]
        let commaCopyright = try #require(processor.processSegments(segments: [
            Segment(start: 0.0, end: 3.2, text: "Die Schaufelgeometrie wird angepasst, Copyright WDR, 2024.", words: commaCopyrightWords)
        ]).first)
        #expect(commaCopyright.text == "Die Schaufelgeometrie wird angepasst.")
        #expect(commaCopyright.words.count == 4)
        #expect(commaCopyright.words[3].start == 1.4 && commaCopyright.words[3].end == 2.0)
    }
}
