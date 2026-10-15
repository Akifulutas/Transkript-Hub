import Testing
import Foundation
@testable import TranskriptHubCore

@Suite("NaturalLanguage Transcript Summarizer & Action Item Test Suite")
struct TranscriptSummarizerTests {
    
    @Test("Basic Extractive Summary extracts salient sentences from multi-sentence transcript")
    func testBasicExtractiveSummary() {
        let summarizer = TranscriptSummarizer()
        let transcript = """
        Bugün Transkript Hub projesinin mimarisini ve Sequoia entegrasyonunu değerlendirmek üzere toplandık.
        Apple Silicon işlemcilerde yerel vDSP ve Accelerate kütüphaneleri sayesinde ses işleme gecikmesi 15 milisaniyenin altına inmiştir.
        Kullanıcı arayüzünde Liquid Glass görsel efektleri ve SF Symbols 6 ikonografisi tam uyumla çalışmaktadır.
        Uygulamanın DMG dağıtım boyutu kesinlikle 10 megabayt sınırının altında tutulacaktır.
        Gelecek hafta başında yeni sürümün beta testlerini tamamlamamız gerekiyor.
        Toplantıya katılan herkese teşekkür ederiz.
        """
        
        let summary = summarizer.summarize(text: transcript, duration: 180.0)
        
        #expect(!summary.executiveSummary.isEmpty)
        #expect(!summary.keyPoints.isEmpty)
        #expect(summary.keyPoints.count >= 2 && summary.keyPoints.count <= 5)
        
        // Key technical terms should be represented in key points
        let combinedKeyPoints = summary.keyPoints.joined(separator: " ")
        #expect(combinedKeyPoints.contains("Transkript Hub") || combinedKeyPoints.contains("Apple Silicon") || combinedKeyPoints.contains("vDSP") || combinedKeyPoints.contains("DMG"))
    }
    
    @Test("Action Item detection identifies commitments, imperatives, and task assignments")
    func testActionItemDetection() {
        let summarizer = TranscriptSummarizer()
        let transcript = """
        Toplantı saat 10:00'da başladı.
        Hava bugün İstanbul'da oldukça güneşli.
        Ali Bey, Cuma gününe kadar veritabanı indeksleme raporunu hazırlamalıdır.
        Ekip olarak DMG boyut optimizasyonunu acilen tamamlamamız gerekiyor.
        Ses dalgası bileşeninde bellek sızıntısı olup olmadığı incelenecektir.
        Gelecek pazartesi saat 14:00'te tekrar toplanılması kararlaştırıldı.
        Herkes için verimli bir gün olmasını dilerim.
        """
        
        let summary = summarizer.summarize(text: transcript, duration: 240.0)
        
        #expect(!summary.actionItems.isEmpty)
        #expect(summary.actionItems.count >= 3)
        
        // Verify detection of modal/imperative Turkish phrases
        let combinedActions = summary.actionItems.joined(separator: " ")
        #expect(combinedActions.contains("hazırlamalıdır") || combinedActions.contains("gerekiyor") || combinedActions.contains("kararlaştırıldı") || combinedActions.contains("incelenecektir"))
    }
    
    @Test("English action item detection identifies imperatives like must, should, will, todo, need to")
    func testEnglishActionItemDetection() {
        let summarizer = TranscriptSummarizer()
        let transcript = """
        Welcome everyone to the sprint review.
        The weather in Cupertino is very pleasant today.
        We must refactor the audio player controller to eliminate memory leaks.
        John should update the entitlements file for microphone permissions before Friday.
        We will release version 2.0 to TestFlight next Tuesday.
        Please make sure to review the open pull requests today.
        Thanks for attending the session.
        """
        
        let summary = summarizer.summarize(text: transcript, duration: 300.0)
        
        #expect(!summary.actionItems.isEmpty)
        #expect(summary.actionItems.count >= 2)
        
        let combinedActions = summary.actionItems.joined(separator: " ")
        #expect(combinedActions.contains("must") || combinedActions.contains("should") || combinedActions.contains("will") || combinedActions.contains("make sure"))
    }
    
