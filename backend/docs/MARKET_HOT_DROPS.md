# Market-wide hot-drop algorithm (mapping)

This doc maps the "market-wide hot-drop" pattern to our codebase: what we have, and what we'd add to **only alert on rare drops** (not every new slot).

## Definitions (algorithm vs us)

| Algorithm term | Our equivalent |
|----------------|----------------|
| **marketKey** | `bucket_id` = date_str + time_slot (e.g. `2026-02-28_20:30`). We also have party size from env (same for all buckets). City/geo is implicit (NYC Resy). |
| **slot_key** | `date + time` — we store at (venue, date, time) granularity as `slot_id` = hash(venue_id, actual_time). So we can derive "set of venue_id per slot_key" from our data. |
| **prev[slot_key]** | `prev_slot_ids` per bucket: set of slot_ids (each slot_id implies a venue_id + time). We diff `curr - prev` → **added** = new drops. ✅ |
| **Poll once per marketKey** | We poll per bucket (marketKey). One job; all users read the same feed. ✅ |

## What we already do

- **Market-wide polling**: One poll per bucket (marketKey); no per-user polling.
- **Prev diff**: `added = curr - prev`; we don't compare to initial baseline forever. ✅
- **Dedupe**: (bucket_id, slot_id) with TTL `NOTIFIED_DEDUPE_MINUTES` so we don't re-notify for the same slot within 10–30 min. ✅
- **Rarity for display**: We have `VenueRollingMetrics`: `rarity_score` (higher = rarely has drops), `availability_rate_14d` (fraction of days in window with at least one drop). We attach these to feed cards so the UI can show "Rare" / "X/14 days". ✅
- **Scarcity in aggregation**: We compute `scarcity_score` from avg drop duration and drop/close counts; `rarity_score` from drop frequency over 14 days. Used for ranking and display, not yet for **filtering** notifications.

## What we don't have yet (alert only on hot drops)

### 1. **Metrics per (venue, weekday, meal_period, party_bucket)**

Algorithm: `observed_checks`, `available_checks`, `availability_rate = available_checks / observed_checks` per (venue_id, weekday, meal_period, party_bucket, market).

- **Us**: We have venue-level rolling metrics over 14 days (`days_with_drops`, `availability_rate_14d`), not per weekday/meal_period. We don't currently store "observed_checks" (every poll we see the venue or not); we only count when a drop opens/closes (sessions).
- **To add**: Either (a) extend aggregation to group by weekday + time_bucket (meal period) and optionally party, and maintain observed_checks / available_checks per poll, or (b) keep venue-level metrics and use them as a proxy for "rarity" in HotScore.

### 2. **Rarity in algorithm units**

Algorithm: `rarity = 1 - availability_rate` (hot places have availability_rate near 0 → rarity near 1).

- **Us**: We have `rarity_score` (0–100, higher = rarer) and `availability_rate_14d` (0–1). So we could define `rarity = 1 - availability_rate_14d` (or map rarity_score to 0–1) for use in HotScore.

### 3. **Unavailability streak**

Algorithm: `last_available_at` per venue in this market bucket; `streak = clamp((now - last_available_at) / 60min, 0..1)`. If it hasn't been available for an hour, streak ≈ 1.

- **Us**: We don't store "last time this venue had availability for this slot_key". We have `SlotAvailability` and session open/close; we could derive "last time this (venue, bucket) was open" from SlotAvailability or from a new table. Not implemented yet.
- **To add**: When we mark a slot closed, we could update `last_available_at[venue_id, slot_key] = closed_at`. When we emit a drop, we compute `streak = min(1, (now - last_available_at) / 60)` and use it in HotScore.

### 4. **HotScore at emit time**

Algorithm: `HotScore = 0.7*rarity + 0.3*streak`. Notify if `HotScore >= 0.8`.

- **Us**: We do **not** filter notifications by HotScore. We create a DropEvent for every added slot (after TTL dedupe) and push/email can send for all. So we don't yet "only alert on rare drops."
- **To add**: When we're about to create a DropEvent (or when the push job runs), compute HotScore from (rarity from VenueRollingMetrics or availability_rate_14d, streak from last_available_at). Only create a "notify" path (e.g. set a flag, or only enqueue push) when `HotScore >= threshold` (e.g. 0.8). Tune threshold later.

### 5. **Dedupe key**

Algorithm: `marketKey + venue_id + slot_key`, TTL 10–30 min.

- **Us**: We use (bucket_id, slot_id) with TTL `NOTIFIED_DEDUPE_MINUTES`. Our slot_id encodes venue + time, so we effectively have marketKey (bucket) + venue + slot. ✅

## Scaling trick (we do it)

- **Poll once per marketKey** → we poll per bucket; all users subscribed to that market get the same feed. Push can fan-out the same hot-drop events to all users watching that market. ✅

## Summary

| Piece | Status |
|-------|--------|
| Market-wide polling, prev diff, TTL dedupe | ✅ Done |
| Rarity / availability for **display** | ✅ VenueRollingMetrics, feed enrichment |
| Rarity / availability for **notify filter** | ❌ Not used to gate notifications |
| observed_checks / available_checks per (venue, weekday, meal) | ❌ Optional refinement |
| last_available_at → streak | ❌ Not implemented |
| HotScore = 0.7×rarity + 0.3×streak | ❌ Not implemented |
| Notify only if HotScore ≥ 0.8 | ❌ Not implemented |

To get "only alert on rare drops": add `last_available_at` (or derive from existing data), compute HotScore at emit time from rarity + streak, and only send push/email when HotScore ≥ threshold. Rarity can come from existing `availability_rate_14d` (e.g. `rarity = 1 - availability_rate_14d`) until you add per–weekday/meal metrics.
