import Foundation
import Testing
@testable import TranskriptHubCore

@Test func testOutputFormatterStructure() throws {
    let metadata = BatchExportMetadata(
        batchID: "TEST-UUID-1234",
        sourceType: "YouTube",
        totalCount: 2,
        completedCount: 1,
        failedCount: 1,
        modelName: "tiny",
        language: "auto"
    )
    
    let items = [
        BatchItemSection(
            sequence: 1,
            totalCount: 2,
            title: "Başarılı Video",
            channel: "Test Kanalı",
            durationSec: 125,
            url: "https://www.youtube.com/watch?v=11111111111",
            language: "tr",
            transcriptText: "Bu birinci videonun transkriptidir.",
            errorMessage: nil
        ),
        BatchItemSection(
            sequence: 2,
            totalCount: 2,
            title: "Hatalı Video",
            channel: "Test Kanalı 2",
            durationSec: nil,
            url: "https://www.youtube.com/watch?v=22222222222",
            language: nil,
            transcriptText: nil,
            errorMessage: "Video kullanılamıyor (silinmiş veya gizli)"
        )
    ]
    
    let formatted = OutputFormatter.formatBatch(metadata: metadata, items: items)
    
    #expect(formatted.contains("TRANSKRIPT HUB EXPORT"))
    #expect(formatted.contains("Format-Version: 1"))
    #expect(formatted.contains("Batch-ID: TEST-UUID-1234"))
    #expect(formatted.contains("Item-Count: 2"))
    #expect(formatted.contains("Completed: 1"))
    #expect(formatted.contains("Failed: 1"))
    #expect(formatted.contains("VIDEO 1 / 2"))
    #expect(formatted.contains("TITLE: Başarılı Video"))
    #expect(formatted.contains("Bu birinci videonun transkriptidir."))
    #expect(formatted.contains("VIDEO 2 / 2"))
    #expect(formatted.contains("STATUS: İŞLENEMEDİ — Video kullanılamıyor (silinmiş veya gizli)"))
}
