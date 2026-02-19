# Database & Jobs Scalability Review

Expert review of the backend data model, indexes, hot paths, and jobs for scale and optimization as data grows. Use this for capacity planning and refactors.

---

## Executive summary

| Area | Verdict | Notes |
|------|---------|------|
| **Read path (just-opened / still-open)** | ✅ Bounded, index-friendly | Limits (500–10k), composite index on `(event_type, opened_at DESC)`. Can scale to hundreds of thousands of `drop_events` with current design. |
| **Write path (per-bucket poll)** | ⚠️ N+1 on CLOSED events | One query per closed slot to find `last_drop`; can be 10–100+ queries per bucket when many slots close. |
| **Aggregation job** | 🔴 Critical: unbounded load | `aggregate_before_prune` currently loads **all** `drop_events` into memory. With 100k+ rows this will OOM or time out. Must filter by `bucket_id < cutoff`. |
| **Pruning** | ✅ Bounded | Delete by `bucket_id < today_15:00`; index on `bucket_id` supports it. Table size stays bounded by 14-day window. |
| **Discovery buckets** | ✅ Fixed 28 rows | No growth; JSON columns are manageable. |
| **Metrics tables** | ✅ Bounded | One row per (venue, window_date) or per (venue, as_of_date); growth is linear in venues × days. |

**Bottom line:** The system can scale to more data **if** you (1) fix aggregation to use a bounded query, (2) eliminate the N+1 when emitting CLOSED events, and (3) add one composite index for the still-open query. Everything else is already capped or indexed reasonably.

---

## 1. Data model & indexes

### 1.1 `drop_events`

| Column | Index | Notes |
|--------|--------|--------|
| `bucket_id` | ✅ `ix_drop_events_bucket_id` | Used by just-opened (filter by bucket in still-open), pruning (range delete), aggregation (range filter). |
| `slot_id` | ✅ `ix_drop_events_slot_id` | Used for lookups. |
| `opened_at` | ✅ `ix_drop_events_opened_at` | Used for ordering and time filters. |
| `dedupe_key` | ✅ unique | Prevents duplicate inserts; used for existence check before insert. |
| `event_type` | ✅ `ix_drop_events_event_type` | Used in all read paths. |
| `event_type` + `opened_at` | ✅ `ix_drop_events_event_type_opened_at` (DESC) | **Critical** for just-opened and new-drops: “recent NEW_DROP by time.” |

**Missing index (recommended):** For `get_still_open_from_buckets` the query filters by `bucket_id.in_(28 ids)` and `event_type = 'NEW_DROP'`, then orders by `opened_at desc` and limits. A composite index improves plan quality and avoids scanning more rows than needed:

- **Recommendation:** `(bucket_id, event_type, opened_at DESC)` — supports “per-bucket, NEW_DROP only, most recent first” in one index.

### 1.2 `discovery_buckets`

- 28 rows (fixed). `bucket_id` PK, `date_str` indexed. No scalability concern.

### 1.3 `venue_metrics` / `market_metrics` / `venue_rolling_metrics`

- Unique constraints and existing indexes are appropriate. Growth is by (venue × window_date) or (venue × as_of_date), which is acceptable.

---

## 2. Hot path: GET /chat/watches/just-opened

**Flow:** `get_just_opened_from_buckets` → `get_still_open_from_buckets` → `build_feed`.

### 2.1 `get_just_opened_from_buckets`

- **Query:** `DropEvent` with `event_type == NEW_DROP`, optional `opened_at >= cutoff` (e.g. last 5 min), `order_by opened_at.desc()`, **limit 500 or 5000**.
- **Index:** `ix_drop_events_event_type_opened_at` (DESC) is used. Good.
- **Bounded:** Yes (5000 max). Payloads for 5k rows are heavy but acceptable; consider 2k–3k if latency grows.

### 2.2 `get_still_open_from_buckets`

- **Query:** `DropEvent` with `bucket_id.in_(bucket_ids)`, `event_type == NEW_DROP`, optional `opened_at < cutoff`, `order_by opened_at.desc()`, **limit 10_000** (`STILL_OPEN_EVENTS_LIMIT`).
- **Index:** Today only `ix_drop_events_bucket_id` (and possibly `event_type`). Adding `(bucket_id, event_type, opened_at DESC)` would make this scale better.
- **Bounded:** Yes (10k). Good.

### 2.3 In-memory work

- After loading events, the code filters by “slot still in prev,” date_filter, party_sizes, time range, and dedupes by venue per date. All in Python. With 5k–10k rows this is fine; if you ever raise limits, watch CPU.

---

## 3. Write path: per-bucket poll (`run_poll_for_bucket`)

### 3.1 NEW_DROP inserts

- **Dedupe:** One query for `dedupe_key.in_(dedupe_keys)` (batch). Then `db.add_all(to_insert)`. Good.
- **Volume:** One batch per bucket per poll; size = number of new drops. Bounded by Resy response size. Fine.

