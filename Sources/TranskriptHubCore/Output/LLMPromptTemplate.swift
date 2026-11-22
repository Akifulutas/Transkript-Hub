import Foundation

/// Ready-to-paste prompt templates for ChatGPT, Claude, Gemini, and Google NotebookLM.
public enum LLMPromptTemplate: String, CaseIterable, Identifiable, Sendable {
    case studyNotes = "study_notes"
    case actionItems = "action_items"
    case technicalSummary = "technical_summary"
    case notebookLM = "notebook_lm"
    
    public var id: String { rawValue }
    
    public var systemImage: String {
        switch self {
        case .studyNotes: return "book.closed.fill"
        case .actionItems: return "checklist"
        case .technicalSummary: return "cpu.fill"
        case .notebookLM: return "sparkles.rectangle.stack.fill"
        }
    }
    
    public func displayTitle(languageCode: String = "tr") -> String {
        switch languageCode.lowercased() {
        case "en":
            switch self {
            case .studyNotes: return "Study Notes & Flashcards"
            case .actionItems: return "Meeting Action Items"
            case .technicalSummary: return "Technical Summary"
            case .notebookLM: return "NotebookLM Source Pack"
            }
        case "de":
            switch self {
            case .studyNotes: return "Lernnotizen & Karteikarten"
            case .actionItems: return "Meeting-Aufgaben & Beschlüsse"
            case .technicalSummary: return "Technische Zusammenfassung"
            case .notebookLM: return "NotebookLM-Quellenpaket"
            }
        default:
            switch self {
            case .studyNotes: return "Ders Notu Çıkar"
            case .actionItems: return "Toplantı Aksiyon Maddeleri"
            case .technicalSummary: return "Teknik Özet"
            case .notebookLM: return "NotebookLM Kaynak Paketi"
            }
        }
    }
    
