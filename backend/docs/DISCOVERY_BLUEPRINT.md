# Discovery Drops — Blueprint (Target Architecture)

**Goal:** Users see newly opened (“drops”) for the next 14 days, 3pm + 7pm, updated every 30 seconds (job skips if previous run still in progress), at scale.

## 1) Data model

- **Bucket**  
  `bucket = (date, time_slot)` where `time_slot ∈ {15:00, 19:00}`.  
  **28 buckets** (14 days × 2).

- **Slot ID (stable key)**  
  `slot_id = hash(provider, venue_id, actual_time)` where `actual_time` is the reservation start (e.g. `"2026-02-18 20:30:00"`). One id per venue+time so baseline is "restaurants and their times". Store slot IDs in baseline/prev; fetch full payload only when emitting drops.

## 2) Storage

- **Redis (hot)** — target for production:
  - `baseline:{bucket}` → SET(slot_id) TTL 15 days
  - `prev:{bucket}` → SET(slot_id) TTL 10 min
  - `seen:{bucket}` → SET(slot_id) TTL 1–2 h (dedupe)

- **DB (durable)** — implemented first (Redis can be added later):
  - **discovery_buckets** — (bucket_id, date_str, time_slot, baseline_slot_ids_json, prev_slot_ids_json, scanned_at)
  - **drop_events** — (bucket_id, slot_id, opened_at, venue_id, payload_json, dedupe_key UNIQUE)
  - Optional: venues table for canonical list

## 3) Baseline build

- **When:** New bucket enters the 14-day window (2 new buckets/day).
- **How:** One job per bucket (28 on bootstrap, then 2/day):
  - Fetch availability with bounded concurrency and **timeouts** (e.g. 10–15s) + max retries.
  - Build `baseline_set` (slot IDs only).
  - Write to Redis `baseline:{bucket}` (or DB `discovery_buckets`).
  - Persist baseline stats to DB.

## 4) Polling loop (every 30 seconds)

- Scheduler enqueues **28 poll jobs** (one per bucket).
- **Per bucket:**
  1. Fetch current availability → `curr_set` (slot IDs).
  2. Read `baseline_set` and `prev_set` (from Redis or DB).
  3. **Drops (product rule):** newly opened since last poll AND not in baseline:
     - `drops = (curr - prev) ∩ (curr - baseline)`
  4. Dedupe: `drops = drops - seen` (optional; or use DB dedupe_key).
  5. Emit: insert into **drop_events** with dedupe key `(bucket_id, slot_id, opened_at_minute)`.
  6. Update: `prev = curr`, `seen += drops` (or update DB columns).

## 5) Sliding 14-day window

- **Daily (e.g. 2:05 AM ET):**
  - Drop yesterday’s buckets (delete or TTL).
  - Add new day (today+13): enqueue baseline build for 3pm + 7pm (2 buckets).

## 6) Live updates to UI

- **Backend:** `GET /feed?since=<cursor>` or SSE/WebSocket for new drop_events.
- **Client:** Stream or poll `/just-opened` every 10–30s as fallback.

## 7) Reliability (non-negotiable)

- Timeout all provider calls.
- Max retries + jitter.
- Concurrency limits.
- Idempotent inserts (unique dedupe key).
- Progress / heartbeat logs.
- Per-bucket job sharding.

## 8) Current implementation vs blueprint

| Blueprint | Current (legacy) |
|-----------|------------------|
| 28 buckets (date × time_slot) | 14 rows (date only; 3pm+7pm merged) |
| slot_id (hash) | venue name |
| baseline / prev / seen (Redis or DB) | previous_venues_json / venues_json (full payload) |
| drop_events table + dedupe | hot_drops_json (embedded) |
| Per-bucket jobs | Single monolithic run_scan() |
| Feed endpoint with cursor | GET /just-opened (no cursor) |

**Migration path:** New code uses buckets + slot_id + drop_events. Legacy `discovery_scans` can stay for backward compat until UI and jobs are switched over; then remove.
