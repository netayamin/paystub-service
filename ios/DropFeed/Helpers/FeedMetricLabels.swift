import Foundation

/// Maps DB metrics to user-facing labels for the live-scan feed.
enum FeedMetricLabels {

    // MARK: - Rarity (backend: rarity_score 0–100, higher = rarer)
    /// Normalised 0–100 for display. Accepts legacy 0–1.
    static func rarityPoints(score: Double?) -> Int? {
        guard let raw = score, raw > 0 else { return nil }
        let s = raw <= 1 ? raw * 100 : raw
        let v = Int(s.rounded())
        return min(100, max(1, v))
    }

    /// 90–100 = Ultra Rare, 70–89 = Rare. Accepts 0–1 or 0–100.
    static func rarityTier(score: Double?) -> String {
        guard let pts = rarityPoints(score: score) else { return "Limited" }
        switch pts {
        case 90...100: return "Ultra Rare"
        case 70..<90: return "Rare"
        case 50..<70: return "Uncommon"
        default: return "Limited"
        }
    }

    /// One line for cards: tier + score, e.g. "Rare · 78".
    static func rarityHeadline(score: Double?) -> String {
        let tier = rarityTier(score: score)
        if let p = rarityPoints(score: score) {
            return "\(tier) · \(p)"
        }
        return tier
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
    /// "Gone in 5 min" when we have avg duration; otherwise no false "<5 min" claim.
    static func urgencyText(avgDurationSeconds: Double?) -> String {
        // No duration yet — don’t imply tables always vanish in <5 min.
        guard let sec = avgDurationSeconds, sec > 0 else { return "Vanish speed unknown" }
        if sec < 60 { return "Gone in <1 min" }
        let mins = Int(sec / 60)
        if mins == 1 { return "Gone in 1 min" }
        if mins < 60 { return "Gone in \(mins) min" }
        let hours = mins / 60
        return "Gone in \(hours)h"
    }

    /// Compact for dense rows: "<1m", "12m", "2h".
    static func vanishShort(avgDurationSeconds: Double?) -> String? {
        guard let sec = avgDurationSeconds, sec > 0 else { return nil }
        if sec < 60 { return "<1m" }
        let mins = Int(sec / 60)
        if mins < 60 { return "\(mins)m" }
        let h = max(1, mins / 60)
        return "\(h)h"
    }

    // MARK: - Active days (days_with_drops / 14)
    static func activeDaysLine(daysWithDrops: Int?) -> String? {
        guard let d = daysWithDrops, d > 0 else { return nil }
        return "Tables showed \(d)× in 14d"
    }

    static func activeDaysShort(daysWithDrops: Int?) -> String? {
        guard let d = daysWithDrops, d > 0 else { return nil }
        return "\(d)/14d"
    }

    // MARK: - Trend (trend_pct: ratio e.g. 0.2 = +20% vs prior week)
    /// Percentage points for display (+/-).
    static func trendPercentPoints(_ raw: Double?) -> Double? {
        guard let p = raw else { return nil }
        if abs(p) < 1e-9 { return nil }
        // Backend sends ratio in (-1, 1) typically
        if p >= -1, p <= 1 { return p * 100 }
        return p
    }

    /// "+18%" / "-12%" when meaningful (≥5 pp change).
    static func trendShortLabel(trendPct: Double?) -> String? {
        guard let pts = trendPercentPoints(trendPct), abs(pts) >= 5 else { return nil }
        let r = Int(pts.rounded())
        return r > 0 ? "+\(r)% wk" : "\(r)% wk"
    }

    // MARK: - Freshness (opened_at / detectedAt)
    /// "Dropped 2m ago" / "Just dropped"
    static func freshnessText(secondsSinceDetected: Int) -> String {
        if secondsSinceDetected < 60 { return "Just dropped" }
        if secondsSinceDetected < 3600 { return "Dropped \(secondsSinceDetected / 60)m ago" }
        if secondsSinceDetected < 86400 { return "Dropped \(secondsSinceDetected / 3600)h ago" }
        return "Dropped \(secondsSinceDetected / 86400)d ago"
    }

    /// Demand level for Hot Right Now secondary (e.g. "High Demand").
    /// rarityScore is on the backend 0–100 scale.
    static func demandLevel(rarityScore: Double?, availabilityRate: Double?) -> String {
        let raw = rarityScore ?? 0
        // Normalise: accept both 0–1 (legacy) and 0–100 (current backend)
        let r = raw <= 1 ? raw * 100 : raw
        let rate = availabilityRate ?? 1
        if r >= 80 || rate < 0.1 { return "Very High Demand" }
        if r >= 50 || rate < 0.25 { return "High Demand" }
        return "Popular"
    }
}
