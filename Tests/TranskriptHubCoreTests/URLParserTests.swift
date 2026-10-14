import Foundation
import Testing
@testable import TranskriptHubCore

@Test func testURLParserValidExamples() throws {
    let validURLs = [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "http://youtube.com/watch?v=dQw4w9WgXcQ",
        "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://music.youtube.com/watch?v=dQw4w9WgXcQ",
        "https://www.youtube-nocookie.com/watch?v=dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ",
        "http://youtu.be/dQw4w9WgXcQ",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ",
        "https://youtube.com/shorts/dQw4w9WgXcQ",
        "https://www.youtube.com/live/dQw4w9WgXcQ",
        "https://youtube.com/live/dQw4w9WgXcQ",
        "https://www.youtube.com/embed/dQw4w9WgXcQ",
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL12345",
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s",
        "https://youtu.be/dQw4w9WgXcQ?t=10",
        "https://youtu.be/dQw4w9WgXcQ?feature=share",
        "https://www.youtube.com/watch?feature=youtu.be&v=dQw4w9WgXcQ",
        "https://www.youtube.com/watch?app=desktop&v=dQw4w9WgXcQ",
        "https://www.youtube.com/shorts/1234567890a",
        "https://youtu.be/1234567890a",
        "https://www.youtube.com/watch?v=1234567890a",
        "https://www.youtube.com/watch?v=abcdefghijk",
        "https://www.youtube.com/watch?v=ABCDEFGHIJK",
        "https://www.youtube.com/watch?v=a-b_c12345Z",
        "https://www.youtube.com/watch?v=__________1"
    ]
    
    #expect(validURLs.count >= 25)
    for url in validURLs {
        let parsed = URLParser.parseSingle(url)
        #expect(parsed != nil, "URL ayrıştırılamadı: \(url)")
        #expect(parsed?.videoID.count == 11)
        #expect(parsed?.canonicalURL.starts(with: "https://www.youtube.com/watch?v=") == true)
    }
}

@Test func testURLParserInvalidExamples() throws {
    let invalidURLs = [
        "https://youtube.com.evil.com/watch?v=dQw4w9WgXcQ",
        "https://evil-youtube.com/watch?v=dQw4w9WgXcQ",
        "https://notyoutube.com/watch?v=dQw4w9WgXcQ",
        "https://www.youtube.com/watch?v=short",          // 5 chars
        "https://www.youtube.com/watch?v=too_long_12345", // 14 chars
        "https://www.youtube.com/watch?v=",               // Empty
        "https://www.youtube.com/watch",                  // No param
        "https://youtu.be/",                              // No path
        "https://youtu.be/short",                         // Short ID
        "https://youtu.be/toolongforanid123",             // Long ID
        "https://google.com?v=dQw4w9WgXcQ",               // Wrong host
        "https://vimeo.com/12345678901",                  // Vimeo
        "",                                               // Empty string
        "not a url at all",                               // Plain text
        "https://www.youtube.com/channel/UC1234567890"    // Channel URL
    ]
    
    #expect(invalidURLs.count >= 15)
    for url in invalidURLs {
        let parsed = URLParser.parseSingle(url)
        #expect(parsed == nil, "Geçersiz URL geçerli kabul edildi: \(url)")
    }
}

@Test func testURLParserBulkExtraction() throws {
    let bulkText = """
    Lütfen şu videolara bakın:
    1) https://www.youtube.com/watch?v=dQw4w9WgXcQ
    2) https://youtu.be/1234567890a harika bir video.
    Ayrıca aynı link tekrar: https://www.youtube.com/watch?v=dQw4w9WgXcQ
    Ve bir shorts: https://www.youtube.com/shorts/abcdefghijk
    Geçersiz: https://evil.com/watch?v=dQw4w9WgXcQ
    """
    
    let results = URLParser.parseBulk(bulkText)
    #expect(results.count == 3) // deduplicated 3 unique valid videos
    #expect(results[0].videoID == "dQw4w9WgXcQ")
    #expect(results[1].videoID == "1234567890a")
    #expect(results[2].videoID == "abcdefghijk")
}
