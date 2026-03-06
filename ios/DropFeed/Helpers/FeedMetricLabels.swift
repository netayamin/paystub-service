import Foundation

/// Maps DB metrics to user-facing labels (no raw numbers in UI).
enum FeedMetricLabels {

    // MARK: - Rarity (rarity_score 0–100)
    /// 90–100 = Mythic/Ultra Rare, 70–89 = Rare
    static func rarityTier(score: Double?) -> String {
        let s = (score ?? 0) <= 1 ? (score ?? 0) * 100 : (score ?? 0)
        let v = Int(s.rounded())
        switch v {
        case 90...100: return "Ultra Rare"
        case 70..<90: return "Rare"
        case 50..<70: return "Uncommon"
        default: return "Limited"
        }
    }

    // MARK: - Scarcity (availability_rate_14d 0–1)
    /// e.g. <5% → "Extremely Scarce"
    static func scarcityStatus(rate: Double?) -> String {
        guard let r = rate, r <= 1 else { return "Scarce" }
        let pct = r * 100
        if pct < 5 { return "Extremely Scarce" }
        if pct < 15 { return "Very Scarce" }
        if pct < 40 { return "Scarce" }
        return "Available"
    }

    // MARK: - Heat (trend_pct) — no % shown
    /// 20% = Rising Heat, 50% = Exploding, 80%+ = Peak Demand
    static func heatLabel(trendPct: Double?) -> String {
        let p = trendPct ?? 0
        if p >= 80 { return "Peak Demand" }
        if p >= 50 { return "Exploding" }
        if p >= 20 { return "Rising Heat" }
        if p > 0 { return "Warming" }
        return "Steady"
    }

    // MARK: - Urgency (avg_drop_duration_seconds)
    /// "Gone in 5 mins" / "Typically gone in 5 mins"
    static func urgencyText(avgDurationSeconds: Double?) -> String {
        guard let sec = avgDurationSeconds, sec > 0 else { return "Act fast" }
        if sec < 60 { return "Gone in <1 min" }
        let mins = Int(sec / 60)
        if mins == 1 { return "Gone in 1 min" }
        if mins < 60 { return "Gone in \(mins) min" }
        let hours = mins / 60
        return "Gone in \(hours)h"
    }

    // MARK: - Freshness (opened_at / detectedAt)
    /// "Dropped 2m ago" / "Just dropped"
    static func freshnessText(secondsSinceDetected: Int) -> String {
        if secondsSinceDetected < 60 { return "Just dropped" }
        if secondsSinceDetected < 3600 { return "Dropped \(secondsSinceDetected / 60)m ago" }
        if secondsSinceDetected < 86400 { return "Dropped \(secondsSinceDetected / 3600)h ago" }
        return "Dropped \(secondsSinceDetected / 86400)d ago"
    }

    /// Demand level for Hot Right Now secondary (e.g. "High Demand")
    static func demandLevel(rarityScore: Double?, availabilityRate: Double?) -> String {
        let r = rarityScore ?? 0
        let rate = availabilityRate ?? 1
        if r >= 0.8 || rate < 0.1 { return "Very High Demand" }
        if r >= 0.5 || rate < 0.25 { return "High Demand" }
        return "Popular"
    }
}
