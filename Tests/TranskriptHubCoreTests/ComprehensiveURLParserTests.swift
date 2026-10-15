import Foundation
import Testing
@testable import TranskriptHubCore

@Suite("Comprehensive URLParser Test Suite")
struct ComprehensiveURLParserTests {
    
    @Test("Recognition of all supported YouTube URL formats")
    func testAllSupportedFormats() {
        let testCases: [(url: String, expectedID: String)] = [
            // Standard web
            ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("http://www.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            
            // Short links (youtu.be)
            ("https://youtu.be/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("http://youtu.be/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://youtu.be/dQw4w9WgXcQ?t=120", "dQw4w9WgXcQ"),
            ("https://youtu.be/dQw4w9WgXcQ?feature=share", "dQw4w9WgXcQ"),
            ("https://youtu.be/dQw4w9WgXcQ?si=abcdef123456", "dQw4w9WgXcQ"),
            
            // Shorts links
            ("https://www.youtube.com/shorts/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://youtube.com/shorts/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://m.youtube.com/shorts/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://youtube.com/shorts/dQw4w9WgXcQ?feature=share", "dQw4w9WgXcQ"),
            
            // Mobile and Music
            ("https://m.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://music.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=RDAMVM", "dQw4w9WgXcQ"),
            
            // Live stream & Embed
            ("https://www.youtube.com/live/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://youtube.com/live/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://www.youtube.com/embed/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            
            // Complex query parameters
            ("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLrAXtmErZgOdP_8GztsuKi9nrraNbKKp4&index=1", "dQw4w9WgXcQ"),
            ("https://www.youtube.com/watch?app=desktop&v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://www.youtube.com/watch?feature=youtu.be&v=dQw4w9WgXcQ&t=5m30s", "dQw4w9WgXcQ"),
            
            // Diverse character combinations in 11-char IDs
            ("https://www.youtube.com/watch?v=1234567890A", "1234567890A"),
            ("https://www.youtube.com/watch?v=a-b_c12345Z", "a-b_c12345Z"),
            ("https://www.youtube.com/watch?v=__________1", "__________1")
        ]
        
        for item in testCases {
            let parsed = URLParser.parseSingle(item.url)
            #expect(parsed != nil, "Could not parse: \(item.url)")
            #expect(parsed?.videoID == item.expectedID, "ID mismatch: \(item.url)")
            #expect(parsed?.canonicalURL == "https://www.youtube.com/watch?v=\(item.expectedID)")
        }
    }
    
    @Test("Rejection of invalid URLs and foreign sites")
    func testInvalidAndMaliciousURLs() {
        let invalidInputs = [
            // Phishing / Misleading domain names
            "https://youtube.com.attacker.com/watch?v=dQw4w9WgXcQ",
            "https://fake-youtube.com/watch?v=dQw4w9WgXcQ",
            "https://notyoutube.com/watch?v=dQw4w9WgXcQ",
            "https://vimeo.com/12345678901",
            "https://dailymotion.com/video/x7tgad0",
            
            // Wrong ID lengths
            "https://www.youtube.com/watch?v=short",          // 5 chars
            "https://www.youtube.com/watch?v=toolongvideo123", // 15 chars
            "https://youtu.be/abc",                           // 3 chars
            "https://youtu.be/123456789012345",               // 15 chars
            
            // Empty parameters
            "https://www.youtube.com/watch?v=",
            "https://www.youtube.com/watch",
            "https://youtu.be/",
            "https://www.youtube.com/shorts/",
            
            // Channel and User pages (Not Video IDs)
            "https://www.youtube.com/@mkbhd",
            "https://www.youtube.com/channel/UCBJycsmduvYEL83R_U4JriQ",
            "https://www.youtube.com/c/Apple",
            
            // Random plain text
            "",
            "   ",
            "https://google.com",
            "copied a youtube link but this is not a url"
        ]
        
        for input in invalidInputs {
            let parsed = URLParser.parseSingle(input)
            #expect(parsed == nil, "Invalid input should not be accepted: \(input)")
        }
    }
    
    @Test("Bulk link extraction and deduplication from dirty text")
    func testBulkExtractionFromDirtyText() {
        let dirtyText = """
        Hello everyone, here are our podcast episodes:
        Episode 1: [Watch](https://www.youtube.com/watch?v=dQw4w9WgXcQ)
        Episode 2 link: https://youtu.be/jNQXAC9IVRw?si=test
        Also check this shorts video: https://youtube.com/shorts/3JZ_D3ELwOQ
        First video again: https://m.youtube.com/watch?v=dQw4w9WgXcQ
        Invalid link: https://vimeo.com/99999999 and https://google.com
        Last video: <a href="https://www.youtube.com/watch?v=9bZkp7q19f0">Gangnam Style</a>
        """
        
        let extracted = URLParser.parseBulk(dirtyText)
        
        // 4 unique videos (dQw4w9WgXcQ appears twice, must be deduplicated)
        #expect(extracted.count == 4)
        
        let ids = extracted.map(\.videoID)
        #expect(ids.contains("dQw4w9WgXcQ"))
        #expect(ids.contains("jNQXAC9IVRw"))
        #expect(ids.contains("3JZ_D3ELwOQ"))
        #expect(ids.contains("9bZkp7q19f0"))
    }
}
