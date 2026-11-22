import Foundation

/// A community-annotated YouTube time segment from the free, keyless SponsorBlock API (`sponsor.ajay.app`).
public struct SponsorBlockSegment: Codable, Sendable, Hashable {
    public let category: String
    public let actionType: String?
    public let segment: [Double]
    
    public var startTime: Double {
        segment.first ?? 0.0
    }
    
    public var endTime: Double {
        segment.count > 1 ? segment[1] : startTime
    }
    
    public var isHighlight: Bool {
        category == "poi_highlight" || actionType == "poi"
    }
    
    public var isSponsor: Bool {
        category == "sponsor"
    }
    
    public var localizedLabel: String {
        switch category {
        case "sponsor": return "SPONSOR"
        case "selfpromo": return "KENDİNİ TANITIM"
        case "interaction": return "ABONE/BEĞENİ HATIRLATMASI"
        case "intro": return "GİRİŞ / ARA"
        case "outro": return "KAPANIŞ"
        case "poi_highlight": return "KİLİT AN (HIGHLIGHT)"
        default: return category.uppercased()
        }
    }
    
    public init(category: String, actionType: String? = nil, segment: [Double]) {
        self.category = category
        self.actionType = actionType
        self.segment = segment
    }
}

/// Zero-API-key client for the public community SponsorBlock API.
/// Strictly non-fatal: returns `[]` on 404, offline state, or timeout so transcription is never delayed or blocked.
public enum SponsorBlockClient {
    public static func fetchSegments(videoID: String, timeoutSeconds: TimeInterval = 3.5) async -> [SponsorBlockSegment] {
        let trimmed = videoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encodedID = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }
        
        let categories = "%5B%22sponsor%22,%22selfpromo%22,%22interaction%22,%22intro%22,%22outro%22,%22poi_highlight%22%5D"
        guard let url = URL(string: "https://sponsor.ajay.app/api/skipSegments?videoID=\(encodedID)&categories=\(categories)") else {
            return []
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = timeoutSeconds
        request.setValue("TranskriptHub/1.6", forHTTPHeaderField: "User-Agent")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return []
            }
            let decoded = try JSONDecoder().decode([SponsorBlockSegment].self, from: data)
            return decoded.sorted { $0.startTime < $1.startTime }
        } catch {
            return []
        }
    }
}
