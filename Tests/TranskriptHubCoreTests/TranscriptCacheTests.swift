import Testing
import Foundation
import GRDB
@testable import TranskriptHubCore

@Suite("Akıllı Önbellek ve Tekilleştirme (TranscriptCacheManager) Test Paketi")
struct TranscriptCacheTests {
    
    private func makeTestDatabase() throws -> AppDatabase {
        var config = Configuration()
        config.qos = .userInitiated
        let queue = try DatabaseQueue(configuration: config)
        return try AppDatabase(queue)
    }
    
    @Test("YouTube external_id ile önbellek eşleşmesi")
    func testYouTubeCacheHit() async throws {
        let db = try makeTestDatabase()
        let cache = TranscriptCacheManager(database: db)
        
        await cache.save(
            externalID: "TEST_VIDEO_123",
            title: "Harika Swift Dersi",
            durationSec: 120.5,
            outputPath: "/path/to/output.md",
            transcriptText: "Merhaba dünya, bu bir test transkriptidir."
        )
        
        let found = await cache.findCached(
            title: "Harika Swift Dersi",
            durationSec: 120.5,
            externalID: "TEST_VIDEO_123"
        )
        
        #expect(found != nil)
        #expect(found?.transcriptText == "Merhaba dünya, bu bir test transkriptidir.")
        #expect(found?.externalID == "TEST_VIDEO_123")
    }
    
    @Test("Ses dosyalarında isim ve süre (uzunluk) ile akıllı eşleşme")
    func testAudioDurationAndNameMatch() async throws {
        let db = try makeTestDatabase()
        let cache = TranscriptCacheManager(database: db)
        
        // Örnek ses kaydı: 45.2 saniye
        await cache.save(
            externalID: "/Users/test/Ses Kaydı 1.m4a",
            title: "Ses Kaydı 1",
            durationSec: 45.2,
            sourcePath: "/Users/test/Ses Kaydı 1.m4a",
            outputPath: "/Users/test/Transkript/Ses Kaydı 1.md",
            transcriptText: "Bu ses kaydının ilk deşifresi."
        )
        
        // 1. Aynı isim ve süre (0.2 sn tolerans içinde) -> Eşleşmeli!
        let match1 = await cache.findCached(
            title: "Ses Kaydı 1",
            durationSec: 45.3,
            sourcePath: "/Users/other/Downloads/Ses Kaydı 1.m4a"
        )
        #expect(match1 != nil)
        #expect(match1?.transcriptText == "Bu ses kaydının ilk deşifresi.")
        
        // 2. Aynı isim ama tamamen farklı süre (örn. 120 sn) -> Eşleşmemeli! (Kullanıcı şartı: süreye de bakılmalı)
        let mismatchDuration = await cache.findCached(
            title: "Ses Kaydı 1",
            durationSec: 120.0,
            sourcePath: "/Users/other/Downloads/Ses Kaydı 1.m4a"
        )
        #expect(mismatchDuration == nil)
        
        // 3. Aynı süre ama tamamen ilgisiz isim -> Eşleşmemeli
        let mismatchName = await cache.findCached(
            title: "Alakasız Dosya",
            durationSec: 45.2,
            sourcePath: "/Users/test/Alakasız.m4a"
        )
        #expect(mismatchName == nil)
    }
    
    @Test("Eski tamamlanmış job kayıtlarından otomatik kurtarma ve önbelleğe alma")
    func testFallbackToCompletedJobs() async throws {
        let db = try makeTestDatabase()
        let cache = TranscriptCacheManager(database: db)
        
        // Veritabanına doğrudan eski bir completed job ve transcript_section ekleyelim
        try await db.dbQueue.write { db in
            try BatchRecord(
                id: "OLD_BATCH",
                createdAt: ISO8601DateFormatter().string(from: Date()),
                kind: .files,
                expectedCount: 1,
                state: .completed,
                outputPath: "/old/batch.md"
            ).insert(db)
            
            try JobRecord(
                id: "OLD_JOB_1",
                batchID: "OLD_BATCH",
                sequence: 1,
                sourceType: "audio",
                sourcePath: "/old/sesli_not.m4a",
                title: "sesli_not",
                durationSec: 88.0,
                state: .completed
            ).insert(db)
            
            try TranscriptSectionRecord(
                jobID: "OLD_JOB_1",
                text: "Eski veritabanından başarıyla kurtarılan transkript metni."
            ).insert(db)
        }
        
        let recovered = await cache.findCached(
            title: "sesli_not",
            durationSec: 88.0,
            sourcePath: "/Users/akif/Desktop/sesli_not.m4a"
        )
        
        #expect(recovered != nil)
        #expect(recovered?.transcriptText == "Eski veritabanından başarıyla kurtarılan transkript metni.")
    }
}
