# Scalable discovery architecture (target state)

This doc captures the **target architecture** for discovery/drops so the system scales with multiple providers (Resy, OpenTable), high poll frequency, and long-term analytics. It separates "current state" from "history" from "analytics" and makes the write path idempotent and partitionable.

**Principle:** Don't design around "delete rows when not available"—that doesn't scale and destroys history. Model as a **state machine + event log (CQRS-ish)**.

---

## 1. Two truths

| Truth | Role | Mutability | Scale lever |
|-------|------|------------|-------------|
| **Current view** | "What's available right now?" | Mutable, last-writer-wins | Small, indexed, hot in cache; partition by entity key |
| **Event log** | "What changed and when?" | Immutable, append-only | Events only on **transitions**; partition by time; retention |

The 1-minute job should **only**:
- Mutate the current view (projection).
- Append **transitions** to the event log (no updates, no deletes of events).

**Why it scales:** Reads stay fast (projection is small). Writes stay bounded (events only on changes, not every poll). You can rebuild analytics, debugging, and backfills from the log.

---

## 2. Soft state, not deletes

When restaurant A disappears on run #2, **do not remove it** from the projection. Mark its state as **unavailable** with a timestamp and "last seen" metadata.

**Deletes create scaling pain:**
- You lose ability to compute durations (how long it was open).
- You can't dedupe flapping.
- You can't debug scraper errors ("was it truly unavailable or did parsing fail?").

**Target:** Projection rows have `state` (e.g. `open` | `closed`) and `closed_at` / `last_seen_at`. History is preserved; queries filter by state when needed.

---

## 3. Poll run = snapshot → diff → projection update + event append

Each run is conceptually:

1. **Build observed snapshot** (set of available items: restaurant or restaurant+slot).
2. **Compare to last known projection** (set math).
3. **Write diff:**
   - `to_open = observed - previously_open`
   - `to_close = previously_open - observed`
4. **Apply:**
   - **Projection update** for both sets (soft state: mark open/closed, timestamps).
   - **Event append** for both sets (immutable log).

**Key scalability trick:** Set math, not row-by-row logic. Idempotent per run (e.g. run id + "last writer wins" by run timestamp).

---

## 4. Events only on transitions

The event log should:

- **Append only** when state flips (open → closed or closed → open).
- **Never** update or delete old events.
- **Never** emit an event on every poll—only when the **transition** happens.

Event volume stays proportional to **real changes**, not poll frequency.

---

## 5. Sessions instead of raw flips (biggest win)

Instead of (or in addition to) logging every OPEN/CLOSE flip, store **availability sessions**:

- One record when a slot becomes available (`opened_at`).
- Close that record when it becomes unavailable (`closed_at`, duration).

Result: **1 row per "open window"**, not 2+ rows per minute of noise.

Benefits:
- Clean analytics ("how long it stayed open").
- Far fewer rows than a flip log.
- Easy dedupe and retention (drop old sessions by `closed_at`).

You can keep a short-retention flip log for debugging; **sessions** are the long-term store.

---

## 6. Idempotent + safe under retries

The job will retry, overlap, or partially fail. Design DB writes so that **re-running the same run doesn't duplicate**.

- **Run id:** Give every poll run a unique run id.
- **Event writes:** Idempotent per (entity, transition, run) so reprocessing doesn't double-append.
- **Projection updates:** "Last writer wins" by run timestamp (or run id).

Result: Safe to reprocess runs or process late runs without corrupting state.

---

## 7. Partitioning

| Table / use | Partition by | Reason |
|-------------|--------------|--------|
| **Projection / state** | Entity key (e.g. `slot_id` or `restaurant_id`) | Hot reads/writes; per-entity locality; scale by sharding. |
| **Event log / sessions** | Time (daily/monthly) | Queries are time-bounded; cheap to drop old partitions (retention). |

---

## 8. Flapping: stabilization layer

Polling every minute will see jitter (parsing errors, transient blocks). If you notify on a single "open" you'll spam.

**Strategy:**
- Projection = **raw observed state** (for correctness).
- Before **user notifications**, apply a lightweight stability rule:
  - e.g. require **2 consecutive runs open** before "notify open";
  - require **2 consecutive runs closed** before "notify closed".
- Optionally still log raw transitions for debug; **gate notifications** on stable transitions.

Reduces downstream load (push/SMS) drastically.

---

## 9. Metrics = rollups, not queries over raw events

Don't query the whole event/session table for dashboards. At scale that becomes expensive.

- **Event/session log** = source of truth (append-only, then retention).
- **Rollup tables** (daily/hourly) = updated **incrementally** when events/sessions are written (or in a separate async job).
- **Dashboards** read rollups only (tiny, fast).

Standard "event log + incremental aggregation" pattern.

---

## 10. Pipeline boundaries (scale beyond 1 worker)

Think in layers:

| Layer | Responsibility | Scale |
|-------|----------------|-------|
| **Collector** | Fetch provider pages/APIs | Parallelized by provider/date/slot |
| **Normalizer** | Canonical keys (restaurant/slot) | Stateless |
| **Diff engine** | Set diff vs projection | Stateless |
| **Writer** | Transactionally update projection + append events | Partition by entity |
| **Notifier** | Consume "notification-ready" events asynchronously | Decoupled; own queue/workers |

**Critical:** Notification work is **decoupled** from polling so polling stays fast and notifiers can scale independently.

---

## 11. Retention (so "millions" doesn't mean "infinite")

| Data | Retention | Purpose |
|------|-----------|---------|
| **Raw run snapshots** | 7 days | Debugging, backfill |
| **Debug / noisy flip events** | 30 days | Telemetry only |
| **Sessions + rollups** | 1–2 years (or forever) | Analytics, product |

Partition by time so **dropping old partitions** is cheap (no huge deletes). Millions of rows is fine if writes are append-only, partitioned, and retained aggressively.

---

## 12. Slot granularity (Resy + OpenTable)

- **Restaurant-level:** Fewer keys, fewer events, less data—but less useful notifications.
- **Slot-level** (date + time + party size): More keys, more events—real product value.

Same architecture either way; only the **entity key** changes.

---

## 13. Mental rule

- **Projection** = the product ("what's open now"). App UI queries this.
- **Events / sessions** = audit trail and notification source. Analytics and rollups read these.
- **Rollups** = for dashboards and reporting (tiny, fast).

---

## Relation to current implementation

| Current | Target (this doc) |
|---------|-------------------|
| `drop_events` = "open drops only"; we delete when slot closes | Projection table: soft state (open/closed + timestamps); no delete on close |
| No persistent event log (we aggregate on close then delete) | Append-only event log (or sessions) for transitions; never delete events |
| Metrics from aggregation at close time | Same idea; rollups updated incrementally from events/sessions |
| Single table for "current" truth | Explicit projection (small) + event/session store (partitioned, retained) |
| No run id / idempotency | Run id; idempotent event writes; last-writer-wins projection |
| No debounce for notifications | Optional: 2 consecutive open/closed before emitting user-facing notify |

Migration path: Introduce a **projection** table (e.g. `slot_availability` with state + timestamps) and an **event or session** table; keep writing to both from the diff engine. Then move reads to projection and notifications to events; finally deprecate "delete on close" and keep only soft state + append-only history.
