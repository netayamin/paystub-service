# From Scraper to Reservation Market Intelligence

**Principle:** Store **availability dynamics** (transitions, durations, aggregates), not tables or raw snapshots. Signal over noise. If the upstream API changes tomorrow, we still own historical scarcity, volatility, and user behavior—that’s the asset.

---

## Current State vs Target

| Layer | Today | Target |
|-------|--------|--------|
| **1. Availability events** | We store only **NEW_DROP** (slot opened). One row per drop, no event type, no close event, no duration. | Store **transitions**: NEW_DROP, CLOSED, STILL_AVAILABLE, BASELINE_AVAILABLE. When a slot closes, persist **duration** and time bucket. |
| **2. Venue intelligence** | `venues`: id, name, first/last_seen. No aggregates. | Per-venue rolling metrics: drop frequency, avg/median drop duration, scarcity score, volatility. |
| **3. Market dynamics** | None. | Drops per hour, by neighborhood, by weekday; prime-time volatility; 14d availability density. |
| **4. User behavior** | None. | Alert sent/opened, tap-to-reserve, booking confirmed, time-to-action, conversion. |

---

## 1. Availability event metrics (core asset)

**Idea:** Every slot **state change** is an event. We already have (curr, prev, baseline); we can derive event type and, when a slot disappears, duration.

### A) Slot identity (enrich what we store per event)

Keep or add on the **event** row (or a shared slot descriptor):

| Field | Source today | Notes |
|-------|----------------|-------|
| `venue_id` | ✓ | Already on DropEvent |
| `venue_name` | ✓ | Already |
| `provider` | Implicit "resy" | Add column; future multi-provider |
| `party_size` | From payload / bucket | We poll 2 and 4; store which sizes had the slot |
| `datetime` | From API `actual_time` | Slot time (e.g. 2026-02-18 20:30) |
| `date` | From bucket_id | date_str |
| `time_bucket` | From time_slot | "prime" (19:00) vs "off_peak" (15:00); or 15:00 / 19:00 |
| `neighborhood` | From Resy payload | If present; else null |
| `price_range` | From payload | If present |

### B) State data (per event or per slot lifecycle)

- `was_available_previous_poll` → we have prev; event is in prev or not.
- `is_available_now` → event is in curr or not.
- `first_seen_at` → for a given (bucket_id, slot_id), first time we saw it (opened_at of NEW_DROP).
- `last_seen_at` → last poll where slot was in curr; when we emit CLOSED, this = previous poll time.
- `baseline_status` → slot in baseline (BASELINE_AVAILABLE) or not.

### C) Event types (transitions, not snapshots)

| Event | When we emit | Today |
|-------|----------------|-------|
| **NEW_DROP** | slot ∈ (curr − prev) ∩ (curr − baseline) | ✓ We do this; it’s our only event. |
| **CLOSED** | slot ∈ prev, slot ∉ curr | ✗ Add: when we transition prev→curr, (prev − curr) = closed slots. |
| **STILL_AVAILABLE** | Optional: slot ∈ prev ∩ curr, was a drop before. | Optional; can be derived. |
| **BASELINE_AVAILABLE** | Slot was in baseline at T0. | Optional; we can tag at baseline time. |

We should **at least** add **CLOSED** and store **duration** when we close.

### D) Duration metrics (when a slot closes)

When we detect **slot in prev, not in curr**:

- `closed_at` = this poll’s `scanned_at` (or now).
- `first_seen_at` = opened_at of the NEW_DROP row for this (bucket_id, slot_id).
- **drop_duration_seconds** = closed_at − first_seen_at.
- Derive: **time_to_close_bucket** (e.g. "7pm", "3pm"), **weekday**, **is_prime_time**.

Then we can answer: *“Friday 7pm at Carbone lasts on average 142 seconds.”*

### Proposed schema (Phase 1)

**Option A – Single events table with `event_type`**

- Keep `drop_events` but rename conceptually to **availability_events** (or add a new table and backfill).
- Add columns:
  - `event_type`: enum **NEW_DROP** | **CLOSED** | (optional: STILL_AVAILABLE | BASELINE_AVAILABLE).
  - `closed_at` (nullable): when we detected slot gone.
  - `drop_duration_seconds` (nullable): closed_at − opened_at for CLOSED.
  - `slot_date`, `slot_time`, `time_bucket` (prime/off_peak), `party_sizes` (e.g. JSON [2,4]), `provider`, `neighborhood`, `price_range` (nullable).
