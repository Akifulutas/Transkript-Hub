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
    {"id": "jNQXAC9IVRw", "title": "Me at the zoo", "channel": "jawed", "duration": 19, "ext": "webm", "description": "Line 1 {braces}\\nLine 2 https://example.com\\n\\n00:00 Intro", "chapters": [{"start_time": 0, "end_time": 5, "title": "Intro"}, {"start_time": 5, "end_time": 17, "title": "The cool thing"}]}
    download: 100.0%
    """
    let meta = YTDLPClient.parseMetadata(from: stdout)
    #expect(meta != nil)
    #expect(meta?.id == "jNQXAC9IVRw")
    #expect(meta?.title == "Me at the zoo")
    #expect(meta?.channel == "jawed")
    #expect(meta?.duration == 19)
    #expect(meta?.description == "Line 1 {braces}\nLine 2 https://example.com\n\n00:00 Intro")
    #expect(meta?.chapters?.count == 2)
    #expect(meta?.chapters?[0].title == "Intro")
    #expect(meta?.chapters?[1].startTime == 5)
}

@Test func testYouTubeChapterFormattingAndDescriptionFallback() throws {
    let description = """
    Bu derste sistem mimarisini inceliyoruz.

    00:00 Giriş
    12:40 - Mimari Kararlar
    1:05:20 Sonuç ve Değerlendirme
    """
    
    // 1. Fallback parser extracts chapters from description when native chapters are absent
    let parsedChapters = OutputFormatter.resolveChapters(nativeChapters: nil, description: description)
    #expect(parsedChapters.count == 3)
    #expect(parsedChapters[0].startTime == 0)
    #expect(parsedChapters[0].title == "Giriş")
    #expect(parsedChapters[1].startTime == 760)
    #expect(parsedChapters[1].title == "Mimari Kararlar")
    #expect(parsedChapters[2].startTime == 3920)
    #expect(parsedChapters[2].title == "Sonuç ve Değerlendirme")
    
    // 2. Segments are grouped into Markdown headings without dropping any segment
    let segments = [
        Segment(start: 2.0, end: 8.0, text: "Herkese merhaba, bugünkü konumuz mimari."),
        Segment(start: 765.0, end: 780.0, text: "İlk mimari kararımız veritabanı seçimi."),
        Segment(start: 3925.0, end: 3940.0, text: "Özetle bu yaklaşım oldukça kararlı.")
    ]
    
    let chaptered = OutputFormatter.formatChapteredTranscript(segments: segments, chapters: parsedChapters)
    #expect(chaptered.contains("## 00:00 Giriş"))
    #expect(chaptered.contains("Herkese merhaba, bugünkü konumuz mimari."))
    #expect(chaptered.contains("## 12:40 Mimari Kararlar"))
    #expect(chaptered.contains("İlk mimari kararımız veritabanı seçimi."))
    #expect(chaptered.contains("## 1:05:20 Sonuç ve Değerlendirme"))
    #expect(chaptered.contains("Özetle bu yaklaşım oldukça kararlı."))
}

@Test func testRichMaximumDataYouTubeDocumentFormatting() throws {
    let metadata = YouTubeMetadata(
        id: "abc12345678",
        title: "Apple Silicon Whisper & Qwen3 Deep Dive",
        channel: "Tech Engineering",
        channelURL: "https://www.youtube.com/channel/UC12345",
        channelFollowerCount: 1_250_000,
        uploadDate: "20261118",
        duration: 1200,
        viewCount: 84_500,
        likeCount: 4_200,
        commentCount: 312,
        liveStatus: "was_live",
        categories: ["Science & Technology"],
        tags: ["whisper.cpp", "Metal GPU", "Qwen3-ASR"],
        ext: "m4a",
        description: "Repo: https://github.com/example/asr-bench\nDocs: https://swift.org/documentation/\n\n00:00 Giriş\n04:00 Sponsor\n05:30 Mimari",
        chapters: [
            YouTubeChapter(startTime: 0, endTime: 240, title: "Giriş"),
            YouTubeChapter(startTime: 240, endTime: 330, title: "Sponsor"),
            YouTubeChapter(startTime: 330, endTime: 1200, title: "Mimari")
        ],
        heatmap: [
            YouTubeHeatmapPoint(startTime: 10, endTime: 22, value: 0.2),
            YouTubeHeatmapPoint(startTime: 340, endTime: 352, value: 0.92),
            YouTubeHeatmapPoint(startTime: 352, endTime: 364, value: 1.0),
            YouTubeHeatmapPoint(startTime: 900, endTime: 912, value: 0.78)
        ],
        comments: [
            YouTubeComment(author: "@CommunityFan", text: "Harika analiz! https://arxiv.org/abs/2501.00001", likeCount: 1850, isPinned: false, isUploader: false),
            YouTubeComment(author: "@TechEngineering", text: "Düzeltme: 05:30'daki benchmark M1 Pro üzerinde alındı.", likeCount: 420, isPinned: true, isUploader: true),
            YouTubeComment(author: "@TechEngineering", text: "Kodları güncelledim: https://github.com/example/asr-bench", likeCount: 120, isPinned: false, isUploader: true)
        ]
    )
    
    let sponsorSegments = [
        SponsorBlockSegment(category: "sponsor", actionType: "skip", segment: [240.0, 325.0]),
        SponsorBlockSegment(category: "poi_highlight", actionType: "poi", segment: [345.0, 345.0])
    ]
    
    let segments = [
        Segment(start: 2.0, end: 12.0, text: "Merhaba arkadaşlar, bugün Apple Silicon üzerinde ses modellerini inceliyoruz."),
        Segment(start: 250.0, end: 270.0, text: "Bu bölüm bugünkü sponsorumuz tarafından desteklenmektedir."),
        Segment(start: 342.0, end: 360.0, text: "Mimari farklara baktığımızda Flash Attention hızı ikiye katlıyor.")
    ]
    
    let doc = OutputFormatter.formatRichYouTubeDocument(
        metadata: metadata,
        segments: segments,
        canonicalURL: "https://www.youtube.com/watch?v=abc12345678",
        sponsorSegments: sponsorSegments
    )
    
    // 1. Video Identity & Metadata
    #expect(doc.contains("VİDEO BİLGİLERİ"))
    #expect(doc.contains("Başlık: Apple Silicon Whisper & Qwen3 Deep Dive"))
    #expect(doc.contains("Kanal: Tech Engineering (1.25M abone) — https://www.youtube.com/channel/UC12345"))
    #expect(doc.contains("Yayın Tarihi: 2026-11-18"))
    #expect(doc.contains("Tür: Canlı Yayın Tekrarı"))
    #expect(doc.contains("84.5K izlenme • 4.2K beğeni • 312 yorum"))
    #expect(doc.contains("Etiketler: whisper.cpp, Metal GPU, Qwen3-ASR"))
    
    // 2. Chapters TOC & Chaptered Headings
    #expect(doc.contains("İÇİNDEKİLER (BÖLÜMLER)"))
    #expect(doc.contains("- 00:00 Giriş"))
    #expect(doc.contains("- 05:30 Mimari"))
    #expect(doc.contains("## 00:00 Giriş"))
    #expect(doc.contains("## 05:30 Mimari"))
    
    // 3. Heatmap Most Replayed Peaks with spoken excerpt
    #expect(doc.contains("🔥 EN ÇOK TEKRAR İZLENEN ANLAR (HEATMAP)"))
    #expect(doc.contains("Yoğunluk: %100"))
    #expect(doc.contains("Flash Attention hızı ikiye katlıyor"))
    
    // 4. SponsorBlock summary + inline [SPONSOR] tag in transcript
    #expect(doc.contains("🏷️ SPONSOR / REKLAM & KİLİT ANLAR (SPONSORBLOCK)"))
    #expect(doc.contains("⭐ Kilit An (Highlight): [05:45]"))
    #expect(doc.contains("[SPONSOR: 04:00 - 05:25]"))
    #expect(doc.contains("[SPONSOR] Bu bölüm bugünkü sponsorumuz"))
    
    // 5. Deduplicated Resource URL Index (from both description and comments)
    #expect(doc.contains("🔗 KAYNAKLAR & LİNKLER (URL DİZİNİ)"))
    #expect(doc.contains("https://github.com/example/asr-bench"))
    #expect(doc.contains("https://swift.org/documentation/"))
    #expect(doc.contains("https://arxiv.org/abs/2501.00001"))
    let repoOccurrencesInLinks = doc.components(separatedBy: "1. https://github.com/example/asr-bench").count - 1
    #expect(repoOccurrencesInLinks == 1)
    
    // 6. Curated Comments (Pinned first, then Uploader, then Community)
    #expect(doc.contains("📌 SABİTLENMİŞ & EN ÇOK BEĞENİLEN YORUMLAR"))
    #expect(doc.contains("[📌 SABİTLENMİŞ] @TechEngineering (420 beğeni):"))
    #expect(doc.contains("[👤 KANAL SAHİBİ] @TechEngineering (120 beğeni):"))
    #expect(doc.contains("1. @CommunityFan (1.9K beğeni):"))
    
    // 7. Timestamped Transcript & Idempotent/Extractable Description
    #expect(doc.contains("[00:02]"))
    #expect(doc.contains("[05:42]"))
    let extractedDesc = OutputFormatter.extractYouTubeDescription(from: doc)
    #expect(extractedDesc?.contains("https://github.com/example/asr-bench") == true)
    #expect(OutputFormatter.ensureYouTubeDescriptionIncluded(transcript: doc, description: metadata.description) == doc)
}
