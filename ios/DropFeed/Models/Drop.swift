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
    // Scarcity metrics from rolling_metrics
    let rarityScore: Double?
    let availabilityRate14d: Double?
    let daysWithDrops: Int?
    let dropFrequencyPerDay: Double?
    let isHotspot: Bool?
    let neighborhood: String?
    
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
        rarityScore = try c.decodeIfPresent(Double.self, forKey: .rarityScore)
        availabilityRate14d = try c.decodeIfPresent(Double.self, forKey: .availabilityRate14d)
        daysWithDrops = try c.decodeIfPresent(Int.self, forKey: .daysWithDrops)
        dropFrequencyPerDay = try c.decodeIfPresent(Double.self, forKey: .dropFrequencyPerDay)
        isHotspot = try c.decodeIfPresent(Bool.self, forKey: .isHotspot)
        neighborhood = try c.decodeIfPresent(String.self, forKey: .neighborhood)
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
        ratingCount: Int? = nil,
        rarityScore: Double? = nil,
        availabilityRate14d: Double? = nil,
        daysWithDrops: Int? = nil,
        dropFrequencyPerDay: Double? = nil,
        isHotspot: Bool? = nil,
        neighborhood: String? = nil
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
        self.rarityScore = rarityScore
        self.availabilityRate14d = availabilityRate14d
        self.daysWithDrops = daysWithDrops
        self.dropFrequencyPerDay = dropFrequencyPerDay
        self.isHotspot = isHotspot
        self.neighborhood = neighborhood
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
        case rarityScore = "rarity_score"
        case availabilityRate14d = "availability_rate_14d"
        case daysWithDrops = "days_with_drops"
        case dropFrequencyPerDay = "drop_frequency_per_day"
        case isHotspot = "is_hotspot"
        case neighborhood
    }
    
    // MARK: - Scarcity helpers
    
    enum ScarcityTier {
        case rare, uncommon, available, unknown
    }
    
    var scarcityTier: ScarcityTier {
        guard let rate = availabilityRate14d, rate > 0 else { return .unknown }
        if rate < 0.15 { return .rare }
        if rate < 0.4 { return .uncommon }
        return .available
    }
    
    var scarcityLabel: String? {
        guard let rate = availabilityRate14d, rate > 0 else { return nil }
        let days = daysWithDrops ?? Int((rate * 14).rounded())
        switch scarcityTier {
        case .rare: return "Rare · open \(days)/14 days"
        case .uncommon: return "Uncommon · open \(days)/14 days"
        case .available: return "Available · open \(days)/14 days"
        case .unknown: return nil
        }
    }
    
    var freshnessLabel: String? {
        guard let iso = detectedAt ?? createdAt else { return nil }
        guard let d = Self.parseISO(iso) else { return nil }
        let sec = Int(-d.timeIntervalSinceNow)
        if sec < 0 { return "Just dropped" }
        if sec < 60 { return "Just dropped" }
        if sec < 3600 { return "\(sec / 60)m ago" }
        if sec < 86400 { return "\(sec / 3600)h ago" }
        return nil
    }
    
    var secondsSinceDetected: Int {
        guard let iso = detectedAt ?? createdAt, let d = Self.parseISO(iso) else { return 999 }
        return max(0, Int(-d.timeIntervalSinceNow))
    }
    
    private static let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    
    private static let isoBasic = ISO8601DateFormatter()
    
    static func parseISO(_ str: String) -> Date? {
        isoFull.date(from: str) ?? isoBasic.date(from: str)
    }
}

// MARK: - Likely to Open venue

struct LikelyToOpenVenue: Codable, Identifiable {
    var id: String { name }
    let name: String
    let imageUrl: String?
    let availabilityRate14d: Double?
    let daysWithDrops: Int?
    let rarityScore: Double?
    let lastSeenDescription: String?
    let neighborhood: String?
    
    enum CodingKeys: String, CodingKey {
        case name
        case imageUrl = "image_url"
        case availabilityRate14d = "availability_rate_14d"
        case daysWithDrops = "days_with_drops"
        case rarityScore = "rarity_score"
        case lastSeenDescription = "last_seen_description"
        case neighborhood
    }
}

// MARK: - Calendar counts

struct CalendarCounts: Codable {
    let byDate: [String: Int]
    let dates: [String]
    
    enum CodingKeys: String, CodingKey {
        case byDate = "by_date"
        case dates
    }
    
    init(byDate: [String: Int] = [:], dates: [String] = []) {
        self.byDate = byDate
        self.dates = dates
    }
}

/// Response from GET /chat/watches/just-opened
struct JustOpenedResponse: Codable {
    let rankedBoard: [Drop]?
    let topOpportunities: [Drop]?
    let hotRightNow: [Drop]?
    let likelyToOpen: [LikelyToOpenVenue]?
    let lastScanAt: String?
    let totalVenuesScanned: Int?
    let nextScanAt: String?
    
    enum CodingKeys: String, CodingKey {
        case rankedBoard = "ranked_board"
        case topOpportunities = "top_opportunities"
        case hotRightNow = "hot_right_now"
        case likelyToOpen = "likely_to_open"
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
        var likelyVenues: [LikelyToOpenVenue] = []
        if let arr = json["likely_to_open"] as? [[String: Any]] {
            likelyVenues = arr.compactMap { item in
                guard let d = try? JSONSerialization.data(withJSONObject: item),
                      let v = try? decoder.decode(LikelyToOpenVenue.self, from: d) else { return nil }
                return v
            }
        }
        return JustOpenedResponse(
            rankedBoard: decodeDrops("ranked_board"),
            topOpportunities: decodeDrops("top_opportunities"),
            hotRightNow: decodeDrops("hot_right_now"),
            likelyToOpen: likelyVenues.isEmpty ? nil : likelyVenues,
            lastScanAt: json["last_scan_at"] as? String,
            totalVenuesScanned: intValue("total_venues_scanned"),
            nextScanAt: json["next_scan_at"] as? String
        )
    }
}

// MARK: - Watchlist API models

struct VenueWatch: Codable, Identifiable {
    let id: Int
    let venueName: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case venueName = "venue_name"
    }
}

struct VenueWatchesResponse: Codable {
    let watches: [VenueWatch]
    let excluded: [VenueWatch]
}

struct HotlistResponse: Codable {
    let names: [String]
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
            ratingCount: 1200,
            rarityScore: 0.85,
            availabilityRate14d: 0.10,
            daysWithDrops: 2,
            isHotspot: true
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
            feedHot: false,
            availabilityRate14d: 0.35,
            daysWithDrops: 5
        )
    }
    
    static var previewRare: Drop {
        Drop(
            id: "preview-don-angie",
            name: "Don Angie",
            location: "West Village",
            dateStr: "2026-02-20",
            slots: [
                DropSlot(dateStr: "2026-02-20", time: "19:00", resyUrl: "https://resy.com/cities/ny/places/don-angie"),
                DropSlot(dateStr: "2026-02-20", time: "21:30", resyUrl: "https://resy.com/cities/ny/places/don-angie")
            ],
            partySizesAvailable: [2],
            imageUrl: nil,
            detectedAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(-30)),
            resyUrl: "https://resy.com/cities/ny/places/don-angie",
            feedHot: true,
            rarityScore: 0.95,
            availabilityRate14d: 0.07,
            daysWithDrops: 1,
            isHotspot: true
        )
    }
}