- For **NEW_DROP**: we already have opened_at, venue_id, venue_name, payload; add event_type=NEW_DROP, others null.
- For **CLOSED**: insert a new row with event_type=CLOSED, same slot_id/bucket_id, closed_at=now, drop_duration_seconds=now−opened_at of the corresponding NEW_DROP (lookup by bucket_id+slot_id, latest opened_at).

**Option B – Two tables**

- **drop_events** (or **availability_events**): only “slot opened” (NEW_DROP) and “slot closed” (CLOSED) events; add duration and time-bucket on CLOSED.
- **slot_lifecycle**: one row per (bucket_id, slot_id) with first_seen_at, last_seen_at, baseline_status, last_event_type. Updated on each poll; used to compute duration on close and to avoid duplicate CLOSED.

Recommendation: **Option A** with one table and `event_type` keeps queries simple; we can add a small **slot_lifecycle** or key-value cache if we need fast “last opened_at for this slot” for duration calculation.

### Implementation sketch (Phase 1)

1. **Migration:** Add to `drop_events`: `event_type` (default NEW_DROP), `closed_at`, `drop_duration_seconds`, `time_bucket`, `slot_date`, `slot_time`, `provider`; optionally `neighborhood`, `price_range`, `party_sizes_json`.
2. **In `run_poll_for_bucket` (after updating prev → curr):**
   - **Closed set:** `closed_slots = prev_set - curr_set`.
   - For each slot_id in closed_slots:
     - Find latest NEW_DROP for (bucket_id, slot_id) to get `opened_at`.
     - `duration = now - opened_at`.
     - Insert **CLOSED** event row: same bucket_id, slot_id, venue_id, venue_name; event_type=CLOSED; closed_at=now; drop_duration_seconds=duration; time_bucket from bucket’s time_slot; slot_date/slot_time from bucket_id + payload if needed.
   - Continue inserting NEW_DROP rows as today (with event_type=NEW_DROP and new columns filled).
3. **Dedupe:** One CLOSED per (bucket_id, slot_id) per “close” (we only close once per lifecycle). Use a dedupe_key like `closed|{bucket_id}|{slot_id}|{closed_at_minute}` if needed.

---

## 2. Venue-level intelligence

**Idea:** Rolling aggregates per venue so we can rank “hardest tables” and show scarcity/volatility.

### Metrics to store (per venue, e.g. in `venue_metrics` or columns on `venues`)

- `drop_frequency_per_day` (e.g. last 14 days)
- `prime_time_drop_frequency`
- `avg_drop_duration_seconds`, `median_drop_duration_seconds`
- `percent_days_fully_booked` (days with zero drops in prime?)
- `volatility_score` (e.g. std of daily drop count)
- `scarcity_score` = f(percent time fully booked, prime-time drop rarity, drop speed)

Store **computed at** (timestamp) so we know freshness; refresh in a nightly or hourly job from **availability_events**.

### Schema (Phase 2)

- New table **venue_metrics** (or add columns to **venues** if we want one row per venue):
  - `venue_id` (FK or same PK as venues), `computed_at`, `drop_frequency_per_day`, `prime_time_drop_frequency`, `avg_drop_duration_seconds`, `median_drop_duration_seconds`, `percent_days_fully_booked`, `volatility_score`, `scarcity_score`.
- Job: aggregate from availability_events (NEW_DROP + CLOSED) by venue_id, time_bucket, date; then compute metrics and upsert.

---

## 3. Market-level metrics

**Idea:** Cross-venue trends—cancellation waves, holiday spikes, release patterns.

### Store (e.g. **market_metrics** or time-series table)

- `window_start`, `window_end` (e.g. last 24h, or 14-day window)
- `total_drops_per_hour` (or per day)
- `drops_by_neighborhood` (JSON or separate rows)
- `drops_by_day_of_week` (JSON or separate rows)
- `prime_time_volatility_index`
- `14_day_forward_availability_density` (e.g. count of slots in baseline across 14 days)

This can be **batch-computed** from availability_events + discovery_buckets; store results in a **market_metrics** table (one row per window type and period) or in a small **market_snapshots** table with JSON for breakdowns.

### Schema (Phase 3)

- **market_metrics**: `id`, `metric_type` (e.g. drops_per_hour, by_neighborhood), `window_start`, `window_end`, `value_json` or scalar columns, `computed_at`.