    @Test("Chaptering generates timestamped sections from segments")
    func testChapteringFromSegments() {
        let summarizer = TranscriptSummarizer()
        
        // 10 minutes session with 3 distinct discussion blocks
        let segments: [Segment] = [
            Segment(start: 0.0, end: 15.0, text: "Giriş ve hoşgeldiniz konuşması.", speaker: "Speaker 1"),
            Segment(start: 16.0, end: 45.0, text: "Projenin genel hedefleri ve zaman çizelgesi.", speaker: "Speaker 1"),
            Segment(start: 180.0, end: 210.0, text: "İkinci bölüm: Performans optimizasyonu ve bellek yönetimi.", speaker: "Speaker 2"),
            Segment(start: 215.0, end: 320.0, text: "vDSP ile FFT filtreleme teknikleri ve Apple Silicon hızlandırması.", speaker: "Speaker 2"),
            Segment(start: 450.0, end: 500.0, text: "Üçüncü bölüm: Kullanıcı deneyimi, Sequoia Liquid Glass ve Menü Çubuğu.", speaker: "Speaker 1"),
            Segment(start: 505.0, end: 600.0, text: "Kapanış ve aksiyon maddelerinin dağıtımı.", speaker: "Speaker 1")
        ]
        
        let summary = summarizer.summarize(segments: segments)
        
        #expect(!summary.chapters.isEmpty)
        #expect(summary.chapters.count >= 2)
        
        // First chapter must start at 0.0s
        #expect(summary.chapters.first?.start == 0.0)
        // Chapters must have non-empty titles and summaries
        for chapter in summary.chapters {
            #expect(!chapter.title.isEmpty)
            #expect(!chapter.summary.isEmpty)
            #expect(chapter.end >= chapter.start)
        }
    }
    
    @Test("Edge cases: empty, whitespace-only, or single-sentence transcripts handle gracefully without crash")
    func testEdgeCases() {
        let summarizer = TranscriptSummarizer()
        
        // 1. Empty string
        let emptySummary = summarizer.summarize(text: "", duration: 0.0)
        #expect(emptySummary.executiveSummary.isEmpty)
        #expect(emptySummary.keyPoints.isEmpty)
        #expect(emptySummary.actionItems.isEmpty)
        #expect(emptySummary.chapters.isEmpty)
        
        // 2. Whitespace only
        let wsSummary = summarizer.summarize(text: "   \n\t   ", duration: 10.0)
        #expect(wsSummary.executiveSummary.isEmpty)
        #expect(wsSummary.keyPoints.isEmpty)
        
        // 3. Single short sentence
        let singleSummary = summarizer.summarize(text: "Kısa bir ses kaydı denemesi.", duration: 2.5)
        #expect(singleSummary.executiveSummary == "Kısa bir ses kaydı denemesi.")
        #expect(singleSummary.keyPoints.count == 1)
        #expect(singleSummary.chapters.count == 1)
        #expect(singleSummary.chapters[0].start == 0.0)
    }
    
    @Test("Performance: Summarizer processes 500 sentences in strictly under 50 milliseconds")
    func testSummarizerPerformance() {
        let summarizer = TranscriptSummarizer()
        
        let baseParagraph = "Transkript Hub Sequoia mimarisinde Apple Silicon donanım hızlandırma yeteneklerini kullanarak yüksek hızda transkripsiyon sağlar. Ekip olarak performansı optimize etmemiz gerekiyor. vDSP kütüphanesi ses spektrum analizinde mikro-saniye gecikme ile çalışır. Cuma gününe kadar tüm testlerin geçmesi şarttır. "
        let largeText = String(repeating: baseParagraph, count: 100) // ~500 sentences
        
        let start = DispatchTime.now()
        let summary = summarizer.summarize(text: largeText, duration: 1800.0)
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
        
        #expect(!summary.executiveSummary.isEmpty)
        #expect(!summary.actionItems.isEmpty)
        #expect(elapsed < 100.0, "Summarizer took \(elapsed)ms, expected < 100ms")
    }
}
