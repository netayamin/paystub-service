import Foundation

/// Maps DB metrics to user-facing labels (no raw numbers in UI).
enum FeedMetricLabels {

    // MARK: - Rarity (backend: rarity_score 0–100, higher = rarer)
    /// 90–100 = Ultra Rare, 70–89 = Rare. Accepts 0–1 or 0–100.
    static func rarityTier(score: Double?) -> String {
        let raw = score ?? 0
        let s = raw <= 1 ? raw * 100 : raw
        let v = Int(s.rounded())
        switch v {
        case 90...100: return "Ultra Rare"
        case 70..<90: return "Rare"
        case 50..<70: return "Uncommon"
        default: return "Limited"
        }
    }

    // MARK: - Scarcity (availability_rate_14d 0–1). Short labels for badges.
    /// e.g. <5% → "Ext. Scarce" so badge doesn’t truncate
    static func scarcityStatus(rate: Double?) -> String {
        guard let r = rate, r >= 0 else { return "Scarce" }
        let pct = r <= 1 ? r * 100 : r
        if pct < 5 { return "Ext. Scarce" }
        if pct < 15 { return "Very Scarce" }
        if pct < 40 { return "Scarce" }
        return "Available"
    }

    // MARK: - Heat (trend_pct). Backend sends ratio e.g. 0.2 = 20% increase; normalize to 0–100 for tiers.
    /// 20% = Rising Heat, 50% = Exploding, 80%+ = Peak Demand. No raw % shown.
    static func heatLabel(trendPct: Double?) -> String {
        let p = trendPct ?? 0
        let normalized: Double = (p >= -1 && p <= 1) ? p * 100 : p
        if normalized >= 80 { return "Peak Demand" }
        if normalized >= 50 { return "Exploding" }
        if normalized >= 20 { return "Rising Heat" }
        if normalized > 0 { return "Warming" }
        if normalized < 0 { return "Cooling" }
        return "Steady"
    }

    // MARK: - Urgency (avg_drop_duration_seconds)
    /// "Gone in 5 min" / "Typically gone in <5 min" when unknown
    static func urgencyText(avgDurationSeconds: Double?) -> String {
        guard let sec = avgDurationSeconds, sec > 0 else { return "Typically gone in <5 min" }
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
