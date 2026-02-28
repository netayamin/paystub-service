import Foundation

/// Single time slot (date + time + Resy URL)
struct DropSlot: Codable {
    let dateStr: String?
    let time: String?
    let resyUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case dateStr = "date_str"
        case time
        case resyUrl = "resyUrl"
    }
}

/// Restaurant drop card from the feed
struct Drop: Codable, Identifiable {
    let id: String
    let name: String
    let venueKey: String?
    let location: String?
    let dateStr: String?
    let slots: [DropSlot]
    let partySizesAvailable: [Int]
    let imageUrl: String?
    let createdAt: String?
    let detectedAt: String?
    let resyUrl: String?
    let feedHot: Bool?
    let resyPopularityScore: Double?
    let ratingAverage: Double?
    let ratingCount: Int?
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        venueKey = try c.decodeIfPresent(String.self, forKey: .venueKey)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        dateStr = try c.decodeIfPresent(String.self, forKey: .dateStr)
        slots = try c.decodeIfPresent([DropSlot].self, forKey: .slots) ?? []
        partySizesAvailable = try c.decodeIfPresent([Int].self, forKey: .partySizesAvailable) ?? []
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        detectedAt = try c.decodeIfPresent(String.self, forKey: .detectedAt)
        resyUrl = try c.decodeIfPresent(String.self, forKey: .resyUrl)
        feedHot = try c.decodeIfPresent(Bool.self, forKey: .feedHot)
        resyPopularityScore = try c.decodeIfPresent(Double.self, forKey: .resyPopularityScore)
        ratingAverage = try c.decodeIfPresent(Double.self, forKey: .ratingAverage)
        ratingCount = try c.decodeIfPresent(Int.self, forKey: .ratingCount)
    }
    
    /// Memberwise init for previews and tests.
    init(
        id: String,
        name: String,
        venueKey: String? = nil,
        location: String? = nil,
        dateStr: String? = nil,
        slots: [DropSlot] = [],
        partySizesAvailable: [Int] = [],
        imageUrl: String? = nil,
        createdAt: String? = nil,
        detectedAt: String? = nil,
        resyUrl: String? = nil,
        feedHot: Bool? = nil,
        resyPopularityScore: Double? = nil,
        ratingAverage: Double? = nil,
        ratingCount: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.venueKey = venueKey
        self.location = location
        self.dateStr = dateStr
        self.slots = slots
        self.partySizesAvailable = partySizesAvailable
        self.imageUrl = imageUrl
        self.createdAt = createdAt
        self.detectedAt = detectedAt
        self.resyUrl = resyUrl
        self.feedHot = feedHot
        self.resyPopularityScore = resyPopularityScore
        self.ratingAverage = ratingAverage
        self.ratingCount = ratingCount
    }
    
    enum CodingKeys: String, CodingKey {
        case id, name, slots
        case venueKey = "venueKey"
        case location
        case dateStr = "date_str"
        case partySizesAvailable = "party_sizes_available"
        case imageUrl = "image_url"
        case createdAt = "created_at"
        case detectedAt = "detected_at"
        case resyUrl = "resyUrl"
        case feedHot = "feedHot"
        case resyPopularityScore = "resy_popularity_score"
        case ratingAverage = "rating_average"
        case ratingCount = "rating_count"
    }
}

/// Response from GET /chat/watches/just-opened
struct JustOpenedResponse: Codable {
    let rankedBoard: [Drop]?
    let topOpportunities: [Drop]?
    let hotRightNow: [Drop]?
    let lastScanAt: String?
    let totalVenuesScanned: Int?
    let nextScanAt: String?
    
    enum CodingKeys: String, CodingKey {
        case rankedBoard = "ranked_board"
        case topOpportunities = "top_opportunities"
        case hotRightNow = "hot_right_now"
        case lastScanAt = "last_scan_at"
        case totalVenuesScanned = "total_venues_scanned"
        case nextScanAt = "next_scan_at"
    }
    
    /// Decode response, skipping any feed cards that fail to decode so one bad card doesn't empty the feed.
    static func decodeLenient(from data: Data, decoder: JSONDecoder) throws -> JustOpenedResponse {
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        func decodeDrops(_ key: String) -> [Drop] {
            guard let arr = json[key] as? [[String: Any]] else { return [] }
            return arr.compactMap { item in
                guard let d = try? JSONSerialization.data(withJSONObject: item),
                      let drop = try? decoder.decode(Drop.self, from: d) else { return nil }
                return drop
            }
        }
        func intValue(_ key: String) -> Int? {
            if let n = json[key] as? Int { return n }
            return (json[key] as? NSNumber)?.intValue
        }
        return JustOpenedResponse(
            rankedBoard: decodeDrops("ranked_board"),
            topOpportunities: decodeDrops("top_opportunities"),
            hotRightNow: decodeDrops("hot_right_now"),
            lastScanAt: json["last_scan_at"] as? String,
            totalVenuesScanned: intValue("total_venues_scanned"),
            nextScanAt: json["next_scan_at"] as? String
        )
    }
}

// MARK: - Preview helpers
extension Drop {
    static var preview: Drop {
        Drop(
            id: "preview-balthazar",
            name: "Balthazar",
            location: "Soho",
            dateStr: "2026-02-18",
            slots: [
                DropSlot(dateStr: "2026-02-18", time: "19:30", resyUrl: "https://resy.com/cities/ny/places/balthazar")
            ],
            partySizesAvailable: [2, 4],
            detectedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-120)),
            resyUrl: "https://resy.com/cities/ny/places/balthazar",
            feedHot: true,
            ratingCount: 1200
        )
    }
    
    static var previewTrending: Drop {
        Drop(
            id: "preview-pastis",
            name: "Pastis",
            location: "Meatpacking",
            dateStr: "2026-02-19",
            slots: [
                DropSlot(dateStr: "2026-02-19", time: "20:00", resyUrl: "https://resy.com/places/pastis")
            ],
            partySizesAvailable: [2],
            detectedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-300)),
            resyUrl: "https://resy.com/places/pastis",
            feedHot: false
        )
    }
}
