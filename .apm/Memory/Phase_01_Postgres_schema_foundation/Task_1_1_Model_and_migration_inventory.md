---
agent: Agent_Backend_Data
task_ref: Task 1.1
status: Completed
ad_hoc_delegation: false
compatibility_issues: true
important_findings: true
---

# Task Log: Task 1.1

## Summary
Inventory of ORM models, live discovery/feed stack, and Alembic-era evolution; documented entity↔table mapping, hot paths, gaps for a falsifiable “fully booked before open” narrative, and redundant/legacy structures.

## Details
- Read all `backend/app/models/*.py` and `app/models/__init__.py` exports.
- Cross-referenced `backend/app/services/discovery/buckets.py` (canonical poll/write path), `feed.py`, `snapshot_store.py`, `scan.py`, `aggregation/aggregate.py`, and `app/db/tables.py`.
- Noted migration-era evolution from docstrings and `tables.py` (023+ drop of discovery_scans, 034 projection+sessions, 042 availability_state/drop_events, multi-market 045, recent_missed 046, venue profile 047).

## Output

### Entity ↔ model ↔ role (product-oriented)

| Product concern | Table / model | Role |
|-----------------|---------------|------|
| Time-scoped discovery window | `discovery_buckets` / `DiscoveryBucket` | Per (market, date, time_slot): `baseline_slot_ids_json`, `prev_slot_ids_json`, `scanned_at`. Drives diff-based “added” slots. |
| Live open-slot projection | `slot_availability` / `SlotAvailability` | Soft state `open`/`closed`, `opened_at`, `closed_at`, `last_seen_at`, denormalized venue/display fields, `market`. Feed reads. |
| Latest closed-open window (per bucket+slot) | `availability_state` / `AvailabilityState` | Upsert on open; **delete** when closed (see buckets). `aggregated_at` for metrics idempotency. **Primary** session-like row used in poll path (replaces heavy use of `availability_sessions`). |
| Session history (append) | `availability_sessions` / `AvailabilitySession` | Model still exported; **poll path uses `AvailabilityState`**. `tables.py` marks sessions as legacy. |
| Open drops / notify / scoring input | `drop_events` / `DropEvent` | **Open** drops only; `dedupe_key`, `push_sent_at`, closes tracked on row then pruned. Drives metrics before prune. |
| Venue normalization | `venues` / `Venue` | Canonical venue metadata from drops. |
| Precomputed API cache (DB) | `feed_cache` / `FeedCache` | Keyed JSON blob; maintained by `feed_cache.py` — **no references from `app/api`** (hot path is in-memory `snapshot_store`). |
| Per-venue daily metrics | `venue_metrics` / `VenueMetrics` | Counts, durations, scarcity/volatility scores. |
| Rolling 14d venue signals | `venue_rolling_metrics` / `VenueRollingMetrics` | Frequency, rarity, trend fields (**includes `trend_pct`** — for ranking/backend only per product plan). |
| Market aggregates | `market_metrics` / `MarketMetrics` | JSON blobs by `metric_type`. |
| Push devices | `push_tokens` / `PushToken` | APNs tokens. |
| Notify list prefs | `notify_preferences` / `NotifyPreference` | include/exclude by normalized venue name. |
| “Just missed” UX | `recent_missed_drops` / `RecentMissedDrop` | Append-only closes for feed segment. |
| In-app notification inbox | `user_notifications` / `UserNotification` | **Not** in `models/__init__.py` `__all__` but model exists; **not** listed in `app/db/tables.py` `ALL_TABLE_NAMES` (drift vs real DB). |

### Hot paths (where truth moves)

1. **Poll / diff / write:** `app/services/discovery/buckets.py` — Resy (provider) fetch → compare to `DiscoveryBucket` prev → upsert `SlotAvailability`, `AvailabilityState`, create `DropEvent` for qualifying adds, close paths + in-memory `ClosedEventData` → `aggregate_closed_events_into_metrics` / related aggregation.
2. **Feed shape / ranking:** `snapshot_store.rebuild_snapshot` → `feed.build_feed`, `likely_open_scoring`, `feed_display`; reads `SlotAvailability`, `DropEvent`, rolling metrics, buckets helpers.
3. **Prune / retention:** discovery routes + scheduled jobs; `tables.DISCOVERY_TABLE_NAMES` / `FULL_RESET_TABLE_NAMES`.

### Gaps: falsifiable “fully booked before open”

- **No stored predicate** “venue/date was fully booked” from provider; “new” = **set diff** (`curr - prev`) per bucket/party pipeline, not proof of global unavailability.
- **First observation / cold start:** no `prev` or thin baseline ⇒ “opened” can mean “first time we saw this slot,” not “was impossible before.”
- **`DropEvent` is open-only** lifecycle on row; historical proof relies on **prior polls** in `discovery_buckets` JSON or slot_availability history — **not** a durable audit log of “closed inventory state.”
- **Partial coverage:** scans are bucketed (date × time_slot × markets); absence from a snapshot ≠ fully booked across all times/party sizes.
- **`opened_at` semantics** differ by table (e.g. server default vs event time); ranking/eligibility must define which timestamp is **user-facing “opened X ago.”**

### Deprecated / redundant / consolidate later (Task 1.2+)

- **`AvailabilitySession` vs `AvailabilityState`:** align model exports, docs, and whether `availability_sessions` table can be dropped or write path fully removed.
- **`feed_cache` vs snapshot:** either wire `refresh_feed_cache` to a real read path or document as optional cold-cache / remove.
- **`app/db/tables.py`:** add `user_notifications` to `ALL_TABLE_NAMES` (and any other live tables) so reset/prune lists match production.
- **`UserNotification`:** export in `__init__.py` if first-class or document as secondary.

## Issues
None blocking inventory.

## Compatibility Concerns
- `user_notifications` exists (033) and is pruned in code but omitted from `ALL_TABLE_NAMES` in `tables.py` — reset/admin lists may be incomplete vs actual schema.

## Important Findings
- Eligibility for “Snag truth” is **inference from polling diffs**, not a persisted, auditable “was fully booked” fact; Task 3.1 / 3.1b will need explicit predicates over **these** facts (and explicit “unknown/disqualify” rules).
- **Dual projection** (`slot_availability` + `availability_state`) plus **open-only** `drop_events` is powerful for performance but increases the cost of proving narrative consistency — any schema refactor should preserve a single coherent story for ranking inputs.

## Next Steps
- Task 1.2: target schema and invariants addressing gaps above (timestamps, confidence, optional durable pre-state, or explicit disqualification flags).
