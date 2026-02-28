# Scalability and Overtime Concerns

Analysis of DB and discovery code for scalability, growth, and long-term maintenance. Use this for capacity planning and refactors.

---

## 1. Unbounded queries (high impact)

### 1.1 `get_still_open_from_buckets` — loads all drop_events for 28 buckets

**Where:** `app/services/discovery/buckets.py` → `get_still_open_from_buckets(..., use_drop_events=True)`.

**Issue:** With `use_drop_events=True` (default), the code does:

```python
q = db.query(DropEvent).filter(DropEvent.bucket_id.in_(bucket_ids)).order_by(DropEvent.opened_at.desc())
# ...
events = q.all()  # NO LIMIT — can load 50k+ rows and full payload_json
```

**Impact:** As `drop_events` grows (14 days × 28 buckets × many drops), this loads every matching row and all `payload_json` into memory. Used by:

- `GET /chat/watches/just-opened`
- `GET /chat/watches/still-open`
- `refresh_feed_cache()` (if/when called after poll)

**Fix:** Add a configurable limit (e.g. 5_000–10_000) and `.limit(N)` before `.all()`. Still-open is a “recent and still available” view; capping is acceptable. Prefer a constant (e.g. `STILL_OPEN_EVENTS_LIMIT`) so it can be tuned.

---

### 1.2 `get_just_opened_from_buckets` — already capped, but high cap when time window set

**Where:** Same file, `get_just_opened_from_buckets`.

**Current:** When `opened_within_minutes` is set, `effective_limit = max(limit_events, 5000)` (up to 5k events). Default `limit_events=500`. So we already cap, but 5k rows + payloads is still heavy.

**Recommendation:** Keep the cap; consider lowering 5k to 2k–3k if memory or latency becomes an issue. Document the constant.

### 1.3 `GET /chat/watches/new-drops` — scalable with `since` + composite index

**Where:** `app/api/routes/discovery.py` → `new_drops`; `app/services/discovery/buckets.py` → `get_just_opened_from_buckets`.

**Improvements:**
- **`since` query param (ISO datetime):** When the frontend sends the previous response’s `at` as `since`, the backend returns only events with `opened_at > since`. Each poll then gets only new drops (smaller payload, no re-sending the same list), so notifications stay “latest” and don’t repeat.
- **Composite index:** `ix_drop_events_event_type_opened_at` on `(event_type, opened_at DESC)` makes the new-drops query efficient as `drop_events` grows (migration 032).

---

## 2. N+1 / repeated queries (medium impact)

### 2.1 `get_bucket_health` — 28 separate queries

**Where:** `app/services/discovery/buckets.py` → `get_bucket_health`.

**Issue:** Loops over 28 bucket IDs and does one `db.query(DiscoveryBucket).filter(DiscoveryBucket.bucket_id == bid).first()` per bucket.

**Fix:** One query: `db.query(DiscoveryBucket).filter(DiscoveryBucket.bucket_id.in_(bucket_ids)).all()`, then build a dict by `bucket_id` and iterate the same list to build the response. **Implemented below.**

---

### 2.2 `ensure_buckets` — 28 queries in a loop

**Where:** `app/services/discovery/buckets.py` → `ensure_buckets`.

**Issue:** For each of 28 (bid, date_str, time_slot), checks existence with a query and optionally inserts. 28 round-trips every time the job runs (and on startup).

**Fix:** One query for all `bucket_id` in the window, then insert only missing bucket_ids in a single batch (one or more `db.add_all` + one `db.commit()`). **Implemented below.**

---

### 2.3 `get_last_scan_info_buckets` — two queries, second loads all 28 rows

**Where:** Same file, `get_last_scan_info_buckets`.

**Current:** (1) `first()` for latest `scanned_at`; (2) `.all()` for all buckets with `date_str >= today` to sum `len(prev_slot_ids_json)`.

**Impact:** Two queries and parsing JSON for 28 rows is acceptable; not a major bottleneck. Optional improvement: single query with `func.max(DiscoveryBucket.scanned_at)` and subquery/expression for total slot count if we want one round-trip.

---

## 3. Data growth and retention (overtime)

### 3.1 `drop_events` — pruned daily only; DELETE is unbounded

**Where:** `prune_old_drop_events(db, today)` in `buckets.py`; called only from `run_sliding_window_job()` (daily), not from the 30s discovery job.

**Issue:**

- Rows for dates before today are deleted with `filter(DropEvent.bucket_id < cutoff).delete(synchronize_session=False)`.
- No `LIMIT`; one big DELETE. With millions of rows, this can hold locks and run for a long time.

**Recommendations:**

- Keep pruning daily; ensure only one sliding-window job runs (no overlap).
- If `drop_events` grows very large (e.g. 500k+), consider batched deletes (e.g. delete 10k at a time in a loop until no rows match) or partition by `bucket_id`/date for easier pruning.
- Optional: run `prune_old_drop_events` from the main discovery job occasionally (e.g. once per hour) with a small batch to smooth out load, or keep daily and monitor lock duration.

---

### 3.2 `venues` — never pruned

**Where:** `app/models/venue.py`; `_upsert_venue` in `buckets.py` adds/updates on every drop.

**Issue:** Table only grows. Over months/years it can accumulate many venues that are no longer in the 14-day window.

**Recommendations:**

- Add optional pruning: e.g. delete venues where `last_seen_at < now() - 30 days` (or only prune if not referenced by any recent `drop_event`). Run from sliding-window job or a weekly task.
- Alternatively, cap table size (e.g. keep 50k most recent) or archive old rows. Document the choice.