---

## 4. User behavior (critical for monetization)

**Idea:** Which alerts convert, how fast users act, what filters correlate with bookings.

### Events to capture

- `alert_sent_at` (we sent a push/in-app alert)
- `alert_opened_at` (user opened the alert)
- `tap_to_reserve_at` (user tapped “reserve” / deep link)
- `booking_confirmed` (user confirmed booking in our flow or reported success)
- `time_to_action_seconds` (e.g. alert_sent → tap_to_reserve)
- `goal_match_score` (how well the drop matched user’s goal)
- **Conversion:** alert_sent → booking_confirmed; alert_opened → booking_confirmed.

### Schema (Phase 4)

- **user_behavior_events** (or **alert_events**): `id`, `user_id` (or device/session), `event_type` (alert_sent | alert_opened | tap_to_reserve | booking_confirmed), `occurred_at`, `drop_event_id` (FK to availability_events), `venue_id`, `time_to_action_seconds` (nullable), `goal_match_score` (nullable), `metadata_json`.
- Or **alerts** table: one row per alert with columns `sent_at`, `opened_at`, `tap_to_reserve_at`, `booking_confirmed_at`, `drop_event_id`, `user_id`, etc.

Client (iOS/Android/web) must send these events to the backend; backend only stores. No need to store full scraped HTML or redundant slot snapshots.

---

## 5. Optional but valuable

- **Goal-based monitoring:** Store user goal windows (date range, time, party size, neighborhood); goal_match_rate; % of drops that matched goals; % of matched drops that converted. Feeds into “intentional” product and better pricing.
- **Supply compression:** From baseline vs current slot counts: total_slots_at_baseline, pct_drop_change_vs_baseline, scarcity_delta. Enables “Supply tightened 34% this weekend.”

---

## 6. What we do **not** store

- Full scraped HTML or raw API response blobs (we already don’t).
- Redundant slot snapshots every poll (we store transitions: NEW_DROP, CLOSED).
- Overly granular fields we won’t query or aggregate.

We **do** store: transitions, durations, and aggregates. Signal, not noise.

---

## 7. Why this matters

If the upstream API changes or goes away, we still have:

- Historical scarcity and drop duration per venue and time bucket
- Volatility and market-level trends
- User behavior and conversion data

That’s a **durable asset**. If we only ever showed a feed and never stored dynamics, we’d have nothing.

---

## 8. Implementation order

| Phase | What | Delivers |
|-------|------|----------|
| **1** | Availability events: event_type (NEW_DROP/CLOSED), closed_at, drop_duration_seconds, time_bucket, slot_date/slot_time, provider. Emit CLOSED when prev−curr. | Full transition history and “Friday 7pm at Carbone lasts 142s on average.” |
| **2** | Venue metrics table + aggregation job from events. | Scarcity score, drop frequency, avg duration per venue. |
| **3** | Market metrics table + job. | Drops per hour, by neighborhood, by weekday, volatility index. |
| **4** | User behavior events table + API for client events. | Alert sent/opened, tap-to-reserve, booking confirmed, conversion. |

---

## 9. Phase 1 implementation status (done)

- **Migration 028:** Added to `drop_events`: `event_type`, `closed_at`, `drop_duration_seconds`, `time_bucket`, `slot_date`, `slot_time`, `provider`, `neighborhood`, `price_range`; indexes on `event_type` and `closed_at`.
- **NEW_DROP:** Every new drop now stores `event_type=NEW_DROP`, `time_bucket` (prime/off_peak from time_slot), `slot_date`/`slot_time` from payload, `provider=resy`, and optional `neighborhood`/`price_range` from payload.
- **CLOSED:** When `prev_set - curr_set` is non-empty, for each closed slot we look up the latest NEW_DROP for that (bucket_id, slot_id), compute `drop_duration_seconds = now - opened_at`, and insert a row with `event_type=CLOSED`, `closed_at=now`, `drop_duration_seconds`, and slot identity copied from that NEW_DROP. Dedupe key: `closed|{bucket_id}|{slot_id}|{closed_at_minute}`.
- **Feed/just-opened/still-open:** All continue to use only NEW_DROP events (filter `event_type=NEW_DROP`) so the product feed and lists are unchanged; CLOSED events are stored for analytics and future venue/market metrics.

Next: **Phase 2** (venue_metrics table + aggregation job from events).
