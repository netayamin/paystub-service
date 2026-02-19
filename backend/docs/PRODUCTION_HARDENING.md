# Production hardening checklist

This doc captures hardening rules for the discovery pipeline and related backend so it scales under concurrency, retries, and multiple instances. Each section states the rule and current implementation status.

---

## 1. Request flow

**Rule:** Keep routes thin. Provider (Resy) calls must never run inside the same DB transaction as writes: do network I/O first, then open a short write transaction for diff+apply. One service boundary per feature (discovery, watch, admin); Resy client stays inside services, not in route handlers.

**Status:**
- Routes are thin (call services only). ✅
- Discovery poll: `run_poll_for_bucket` does `fetch_for_bucket` (network) first, then uses the DB session only for read-bucket + diff + apply + commit. No Resy calls inside the transaction. ✅
- Resy is only used inside `services/resy` and discovery’s `fetch_for_bucket`; routes never call Resy directly. ✅

---

## 2. Discovery pipeline: concurrency and ordering

**Rule:** One bucket = one in-flight poll. Use a DB-level lease per bucket so two workers (or restarts) never process the same bucket concurrently. Apply results only if this run is newer than what the projection last applied (explicit last-writer-wins).

**Status:**
- **Bucket lease:** `run_poll_for_bucket` acquires a PostgreSQL advisory lock (by bucket id) at the start of the write phase. If the lock cannot be acquired, the poll is skipped (another worker has the bucket). Lock is held until commit. ✅
- **Apply-if-newer:** Projection upserts use `ON CONFLICT DO UPDATE` with a `WHERE slot_availability.updated_at < excluded.updated_at` so a stale (late) run does not overwrite a newer one. ✅

---

## 3. Baseline behavior

**Rule:** Baseline must not create availability sessions or emit metrics. Set projection state without creating sessions, or use a “baseline” run_type that does not emit sessions/metrics.

**Status:**
- Baseline only updates `discovery_buckets` (baseline_slot_ids_json, prev_slot_ids_json, scanned_at). It does not write to `slot_availability` or `availability_sessions`. ✅

---

## 4. Session invariants

**Rule:** At most one open session per (bucket_id, slot_id). Closing is a single update, not an insert. Open when already open → no-op; close when already closed → no-op. Makes retries safe and keeps session counts bounded.

**Status:**
- **Open:** Before inserting a new `AvailabilitySession` for a drop, we check for an existing open session (closed_at IS NULL) for that (bucket_id, slot_id). If one exists, we skip the insert (idempotent). ✅
- **Close:** We find the open session by (bucket_id, slot_id, closed_at IS NULL), update it with closed_at and duration_seconds. If none found (already closed), we do not add to aggregation (no-op). ✅
- No second row is inserted on close; we only update the existing session row. ✅

---

## 5. Projection table

**Rule:** Keep the projection (slot_availability) small and hot: minimal fields, keyed by what we query most (bucket, slot), updated only on diff. Prune by window (e.g. 14 days), not aggressively.

**Status:**
- Projection is keyed by (bucket_id, slot_id). Updated only when diff says open/close. ✅
- Pruning: `prune_old_slot_availability(db, today)` removes rows for bucket_id before today’s window (14-day window). ✅

---

## 6. Metrics: aggregate on close + idempotency

**Rule:** Aggregate on close (not per poll). Same session close must not be double-counted: either record that the session has been “accounted” (e.g. aggregated_at on the session) or use an upsert keyed by session_id/date. Metrics should be rebuildable from sessions for a time window.

**Status:**
- We aggregate only when a slot closes (in-memory closed data → venue_metrics / market_metrics). ✅
- **Idempotency:** `availability_sessions` has an `aggregated_at` timestamp. We only aggregate closed sessions where `aggregated_at IS NULL`; after writing metrics we set `aggregated_at = now` for those sessions. Prevents double-count on retries. ✅
- Rebuild from sessions: metrics are derived from closed sessions; for a given date range you can recompute from sessions (design allows rebuild scripts). ✅

---

## 7. Notifications: outbox (future)

**Rule:** Do not emit notifications from the poll thread. Use an outbox: discovery writes a “notification_candidate” row on stable open; a notifier job reads the outbox, sends push/SMS/email, then marks the row as sent. Keeps provider/notification latency out of discovery.

**Status:**
- Not implemented. Discovery and notification flow are separate; when we add “notify on drop,” we should introduce a notification_candidate outbox and a notifier job. 📋

---

## 8. Scheduler: multi-instance

**Rule:** In-process APScheduler is fine for v1. If you run more than one backend instance, you must add: leader election (e.g. DB advisory lock) for the scheduler, and per-bucket leases so only one instance processes a given bucket (already done per process; need cross-process).

**Status:**
- Single instance: current design is safe. ✅
- Multi-instance: no leader election or cross-process bucket lease yet. Before scaling to multiple backend replicas, add scheduler leader election and ensure bucket advisory lock is process-wide (same DB). 📋

---

## 9. Retention and feed semantics

**Rule:** Projection = window-bound (14 days). Sessions = product-dependent (e.g. 30–180 days). Metrics = long or forever. Legacy drop_events = short then prune. Make pruning partition-friendly (e.g. time-partition sessions) for future scale.

**Feed semantics:**
- **“Just opened”** = based on session.opened_at (or projection opened_at for open state). Used so “new” drops are stable.
- **“Still open”** = session.closed_at IS NULL (or projection state = open). Avoids open/close flicker from transient misses.

**Status:**
- Pruning: projection and sessions pruned by bucket date (window); drop_events pruned daily. ✅
- Feed/just-opened/still-open read from projection (state = open) and session timestamps. ✅
- Partitioning: sessions table is not yet time-partitioned; add when row count or vacuum becomes an issue. 📋