---

### 3.3 `discovery_buckets` — pruned and bounded

**Where:** `prune_old_buckets(db, today)` deletes `date_str < today`; called at start of discovery job and sliding-window job.

**Status:** Bounded to ~28 rows (14 days × 2 slots). No change needed.

---

### 3.4 `feed_cache` — single row; payload size unbounded

**Where:** `app/services/discovery/feed_cache.py`; one row with `payload_json` containing full just_opened + still_open + ranked board, etc.

**Issue:** If `get_just_opened_from_buckets` / `get_still_open_from_buckets` return large lists (e.g. 5k venues each), the cached JSON can be several MB. Writes and reads then get heavier.

**Recommendations:**

- Cap the number of items per segment in the cache (e.g. top 500 just_opened, top 1000 still_open) when building the cache.
- Ensure `get_still_open_from_buckets` is capped (see 1.1) so that both feed-building paths are bounded.

---

## 4. Large in-row data (overtime)

### 4.1 `discovery_buckets.baseline_slot_ids_json` / `prev_slot_ids_json`

**Where:** Each bucket row stores two JSON arrays of slot_id strings (32-char hashes).

**Issue:** If Resy returns thousands of slots per bucket, each array can be hundreds of KB. 28 buckets × 2 columns = potential multi-MB per job.

**Recommendations:**

- Monitor row/table size; if needed, cap slot count per bucket (e.g. keep first 2000 slot_ids) and document that “baseline” is then a sample.
- Alternatively, move to a separate `bucket_slots` table keyed by bucket_id + slot_id for easier pruning and indexing.

---

## 5. Indexes and query patterns

**Current indexes (from migrations / models):**

- `discovery_buckets`: `date_str`
- `drop_events`: `bucket_id`, `slot_id`, `opened_at`, unique `dedupe_key`

**Query patterns:**

- Feed / just-opened: `DropEvent` ordered by `opened_at desc`, often filtered by `opened_at >= cutoff`. Index on `opened_at` is used.
- Still-open: `DropEvent` by `bucket_id.in_(...)` and `opened_at < cutoff`. Index on `bucket_id` (and optionally composite `(bucket_id, opened_at)`) would help; `opened_at` alone is already present.
- Bucket health / ensure_buckets: lookups by `bucket_id`. `bucket_id` is primary key for `discovery_buckets`, so no extra index needed.

**Recommendation:** Add composite index on `drop_events (bucket_id, opened_at)` if still-open queries become slow with a limit in place. Measure first.

---

## 6. Connection pool and concurrency

**Current:** `pool_size=8`, `max_overflow=10`; discovery job uses up to 8 worker threads, each with its own session. API requests use `get_db()` and release.

**Status:** Sizing is reasonable for one app instance. If you run multiple workers (e.g. several Uvicorn workers), total connections can exceed pool size; consider pooling at the DB (e.g. PgBouncer) and/or reducing per-process pool size.

---

## 7. Summary of fixes applied in code

- **get_bucket_health:** Replaced 28 per-bucket queries with one `bucket_id.in_(bucket_ids)` query and a dict lookup. (Done.)
- **get_still_open_from_buckets:** Added `STILL_OPEN_EVENTS_LIMIT = 10_000` and `.limit(STILL_OPEN_EVENTS_LIMIT)` before loading events when `use_drop_events=True`. (Done.)
- **ensure_buckets:** Replaced 28 existence checks with one query for existing bucket_ids, then `db.add_all(to_add)` for missing buckets and a single commit. (Done.)

Other items above are documented for future tuning (pruning venues, batched prune of drop_events, feed_cache size, composite index).

---

## 8. TTL, retention, and avoiding hot-path deletes (implemented)

To prevent index bloat and query latency from unbounded growth:

### 8.1 **availability_state (replaces session history)**

- **Before:** `availability_sessions` — one row per open/close window → 230k+ rows from repeated polls.
- **After:** `availability_state` — one row per `(bucket_id, slot_id)`. Upsert on open; on close we update the row, run aggregation, then **delete** the row. Table holds only currently-open slots (bounded).
- **Hot path:** No deletes in the poll loop; we only upsert and update. Deletes happen after aggregation (same run) and in scheduled prune (stale buckets).

### 8.2 **drop_events: events not ticks**

- Only store real drops (slot became available). Already enforced by logic.
- **Retention:** `DROP_EVENTS_RETENTION_DAYS` (env, 7–30). Prune only in **daily** sliding-window job, not every tick.
- **Unique:** Index `(bucket_id, slot_id, venue_id, date_trunc('minute', opened_at))` prevents flapping from creating many rows per minute.

### 8.3 **user_notifications**

- **Retention:** `NOTIFICATIONS_RETENTION_DAYS` (env, 7–90). Prune in daily job and optionally via POST `/watches/prune-now`.

### 8.4 **No heavy deletes in the hot path**

- **Every tick (every ~20s):** Only light work — upsert `availability_state`, ensure buckets, and every N ticks prune `slot_availability` and `availability_state` by bucket date. **No** `prune_old_drop_events` in the tick.
- **Daily job:** `prune_old_drop_events`, `prune_old_notifications`, `prune_old_availability_state`, slot_availability, buckets, metrics, venues.

### 8.5 **Partitioning (future)**

For very large `drop_events` or `user_notifications`, consider **partition by day (or week) on `created_at`/`opened_at`**. Cleanup then becomes **DROP PARTITION** for old dates (O(1), no vacuum pain). Not required at current scale; add when single-table deletes become slow.
