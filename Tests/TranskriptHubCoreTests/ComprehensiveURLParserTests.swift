import Foundation
import Testing
@testable import TranskriptHubCore

@Suite("URL Parser Kapsamlı Test Paketi")
struct ComprehensiveURLParserTests {
    
    @Test("Tüm geçerli YouTube URL formatlarını tanıma")
    func testAllSupportedFormats() {
        let testCases: [(url: String, expectedID: String)] = [
            // Standart web
            ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("http://www.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            
            // Kısa linkler (youtu.be)
            ("https://youtu.be/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("http://youtu.be/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://youtu.be/dQw4w9WgXcQ?t=120", "dQw4w9WgXcQ"),
            ("https://youtu.be/dQw4w9WgXcQ?feature=share", "dQw4w9WgXcQ"),
            ("https://youtu.be/dQw4w9WgXcQ?si=abcdef123456", "dQw4w9WgXcQ"),
            
            // Shorts linkleri
            ("https://www.youtube.com/shorts/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://youtube.com/shorts/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://m.youtube.com/shorts/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://youtube.com/shorts/dQw4w9WgXcQ?feature=share", "dQw4w9WgXcQ"),
            
            // Mobil ve Müzik
            ("https://m.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://music.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=RDAMVM", "dQw4w9WgXcQ"),
            
            // Canlı yayın & Embed
            ("https://www.youtube.com/live/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://youtube.com/live/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://www.youtube.com/embed/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            
            // Karmaşık query parametreleri
            ("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLrAXtmErZgOdP_8GztsuKi9nrraNbKKp4&index=1", "dQw4w9WgXcQ"),
            ("https://www.youtube.com/watch?app=desktop&v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://www.youtube.com/watch?feature=youtu.be&v=dQw4w9WgXcQ&t=5m30s", "dQw4w9WgXcQ"),
            
            // Çeşitli karakter kombinasyonları içeren 11 karakterlik ID'ler
            ("https://www.youtube.com/watch?v=1234567890A", "1234567890A"),
            ("https://www.youtube.com/watch?v=a-b_c12345Z", "a-b_c12345Z"),
            ("https://www.youtube.com/watch?v=__________1", "__________1")
        ]
        
        for item in testCases {
            let parsed = URLParser.parseSingle(item.url)
            #expect(parsed != nil, "Ayrıştırılamadı: \(item.url)")
            #expect(parsed?.videoID == item.expectedID, "ID uyuşmadı: \(item.url)")
            #expect(parsed?.canonicalURL == "https://www.youtube.com/watch?v=\(item.expectedID)")
        }
    }
    
    @Test("Geçersiz URL'leri ve yabancı siteleri reddetme")
    func testInvalidAndMaliciousURLs() {
        let invalidInputs = [
            // Phishing / Yanıltıcı alan adları
            "https://youtube.com.attacker.com/watch?v=dQw4w9WgXcQ",
            "https://fake-youtube.com/watch?v=dQw4w9WgXcQ",
            "https://notyoutube.com/watch?v=dQw4w9WgXcQ",
            "https://vimeo.com/12345678901",
            "https://dailymotion.com/video/x7tgad0",
            
            // Hatalı uzunlukta ID'ler
            "https://www.youtube.com/watch?v=short",          // 5 karakter
            "https://www.youtube.com/watch?v=toolongvideo123", // 15 karakter
            "https://youtu.be/abc",                           // 3 karakter
            "https://youtu.be/123456789012345",               // 15 karakter
            
            // Boş parametreler
            "https://www.youtube.com/watch?v=",
            "https://www.youtube.com/watch",
            "https://youtu.be/",
            "https://www.youtube.com/shorts/",
            
            // Kanal ve Kullanıcı sayfaları (Video ID değil)
            "https://www.youtube.com/@mkbhd",
            "https://www.youtube.com/channel/UCBJycsmduvYEL83R_U4JriQ",
            "https://www.youtube.com/c/Apple",
            
            // Rastgele metinler
            "",
            "   ",
            "https://google.com",
            "youtube linki kopyaladım ama bu bir url değil"
        ]
        
        for input in invalidInputs {
            let parsed = URLParser.parseSingle(input)
            #expect(parsed == nil, "Geçersiz giriş kabul edilmemeliydi: \(input)")
        }
    }
    
    @Test("Kirli ve karışık metinlerden toplu link ayıklama ve tekilleştirme")
    func testBulkExtractionFromDirtyText() {
        let dirtyText = """
        Merhaba arkadaşlar, bugünkü podcast bölümlerimiz:
        1. Bölüm: [İzle](https://www.youtube.com/watch?v=dQw4w9WgXcQ)
        2. Bölüm için şu linke bakın: https://youtu.be/jNQXAC9IVRw?si=test
        Ayrıca şu shorts videosu çok iyi: https://youtube.com/shorts/3JZ_D3ELwOQ
        Tekrar birinci video: https://m.youtube.com/watch?v=dQw4w9WgXcQ
        Bu da geçersiz bir link: https://vimeo.com/99999999 ve https://google.com
        Son video: <a href="https://www.youtube.com/watch?v=9bZkp7q19f0">Gangnam Style</a>
        """
        
        let extracted = URLParser.parseBulk(dirtyText)
        
        // 4 benzersiz video olmalı (dQw4w9WgXcQ tekrar ettiği için tekilleştirilmeli)
        #expect(extracted.count == 4)
        
        let ids = extracted.map(\.videoID)
        #expect(ids.contains("dQw4w9WgXcQ"))
        #expect(ids.contains("jNQXAC9IVRw"))
        #expect(ids.contains("3JZ_D3ELwOQ"))
        #expect(ids.contains("9bZkp7q19f0"))
    }
}