    /// Builds a structured, ready-to-paste payload combining prompt instructions,
    /// source metadata, video description (without duplication), and transcript body.
    public func formatPayload(
        title: String? = nil,
        sourceURL: String? = nil,
        videoDescription: String? = nil,
        transcript: String,
        isBatch: Bool = false,
        languageCode: String = "tr"
    ) -> String {
        let body = OutputFormatter.ensureYouTubeDescriptionIncluded(
            transcript: transcript,
            description: videoDescription
        )
        
        var headerLines: [String] = []
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            headerLines.append("# \(title)")
        }
        if let url = sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
            headerLines.append("Kaynak: \(url)")
        }
        let metadataBlock = headerLines.isEmpty ? "" : headerLines.joined(separator: "\n") + "\n\n"
        
        if self == .notebookLM {
            let intro: String
            switch languageCode.lowercased() {
            case "en":
                intro = isBatch
                    ? "<!-- NotebookLM Multi-Source Knowledge Pack — Transkript Hub -->"
                    : "<!-- NotebookLM Source Document — Transkript Hub -->"
            case "de":
                intro = isBatch
                    ? "<!-- NotebookLM Mehrquellen-Wissenspaket — Transkript Hub -->"
                    : "<!-- NotebookLM Quelldokument — Transkript Hub -->"
            default:
                intro = isBatch
                    ? "<!-- NotebookLM Çoklu Kaynak Paketi — Transkript Hub -->"
                    : "<!-- NotebookLM Kaynak Belgesi — Transkript Hub -->"
            }
            return """
            \(intro)

            \(metadataBlock)\(body)
            """.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        let promptInstruction = instructionText(isBatch: isBatch, languageCode: languageCode)
        return """
        \(promptInstruction)

        ================================================================================
        \(metadataBlock)\(body)
        ================================================================================
        """.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func instructionText(isBatch: Bool, languageCode: String) -> String {
        let lang = languageCode.lowercased()
        switch self {
        case .studyNotes:
            if lang == "en" {
                return isBatch
                    ? """
                    You are an expert educator. Synthesize the following transcripts (including video descriptions and chapter headings) into structured study notes:
                    1. High-level overview connecting all sources
                    2. Section-by-section structured notes with key definitions and formulas/examples
                    3. 5–10 active-recall Q&A flashcards for exam review
                    4. Concrete takeaways & terms to memorize
                    """
                    : """
                    You are an expert educator. Turn the following transcript (including video description and chapter headings) into clear, structured study notes:
                    1. Executive overview (3–5 bullets)
                    2. Topic-by-topic structured notes preserving chapter flow, definitions, and concrete examples
                    3. 5–8 active-recall Q&A flashcards for review
                    4. Key terms & concepts glossary
                    """
            } else if lang == "de" {
                return isBatch
                    ? """
                    Du bist ein erfahrener Dozent. Erstelle aus den folgenden Transkripten (inkl. Videobeschreibungen und Kapiteln) strukturierte Lernnotizen:
                    1. Überblick und Zusammenhang aller Quellen
                    2. Kapitelweise strukturierte Notizen mit Definitionen und Beispielen
                    3. 5–10 Lernkarten (Frage/Antwort) zur Prüfungsvorbereitung
                    4. Zentrale Fachbegriffe und Kernaussagen
                    """
                    : """
                    Du bist ein erfahrener Dozent. Erstelle aus dem folgenden Transkript (inkl. Videobeschreibung und Kapiteln) klare, strukturierte Lernnotizen:
                    1. Kurzer Überblick (3–5 Stichpunkte)
                    2. Themen- und kapitelweise strukturierte Notizen mit Definitionen und Beispielen
                    3. 5–8 Lernkarten (Frage/Antwort) zur Wiederholung
                    4. Glossar der wichtigsten Begriffe
                    """
            } else {
                return isBatch
                    ? """
                    Aşağıdaki birden fazla kaynaktan oluşan transkriptleri (video açıklamaları ve bölüm başlıkları dahil) eksiksiz ve düzenli bir **Ders Notu** haline getir:
                    1. Tüm kaynakları birleştiren kısa genel özet
                    2. Bölüm başlıklarına uygun, madde işaretli ve kavram tanımlı detaylı ders notları
                    3. Konuyu pekiştirmek için 5–10 adet Soru-Cevap (Flashcard) çalışma kartı
                    4. Mutlaka bilinmesi gereken temel terimler ve kritik çıkarımlar
                    """
                    : """
                    Aşağıdaki transkripti (video açıklaması ve bölüm başlıkları dahil) eksiksiz ve düzenli bir **Ders Notu** haline getir:
                    1. 3–5 maddelik genel özet
                    2. Bölüm başlıklarını takip eden, kavram tanımları ve somut örnekler içeren düzenli ders notları
                    3. Sınav / tekrar için 5–8 adet Soru-Cevap (Flashcard) çalışma kartı
                    4. Kritik kavramlar sözlüğü ve akılda kalması gerekenler
                    """
            }
            
        case .actionItems:
            if lang == "en" {
                return """
                Analyze the following transcript and extract an executive meeting breakdown:
                1. Key Decisions Made
                2. Action Items (Task | Owner if mentioned | Deadline/Priority if mentioned)
                3. Open Questions, Risks & Blockers
                4. Concise Chronological Summary
                """
            } else if lang == "de" {
                return """
                Analysiere das folgende Transkript und erstelle eine strukturierte Meeting-Auswertung:
                1. Getroffene Entscheidungen
                2. Konkrete Aufgaben / Action Items (Aufgabe | Verantwortlich | Termin/Priorität falls genannt)
                3. Offene Fragen, Risiken & Blocker
                4. Kurze Zusammenfassung der wichtigsten Punkte
                """
            } else {
                return """
                Aşağıdaki transkripti analiz et ve net bir **Toplantı & Aksiyon Çıktısı** oluştur:
                1. Alınan Kesin Kararlar
                2. Aksiyon Maddeleri (Görev | Sorumlu kişi belirtildiyse | Tarih/Öncelik belirtildiyse)
                3. Açık Kalan Sorular, Riskler ve Engeller
                4. Kısa Yönetici Özeti
                """
            }
            
        case .technicalSummary:
            if lang == "en" {
                return """
                Produce a senior-level Technical Summary from the following transcript and description:
                1. Core Problem & Architecture / Approach
                2. Exact Tools, Libraries, Models, APIs, Commands, and Metrics mentioned (preserve exact spelling/numbers)
                3. Key Trade-offs, Pitfalls & Best Practices highlighted
                4. Concise Actionable Engineering Takeaways
                """
            } else if lang == "de" {
                return """
                Erstelle eine präzise technische Zusammenfassung aus dem folgenden Transkript (inkl. Beschreibung):
                1. Kernproblem, Architektur & Lösungsansatz
                2. Genannte Tools, Bibliotheken, Modelle, APIs, Befehle und Messwerte (exakte Schreibweise/Zahlen beibehalten)
                3. Wichtige Trade-offs, Fallstricke & Best Practices
                4. Konkrete technische Empfehlungen
                """
            } else {
                return """
                Aşağıdaki transkript ve video açıklamasından kapsamlı bir **Teknik Özet** çıkar:
                1. Temel Problem, Mimari ve Yaklaşım
                2. Bahsedilen Araçlar, Kütüphaneler, Modeller, Komutlar, Linkler ve Sayısal Ölçümler (orijinal adları ve sayıları koruyarak)
                3. Vurgulanan Avantajlar, Dezavantajlar (Trade-off'lar) ve Dikkat Edilmesi Gereken Tuzaklar
                4. Uygulanabilir Teknik Çıkarımlar
                """
            }
            
        case .notebookLM:
            return ""
        }
    }
}
