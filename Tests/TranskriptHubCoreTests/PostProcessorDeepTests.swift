import Foundation
import Testing
@testable import TranskriptHubCore

@Suite("Transkript Son İşleyici (PostProcessor) Kapsamlı Test Paketi")
struct PostProcessorDeepTests {
    
    @Test("Gürültü ve arka plan ses etiketlerinin temizlenmesi")
    func testNoiseTagsRemovalComprehensive() {
        let processor = TranscriptPostProcessor()
        let rawSegments = [
            Segment(start: 0.0, end: 2.0, text: "[Müzik]"),
            Segment(start: 2.0, end: 5.0, text: "Merhaba değerli izleyiciler [Alkış] programımıza hoş geldiniz."),
            Segment(start: 5.0, end: 7.0, text: "(Gülüşmeler) Bugün yapay zeka konuşacağız."),
            Segment(start: 7.0, end: 9.0, text: "[Music] [Applause] Devam ediyoruz."),
            Segment(start: 9.0, end: 11.0, text: "*müzik* Arka plan sesi temizlenmeli."),
            Segment(start: 11.0, end: 13.0, text: "♪ neşeli müzik ♪"),
            Segment(start: 13.0, end: 15.0, text: "Sonuç cümlesi.")
        ]
        
        let result = processor.process(segments: rawSegments)
        
        // Etiketler silinmiş olmalı
        #expect(!result.contains("[Müzik]"))
        #expect(!result.contains("[Alkış]"))
        #expect(!result.contains("(Gülüşmeler)"))
        #expect(!result.contains("[Music]"))
        #expect(!result.contains("[Applause]"))
        #expect(!result.contains("*müzik*"))
        #expect(!result.contains("♪"))
        
        // Asıl konuşma korunmalı
        #expect(result.contains("Merhaba değerli izleyiciler"))
        #expect(result.contains("programımıza hoş geldiniz."))
        #expect(result.contains("Bugün yapay zeka konuşacağız."))
        #expect(result.contains("Devam ediyoruz."))
        #expect(result.contains("Sonuç cümlesi."))
    }
    
    @Test("Whisper halüsinasyonu olan tekrar döngülerinin kırılması (Repetition Loop Break)")
    func testRepetitionLoopBreak() {
        let processor = TranscriptPostProcessor()
        var segments: [Segment] = [
            Segment(start: 0.0, end: 2.0, text: "Giriş yapılıyor."),
            Segment(start: 2.0, end: 4.0, text: "Konu anlatılıyor.")
        ]
        
        // 10 kez art arda aynı halüsinasyon cümlesini ekle
        for i in 1...10 {
            segments.append(
                Segment(start: Double(4 + i), end: Double(5 + i), text: "Lütfen kanala abone olun.")
            )
        }
        
        segments.append(Segment(start: 20.0, end: 22.0, text: "Kapanış yapıldı."))
        
        let result = processor.process(segments: segments)
        
        // Cümle 10 kez yerine en fazla 2 kez yer almalı
        let occurrences = result.components(separatedBy: "Lütfen kanala abone olun.").count - 1
        #expect(occurrences <= 2, "Tekrar döngüsü kırılmadı, adet: \(occurrences)")
        #expect(result.contains("Giriş yapılıyor."))
        #expect(result.contains("Kapanış yapıldı."))
    }
    
    @Test("Metin sessizlik eşiğine göre paragraflara ayrıştırma")
    func testParagraphChunkingWithSilenceThreshold() {
        let processor = TranscriptPostProcessor()
        let segments = [
            Segment(start: 0.0, end: 5.0, text: "Birinci konu ele alınıyor."),
            Segment(start: 5.0, end: 10.0, text: "İkinci cümle burada bitiyor."),
            // 20 saniyelik uzun sessizlik boşluğu -> eşik 2.0 saniye olunca yeni paragraf olmalı
            Segment(start: 30.0, end: 35.0, text: "Uzun aradan sonra yeni konu başladı.")
        ]
        
        let options = PostProcessorOptions(paragraphSilenceThreshold: 2.0)
        let result = processor.process(segments: segments, options: options)
        
        // İki paragraf çift satır atlama (\n\n) ile ayrılmalıdır
        let paragraphs = result.components(separatedBy: "\n\n")
        #expect(paragraphs.count >= 2, "Paragraf ayrımı oluşmadı")
        #expect(paragraphs[0].contains("Birinci konu"))
        #expect(paragraphs[1].contains("Uzun aradan sonra"))
    }
}
