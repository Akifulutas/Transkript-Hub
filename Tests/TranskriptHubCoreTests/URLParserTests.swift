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

@Test func testURLParserDetectType() throws {
    // 1. Pure playlist
    let playlistURL = "https://www.youtube.com/playlist?list=PLrAXtmErZgOdP_8GztsuKi9nrraNbKKp4"
    let playlistType = URLParser.detectType(playlistURL)
    #expect(playlistType != nil)
    if case .playlist(let url, let playlistID, let videoID) = playlistType {
        #expect(playlistID == "PLrAXtmErZgOdP_8GztsuKi9nrraNbKKp4")
        #expect(videoID == nil)
        #expect(url.contains("playlist?list=PLrAXtmErZgOdP_8GztsuKi9nrraNbKKp4"))
    } else {
        #expect(Bool(false), "Oynatma listesi tipi yanlış algılandı")
    }
    
    // 2. Video with playlist parameter
    let videoInPlaylistURL = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL12345"
    let videoInPlaylistType = URLParser.detectType(videoInPlaylistURL)
    if case .playlist(let url, let playlistID, let videoID) = videoInPlaylistType {
        #expect(playlistID == "PL12345")
        #expect(videoID == "dQw4w9WgXcQ")
        #expect(url.contains("playlist?list=PL12345"))
    } else {
        #expect(Bool(false), "Oynatma listesi + video tipi yanlış algılandı")
    }
    
    // 3. Channel with handle
    let channelHandle = "https://www.youtube.com/@mkbhd"
    let channelHandleType = URLParser.detectType(channelHandle)
    if case .channel(let url, let identifier) = channelHandleType {
        #expect(identifier == "@mkbhd")
        #expect(url == "https://www.youtube.com/@mkbhd/videos")
    } else {
        #expect(Bool(false), "Kanal handle tipi yanlış algılandı")
    }
    
    // 4. Channel with handle and /videos
    let channelVideos = "https://www.youtube.com/@mkbhd/videos"
    let channelVideosType = URLParser.detectType(channelVideos)
    if case .channel(let url, let identifier) = channelVideosType {
        #expect(identifier == "@mkbhd")
        #expect(url == "https://www.youtube.com/@mkbhd/videos")
    } else {
        #expect(Bool(false), "Kanal /videos tipi yanlış algılandı")
    }
    
    // 5. Channel with /channel/ID
    let channelIDURL = "https://www.youtube.com/channel/UCBJycsmduvYEL83R_U4JriQ"
    let channelIDType = URLParser.detectType(channelIDURL)
    if case .channel(let url, let identifier) = channelIDType {
        #expect(identifier == "UCBJycsmduvYEL83R_U4JriQ")
        #expect(url == "https://www.youtube.com/channel/UCBJycsmduvYEL83R_U4JriQ/videos")
    } else {
        #expect(Bool(false), "Kanal ID tipi yanlış algılandı")
    }
    
    // 6. Single regular video
    let singleURL = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    let singleType = URLParser.detectType(singleURL)
    if case .singleVideo(let video) = singleType {
        #expect(video.videoID == "dQw4w9WgXcQ")
    } else {
        #expect(Bool(false), "Tek video tipi yanlış algılandı")
    }
    
    // 7. Non-YouTube URL
    let nonYouTube = "https://vimeo.com/12345678"
    #expect(URLParser.detectType(nonYouTube) == nil)
}

