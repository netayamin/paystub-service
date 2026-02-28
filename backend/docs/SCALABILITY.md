# Discovery scalability and DB optimization

This doc describes how we keep the discovery stack bounded and avoid timeouts as data grows.

## 1. Hard limits (constants)

All discovery query limits are centralized in **`app/core/constants.py`**:

| Constant | Value | Use |
|----------|--------|-----|
| `DISCOVERY_JUST_OPENED_LIMIT` | 2000 | Max `slot_availability` rows per just-opened request |
| `DISCOVERY_STILL_OPEN_LIMIT` | 3000 | Max rows for still-open view |
| `DISCOVERY_ROLLING_METRICS_LIMIT` | 4000 | Max `venue_rolling_metrics` rows for feed enrichment |
| `DISCOVERY_FEED_LIMIT` | 100 | Default max rows for GET /feed |
| `DISCOVERY_MAX_VENUES_PER_DATE` | 500 | Cap venues per date in just-opened/still-open |

Change these in one place; routes and services import them so responses and DB load stay bounded.

## 2. Retention (pruning)

Tables are kept bounded by **retention pruning**:

- **Discovery bucket job (every tick)**  
  - `prune_old_buckets`: drop `discovery_buckets` with `date_str < today`.  
  - Every **`DISCOVERY_PRUNE_EVERY_N_TICKS`** ticks (~50s): also run  
    **Every tick:** `prune_old_drop_events`. Every **`DISCOVERY_PRUNE_EVERY_N_TICKS`** ticks: `prune_old_slot_availability`, `prune_old_sessions`  
    so `slot_availability`, `drop_events`, and `availability_sessions` don’t grow.

- **Sliding window job (daily)**  
  - Same pruning as above plus:  
  - `prune_old_venue_rolling_metrics(db, today, keep_days=60)`: drop `venue_rolling_metrics` older than 60 days.

Result:

- **discovery_buckets**: only current 14-day window.
- **drop_events**: (1) bucket_id before today (same as others); (2) rows with `opened_at` older than `DROP_EVENTS_RETENTION_DAYS` (7 days) **and** `push_sent_at` set; (3) when a slot is marked closed, the corresponding `drop_events` row is deleted if `push_sent_at` is already set.
- **slot_availability**, **availability_sessions**: only current window; pruning runs every N ticks and daily.
- **venue_rolling_metrics**: last 60 days only (daily job).
- **venue_metrics**, **market_metrics**: last **90 days** only (`METRICS_RETENTION_DAYS`); pruned in the daily sliding-window job.
- **venues**: rows with `last_seen_at` older than **90 days** (`VENUES_RETENTION_DAYS`) are pruned in the daily job so the table does not grow unbounded.

## 3. Indexes

- **slot_availability**  
  - `ix_slot_availability_state_opened_at` **(state, opened_at)**  
    Used by: just-opened and feed queries  
    `WHERE state = 'open' ORDER BY opened_at DESC LIMIT N`.  
  - `ix_slot_availability_bucket_state` **(bucket_id, state)**  
    Used by: retention deletes and still-open filter.  
  - **040** `ix_slot_availability_bucket_state_opened_at` **(bucket_id, state, opened_at DESC)**  
    Used by: still-open query (filter by bucket + state, order by opened_at).

- **drop_events**  
  - Indexes on `bucket_id`, `opened_at` (see migrations 023, 032, 035) for new-drops and pruning.

- **venue_rolling_metrics**  
  - `venue_id`, `as_of_date` for lookups and retention delete.  
  - **040** `ix_venue_rolling_metrics_computed_at` **(computed_at DESC)**  
    Used by: feed enrichment `ORDER BY computed_at DESC LIMIT N`.

Run `alembic upgrade head` so migrations **038** and **040** (and any later ones) are applied.

## 4. Bounded queries

- **Just-opened**  
  - Single query: `slot_availability` with `state = 'open'`, `opened_at` filter, `ORDER BY opened_at DESC`, `LIMIT DISCOVERY_JUST_OPENED_LIMIT`.  
  - Rolling metrics: `ORDER BY computed_at DESC LIMIT DISCOVERY_ROLLING_METRICS_LIMIT` (no unbounded `.all()`).

- **Aggregation**  
  - `VenueMetrics` for rolling compute: `window_date >= since` with `.limit(50_000)`.

- **Feed**  
  - `get_feed`: `limit` capped (default `DISCOVERY_FEED_LIMIT`, max 500).

## 5. Monitoring

- **GET /chat/watches/row-counts**  
  Returns approximate row counts (from `pg_class.reltuples`, fast — no full table scan). Use it to:  
  - Confirm pruning is keeping tables in check.  
  - Spot growth before it causes timeouts.

**DB super slow?**

1. Check row counts: `GET /chat/watches/row-counts`. If `slot_availability` or `venue_rolling_metrics` are huge (e.g. >100k), prune isn’t keeping up or indexes are missing.  
2. Run `alembic upgrade head` so migrations 038 and 040 (indexes) are applied.  
3. Reset discovery to clear bloat: `POST /chat/watches/reset-discovery-buckets`, then restart the backend.  
4. Optionally run `VACUUM ANALYZE slot_availability;` (and other large tables) in PostgreSQL.  
5. Confirm pruning is running (every ~50s in the bucket job; daily sliding window for venue_rolling_metrics).

## 6. Checklist for new code

- No unbounded `.all()` on large tables: use `.limit(N)` and define N in `constants.py` if it’s discovery-wide.
- Any new discovery table that grows over time should have a retention strategy (prune in sliding window or in the bucket job).
- New filters that are used in hot paths (e.g. just-opened, feed) should be covered by an index (composite if multiple columns).
