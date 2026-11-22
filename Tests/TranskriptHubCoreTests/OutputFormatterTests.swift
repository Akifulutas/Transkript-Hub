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

@Test func testOutputFormatterYouTubeDescriptionSingleAndBatch() throws {
    let rawTranscript = "Merhaba, bugün Swift 6 anlatıyoruz."
    let description = "Video kaynakları:\nhttps://swift.org\n00:00 Giriş\n02:15 Örnek"
    
    // 1. Single video formatting with description
    let singleFormatted = OutputFormatter.formatYouTubeTranscript(
        transcript: rawTranscript,
        description: description
    )
    #expect(singleFormatted.contains("VİDEO AÇIKLAMASI:"))
    #expect(singleFormatted.contains("https://swift.org"))
    #expect(singleFormatted.contains("TRANSKRİPT:"))
    #expect(singleFormatted.contains(rawTranscript))
    
    // 2. Idempotency (must not duplicate header/description)
    let idempotent = OutputFormatter.ensureYouTubeDescriptionIncluded(
        transcript: singleFormatted,
        description: description
    )
    #expect(idempotent == singleFormatted)
    
    // 3. Round-trip description extraction
    let extracted = OutputFormatter.extractYouTubeDescription(from: singleFormatted)
    #expect(extracted == description)
    
    // 4. Empty / nil description returns clean transcript only
    #expect(OutputFormatter.formatYouTubeTranscript(transcript: rawTranscript, description: nil) == rawTranscript)
    #expect(OutputFormatter.formatYouTubeTranscript(transcript: rawTranscript, description: "   \n  ") == rawTranscript)
    
    // 5. Batch formatting includes DESCRIPTION section
    let metadata = BatchExportMetadata(
        batchID: "BATCH-DESC-1",
        sourceType: "YouTube",
        totalCount: 1,
        completedCount: 1,
        failedCount: 0,
        modelName: "large-v3",
        language: "tr"
    )
    let batchItem = BatchItemSection(
        sequence: 1,
        totalCount: 1,
        title: "Swift 6 Rehberi",
        channel: "Dev Kanal",
        durationSec: 300,
        url: "https://www.youtube.com/watch?v=abc12345678",
        language: "tr",
        videoDescription: description,
        transcriptText: rawTranscript,
        errorMessage: nil,
        isYouTube: true
    )
    let batchOutput = OutputFormatter.formatBatch(metadata: metadata, items: [batchItem])
    #expect(batchOutput.contains("DESCRIPTION"))
    #expect(batchOutput.contains("https://swift.org"))
    #expect(batchOutput.contains("TRANSCRIPT"))
    #expect(batchOutput.contains(rawTranscript))
}

@Test func testYTDLPClientParseMetadataWithDescriptionAndBraces() throws {
    let stdout = """
    download:  12.4%
    {"id": "jNQXAC9IVRw", "title": "Me at the zoo", "channel": "jawed", "duration": 19, "ext": "webm", "description": "Line 1 {braces}\\nLine 2 https://example.com\\n\\n00:00 Intro"}
    download: 100.0%
    """
    let meta = YTDLPClient.parseMetadata(from: stdout)
    #expect(meta != nil)
    #expect(meta?.id == "jNQXAC9IVRw")
    #expect(meta?.title == "Me at the zoo")
    #expect(meta?.channel == "jawed")
    #expect(meta?.duration == 19)
    #expect(meta?.description == "Line 1 {braces}\nLine 2 https://example.com\n\n00:00 Intro")
}