### 3.2 CLOSED events — N+1 (must fix for scale)

For each slot that disappeared (`closed_slots = prev_set - curr_set`), the code does:

```python
last_drop = db.query(DropEvent).filter(
    DropEvent.bucket_id == bid,
    DropEvent.slot_id == sid,
    DropEvent.event_type == EVENT_TYPE_NEW_DROP,
).order_by(DropEvent.opened_at.desc()).limit(1).first()
```

So **one query per closed slot**. If 50 slots close in one bucket, that’s 50 round-trips. With 8 buckets in flight and many closures, this multiplies.

**Recommendation:** Load “last drop per (bucket_id, slot_id)” in one or two queries, then build a dict:

1. Collect all `(bid, sid)` for closed_slots.
2. Query once: all `DropEvent` rows with `(bucket_id, slot_id)` in those pairs, `event_type == NEW_DROP`, then in Python take the latest `opened_at` per (bucket_id, slot_id) (or use `DISTINCT ON (bucket_id, slot_id) ... ORDER BY opened_at DESC` in raw SQL).
3. Build `to_insert_closed` from that map.

That replaces N queries with 1 (or 2) per bucket.

---

## 4. Aggregation job (`aggregate_before_prune`) — critical

**Current implementation (problematic):**

```python
events = db.query(DropEvent).all()  # Loads entire table
```

- With 50k–500k+ `drop_events` (e.g. before daily prune), this:
  - Loads every row and full `payload_json` into memory → risk of OOM.
  - Holds the connection and blocks the job for a long time.
  - Can cause timeouts and backpressure on the DB.

**Required fix:** Only aggregate events that are about to be pruned (same as prune window):

```python
cutoff = f"{today_str}_15:00"
events = (
    db.query(DropEvent)
    .filter(DropEvent.bucket_id < cutoff)
    .all()
)
```

- Row count is then bounded by “events in buckets older than today” (e.g. at most ~14 days of data). Still large but bounded and predictable.
- Optional: stream or chunk (e.g. by `bucket_id` ranges) and aggregate in chunks so memory stays bounded even with a large window.

**Rolling metrics:** The step that reads `VenueMetrics` for the last 14 days and writes `VenueRollingMetrics` is fine; it’s one query with a date filter and a bounded number of rows.

---

## 5. Pruning (`prune_old_drop_events`)

- **Query:** `DELETE FROM drop_events WHERE bucket_id < cutoff` (string comparison matches bucket_id ordering).
- **Index:** `ix_drop_events_bucket_id` supports finding rows to delete. Deletes can be large but run once per day; consider batching (e.g. delete in chunks by bucket_id) if lock duration becomes an issue.

---

## 6. Job design

### 6.1 Discovery bucket job (tick every N seconds)

- Up to 8 buckets in parallel; each has its own DB session; 30s cooldown per bucket. Good.
- Risk: DB connection pool size must be ≥ 8 (plus API requests). Monitor pool usage.

### 6.2 Sliding window job (daily)

- Order: **aggregate_before_prune** → prune_old_buckets → prune_old_drop_events → ensure_buckets → baseline new day.
- Correct: aggregate before prune so no data loss. Only aggregation’s **scope** (all vs `bucket_id < cutoff`) must be fixed as above.

---

## 7. Recommendations summary

| Priority | Action |
|----------|--------|
| **P0** | **Aggregation:** Change `aggregate_before_prune` to filter `DropEvent.bucket_id < today_15:00` (or equivalent). Do not load all `drop_events`. |
| **P1** | **CLOSED N+1:** Replace per-slot query for `last_drop` with one (or two) batched query per bucket and build CLOSED inserts from a (bucket_id, slot_id) → latest drop map. |
| **P2** | **Index:** Add composite index on `drop_events (bucket_id, event_type, opened_at DESC)` for `get_still_open_from_buckets` (and similar still-open paths). |
| **P3** | **Just-opened cap:** Consider lowering 5000 to 2000–3000 if response size or latency grows; document the constant. |
| **P4** | **Optional:** Use `feed_cache` for default/unfiltered just-opened and serve from cache when fresh, to reduce repeated heavy queries (see `feed_cache.py`). |

---

## 8. Capacity snapshot (order-of-magnitude)

- **drop_events:** Bounded by 14-day window × ~28 buckets × drops per poll. With ~100–500 drops/day per bucket → tens to low hundreds of thousands of rows before prune. After fix, aggregation only touches “old” buckets (bounded).
- **API:** Each just-opened request: 2 main queries (just_opened + still_open), each limited to 5k–10k rows. With the new index, still-open stays efficient as the table grows.
- **DB connections:** Scheduler + API; ensure pool size accommodates 8 concurrent bucket workers + a few API workers.

With the P0 and P1 fixes and the P2 index, the backend is in good shape to scale to significantly more data and traffic.
