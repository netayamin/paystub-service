# Value from data: why the data is the product

**Principle:** If we only show a live feed and delete everything at midnight, we have no moat. The **durable asset** is: scarcity, speed, and behavior—computed from the events we already (or will) collect.

---

## 1. What value means for this product

| Value type | What it is | Who cares |
|------------|------------|-----------|
| **Real-time** | “A table just opened at Carbone.” | User right now; already delivered by feed + notify. |
| **Scarcity** | “Carbone is one of the hardest tables in NYC; slots last ~2 min.” | User choosing where to try; differentiator vs “just a list.” |
| **Timing** | “Friday 7pm drops more than Tuesday 3pm; prime time is brutal.” | User planning when to watch; content and expectations. |
| **Conversion** | “Users who get alerts for Tatiana book 3x more than for random venues.” | Us: pricing, messaging, which venues to push. |

Real-time is table stakes. **Scarcity, timing, and conversion are the defensible value**—and they all depend on **keeping and aggregating data**, not only showing then deleting it.

---

## 2. Data → product value (concrete)

### A) Venue-level: “How hard is it?”

**Data we need:** Per-venue aggregates over time (from events we already have or will have):

- Drop frequency (drops per day / per week).
- Average (and median) **drop duration** (how long a slot stays open).
- Prime vs off-peak mix.
- Optional: % of days with zero prime-time drops (“fully booked”).

**Product value:**

- **Rankings:** “Hardest tables in NYC,” “Easiest of the hard,” “Getting better / getting harder.”
- **Expectations:** “Slots here usually last ~2 minutes—have Resy open.”
- **Lists:** Curate “truly impossible” vs “tough but doable” (Infatuation list + our own scores).
- **Trust:** Numbers from our system, not a generic “hard to get” label.

**Requirement:** We must **aggregate from drop_events (and CLOSED events) into a `venue_metrics` (or similar) table *before* pruning**. Otherwise we delete the only source of truth for scarcity.

---

### B) Market-level: “What’s going on in the market?”

**Data we need:** Time-series and distributions:

- Drops per hour / per day (total and by neighborhood if we have it).
- By day-of-week, prime vs off-peak.
- Optional: “Supply compression” (e.g. % change in available slots vs baseline).

**Product value:**

- **Content:** “Drops spiked this weekend,” “Tuesday is the quietest day,” “Prime time is 2x more volatile.”
- **Context:** “Right now the market is really tight” vs “Good week to try.”
- **Editorial / social:** Charts, weekly digests, “State of NYC reservations.”

**Requirement:** Compute from events (and maybe discovery_buckets), store in **market_metrics** (or equivalent); again, **before** we prune old events.

---

### C) User behavior: “Did we help you get a table?”

**Data we need:** Funnel per alert / per drop:

- Alert sent → opened → tap-to-reserve → booking confirmed.
- Time-to-action (e.g. seconds from alert to tap).
- Link to drop_event (venue, time, slot) and optionally “goal match.”

**Product value:**

- **Product:** “You’re 3x more likely to book when we alert you for venues you saved.”
- **Monetization:** Value-based pricing (e.g. premium for “hardest” or for guaranteed alerts).
- **Optimization:** Which venues and which messaging convert; when to send.

**Requirement:** Backend (and clients) **persist** these events; they are independent of pruning (they reference drop_event_id but don’t need raw events forever).

---

## 3. What we do today vs what we need

| Layer | Today | Gap |
|-------|--------|-----|
| **Events** | We store NEW_DROP + CLOSED, duration, time_bucket (Phase 1). | Done. |
| **Venue metrics** | **Implemented (Phase 2).** Table `venue_metrics`; aggregation runs *before* prune. API: `GET /chat/watches/venue-metrics?days=14&limit=100`. | Optional: volatility_score, rolling 7d/14d. |
| **Market metrics** | **Implemented (Phase 2).** Table `market_metrics`; same job writes `daily_totals`. API: `GET /chat/watches/market-metrics?days=14`. | Optional: by_neighborhood, by_weekday. |
| **User behavior** | None. | Need **alert_events** + API for clients (Phase 4). |

So: **we now aggregate before prune.** Venue and market metrics are persisted; raw drop_events are pruned daily. Next: user behavior events for conversion.

---

## 4. Order of operations (so data = value)

1. **Aggregate before prune** ✅ Done.
   - In `run_sliding_window_job()` we call `aggregate_before_prune(db, today)` then `prune_old_drop_events(db, today)`.
   - Job: `app/services/aggregation/aggregate.py`; reads events with `bucket_id < today_15:00`, writes `venue_metrics` and `market_metrics`, then prune runs.

2. **Venue metrics (Phase 2)** ✅ Done.
   - Table: `venue_metrics` (venue_id, window_date, new_drop_count, closed_count, prime_time_drops, off_peak_drops, avg/median_drop_duration_seconds, scarcity_score, volatility_score).
   - API: `GET /chat/watches/venue-metrics?days=14&limit=100` for rankings and predictions.

3. **Market metrics (Phase 2)** ✅ Done.
   - Table: `market_metrics` (window_date, metric_type, value_json). Currently `daily_totals` with total_new_drops, total_closed, avg_drop_duration_seconds.
   - API: `GET /chat/watches/market-metrics?days=14`.

4. **User behavior (Phase 4)** Next.
   - Table: `alert_events` (or user_behavior_events): event_type, occurred_at, drop_event_id, venue_id, time_to_action_seconds, etc.
   - API: POST /events or /alerts/track for client (iOS) to send alert_sent, alert_opened, tap_to_reserve, booking_confirmed.
   - Product: Conversion reports, value-based messaging, pricing.

---

## 5. One-line summary

**Value = real-time (we have it) + scarcity + timing + conversion.** Scarcity and timing need **aggregates from the same events we currently delete**; conversion needs **behavior events**. So: **aggregate before delete**, then add venue_metrics, market_metrics, and behavior tracking. After that, the data is the product’s moat.
