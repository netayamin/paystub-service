# Metrics roadmap: data as the product

Treat collected data as a core asset. Below: metrics we have, metrics we're adding, and a backlog of high-value ideas.

---

## What we already collect

| Layer | Metrics | Product use |
|-------|---------|-------------|
| **drop_events** | NEW_DROP / CLOSED, opened_at, closed_at, duration, time_bucket (prime/off_peak), slot_date, slot_time, venue_id, neighborhood | Raw signal; aggregated before prune. |
| **venue_metrics** (per venue per day) | new_drop_count, closed_count, prime/off_peak, avg/median_duration, **scarcity_score** (speed + churn + rarity) | "Hardest tables," rankings, expectations. |
| **market_metrics** | daily_totals: total_new_drops, total_closed, avg_duration, event_count | Market pulse, trends. |
| **venue_rolling_metrics** (per venue, 14d) | total_new_drops, days_with_drops, drop_frequency_per_day, **rarity_score** | "Rarely opens" / unique opportunity. |

---

## High-value metrics to add

### 1. Timing: when do drops happen?

| Metric | Source | Store | Product use |
|--------|--------|--------|-------------|
| **Drops by hour of day** | opened_at from events | market_metrics value_json: `by_hour: {"9": 12, "17": 45, ...}` | "Best time to check," content: "Most drops 5–7pm." |
| **Weekday** | slot_date / opened_at | Already have slot_date; add **by_weekday** to daily or market rollup | "Fridays are brutal," "Tuesdays quieter." |
| **Prime vs off-peak share** | time_bucket on events | market_metrics: `prime_share`, `off_peak_share` | "Prime time is 80% of drops." |

**Implementation:** Extend aggregation: when building daily_totals, also aggregate events by hour(opened_at) and weekday; add to value_json. Optional: one market_metrics row per week with by_weekday rollup.

### 2. Trend: getting harder or easier?

| Metric | Source | Store | Product use |
|--------|--------|--------|-------------|
| **Venue trend (last 7d vs prev 7d)** | venue_metrics last 14d | venue_rolling_metrics: `total_last_7d`, `total_prev_7d`, `trend_pct` | "Getting harder," "More availability lately." |
| **Market week-over-week** | market_metrics daily_totals | New: market_metrics metric_type=weekly_summary, value_json: this_week vs last_week | "Drops up 15% this week." |

**Implementation:** In rolling step, compute last 7d and prev 7d from venue_metrics; add trend_pct. Weekly market: optional second pass over market_metrics.

### 3. Availability rate (explicit)

| Metric | Source | Store | Product use |
|--------|--------|--------|-------------|
| **Availability rate 14d** | days_with_drops / 14 | venue_rolling_metrics: `availability_rate_14d` | "Available 3 of 14 days" = 21%; badges. |

**Implementation:** We have days_with_drops and window_days; add column and set availability_rate_14d = days_with_drops / window_days.

### 4. Neighborhood / geography

| Metric | Source | Store | Product use |
|--------|--------|--------|-------------|
| **Drops by neighborhood** | neighborhood on drop_events | market_metrics: metric_type=by_neighborhood, value_json: {"SoHo": 120, "Tribeca": 45} | "SoHo had 3x more drops than Tribeca." |
| **Venue primary neighborhood** | Most common neighborhood in events | venue_metrics or venues table | Filter, "hardest in SoHo." |

**Implementation:** When aggregating events, group by neighborhood; write market_metrics row by_neighborhood per window_date. Venue: from venue_metrics we don't have neighborhood yet; could add from drop_events or leave for later.

### 5. Supply compression (vs baseline)

| Metric | Source | Store | Product use |
|--------|--------|--------|-------------|
| **Slots vs baseline** | discovery_buckets: baseline size, current size per poll | New: store baseline_slot_count, current_slot_count per bucket or day | "Supply tightened 20% this weekend." |

**Implementation:** Requires storing baseline/current counts when we poll (we have slot IDs, so count is derivable). New table or columns; then aggregate to market "supply_tightening" metric.

### 6. User behavior (conversion)

| Metric | Source | Store | Product use |
|--------|--------|--------|-------------|
| **Alert sent → opened → tap → booked** | Client events | alert_events / user_behavior_events | Conversion rate, value-based pricing. |
| **Time to action** | Timestamps | Same table | "Users book within 2 min when we alert." |

**Implementation:** New table + API for client events (Phase 4 in VALUE_FROM_DATA).

### 7. Percentile / relative ranking

| Metric | Source | Store | Product use |
|--------|--------|--------|-------------|
| **Venue scarcity percentile** | Distribution of scarcity_score | On read: compute percentile from venue_metrics | "Top 5% hardest." |
| **Venue rarity percentile** | Distribution of rarity_score | Same | "Rarest 10%." |

**Implementation:** Query-time or cached; no new storage.

### 8. Slot-time quality (prime 7pm vs 5pm)

| Metric | Source | Store | Product use |
|--------|--------|--------|-------------|
| **Avg duration by slot_time bucket** | slot_time / time_bucket on events | venue_metrics: avg_duration_prime, avg_duration_off_peak (we have prime/off_peak counts) | "7pm slots disappear 2x faster than 3pm." |

**Implementation:** We already have prime_time_drops, off_peak_drops; could add avg_duration_prime and avg_duration_off_peak in venue_metrics (separate aggregates in group-by).

---

## Implementation priority

| Priority | What | Effort | Value |
|----------|------|--------|--------|
| **Done** | Market daily_totals: `by_hour`, `weekday` in value_json | Low | "When to check," timing content. |
| **Done** | Venue rolling: `total_last_7d`, `total_prev_7d`, `trend_pct`, `availability_rate_14d` | Low | "Getting harder," "available 3/14 days." |
| Next | by_neighborhood in market_metrics | Low | "SoHo vs Tribeca." |
| Next | Venue primary_neighborhood (or from payload) | Low | Filter, "hardest in X." |
| Later | Supply compression (baseline vs current) | Medium | "Supply tightened." |
| Later | User behavior events table + API | Medium | Conversion, pricing. |
| Later | Percentile on read or cached | Low | "Top 5% hardest." |

---

## Summary

- **Already strong:** Scarcity, rarity, duration, prime/off_peak, daily market totals.
- **Adding now:** Timing (by_hour, weekday), venue trend (last 7 vs prev 7), availability_rate_14d.
- **Next:** Neighborhood (market + venue), then supply compression and user behavior.

All of these make the data a durable, differentiable product asset.
