---
agent: Agent_Backend_Data
task_ref: Task 1.4 - Indexes and hot-path query optimization
status: Completed
ad_hoc_delegation: false
compatibility_issues: false
important_findings: true
---

# Task Log: Task 1.4 - Indexes and hot-path query optimization

## Summary

Added Alembic **049** with btree and partial indexes on `drop_events` keyed to **`user_facing_opened_at`**, replaced **`ix_drop_events_market`** with **`(market, user_facing_opened_at DESC)`** per `TARGET_SCHEMA_AND_INVARIANTS.md` §3, dropped legacy **`ix_drop_events_opened_at`**, and aligned hot-path readers to the canonical timestamp. Captured **EXPLAIN (ANALYZE, BUFFERS)** for three representative queries locally.

## Details

### Hot-path inventory (before changes)

- **`push_job.py`:** `push_sent_at IS NULL`, `opened_at >= cutoff`, `ORDER BY opened_at ASC`.
- **`buckets.py`:** TTL dedupe `bucket_id` + `opened_at >= cutoff`; `get_just_opened_from_buckets` / `get_still_open_from_buckets` recent pairs via `opened_at >= cutoff`; `_max_opened_at_by_venue` / enrichment query ordered by `opened_at`.
- **`aggregate.py`:** `aggregate_open_drops_into_metrics` filtered on `opened_at >= since`.
- **`feed.py`:** no direct `drop_events` reads (snapshot/cards path).
- **Design:** canonical clock is **`user_facing_opened_at`**; indexing **`opened_at`** duplicates semantics after 048 backfill.

### Migration 049 (`backend/alembic/versions/049_drop_events_hot_path_indexes.py`)

- **`ix_drop_events_user_facing_opened_at`:** general recency windows + push job (filter `push_sent_at` on heap).
- **`ix_drop_events_push_sent_user_facing_opened_at`:** **partial** `WHERE push_sent_at IS NOT NULL` — `prune_old_drop_events` time-based delete.
- **`ix_drop_events_market_user_facing_opened_at`:** `(market, user_facing_opened_at DESC)` — replaces `ix_drop_events_market`.
- **`ix_drop_events_bucket_id_user_facing_opened_at`:** `(bucket_id, user_facing_opened_at)` — per-bucket TTL dedupe.
- **Removed:** `ix_drop_events_opened_at`, `ix_drop_events_market`.

### Code alignment

- **`push_job.py`**, **`buckets.py`** (TTL, just-opened pair queries, prune time branch, max/enrichment), **`aggregate.py`** (open-drop counts): use **`user_facing_opened_at`** for time predicates / ordering.
- **`DropEvent` model:** `__table_args__` **`Index`** entries matching 049 (plus existing column `index=True` on `bucket_id` / `slot_id`); **`market`** no longer `index=True` (composite covers market-leading access).

## Output

- `backend/alembic/versions/049_drop_events_hot_path_indexes.py` (new)
- `backend/app/models/drop_event.py`, `backend/app/scheduler/push_job.py`, `backend/app/services/discovery/buckets.py`, `backend/app/services/aggregation/aggregate.py`
- Local: `alembic upgrade head` and **downgrade/upgrade** cycle verified for 049.

## EXPLAIN (ANALYZE, BUFFERS) — sample (local DB)

**1. Push-style unsent window**

```
Index Scan using ix_drop_events_user_facing_opened_at on drop_events
  Index Cond: (user_facing_opened_at >= cutoff)
  Filter: (push_sent_at IS NULL)
```

**2. Recent distinct (bucket_id, slot_id) — just-opened style**

```
Index Scan using ix_drop_events_user_facing_opened_at on drop_events
  Index Cond: (user_facing_opened_at >= cutoff)
```

**3. Prune pushed-old (partial index)**

```
Index Scan using ix_drop_events_push_sent_user_facing_opened_at on drop_events
  Index Cond: (user_facing_opened_at < (now() - '365 days'::interval))
```

## Issues

None.

## Important Findings

- **`opened_at` index removed:** Any remaining code that filters **only** on `opened_at` for large scans may degrade until switched to **`user_facing_opened_at`** (scripts such as `backfill_venues_from_drop_events.py` still order by `opened_at`; low-frequency).
- **Partial prune index:** Requires `push_sent_at IS NOT NULL` in the query to match the partial predicate — aligned in `prune_old_drop_events`.

## Next Steps

- **Task 1.5:** backfill/consistency checks; optional follow-up to migrate one-off scripts to canonical time.
- **Task 2.1:** populate evidence columns on insert; revisit whether the 048 insert trigger can be narrowed or removed.
