# Target schema and invariants (Snag drop eligibility)

**Status:** Design brief for Task 1.3 (migrations) and Task 3.1 / 3.1b (eligibility + ranking spec).  
**Ground truth:** We do **not** have Resy “fully booked” as a first-class API fact. “New” is **diff-based** over bucket snapshots. This document defines **honest** stored evidence and **one canonical timestamp** for UX.

---

## 1. Design principles

1. **No fake certainty:** Schema may store **evidence class** and **counts**, not a boolean “was_fully_booked” unless derived from observable scan history.
2. **Single user-facing clock:** **`user_facing_opened_at`** on `drop_events` (new column) is the only timestamp that may drive **“Opened X ago”** in clients. It must be set at insert from the **discovery event** (when the slot entered the “added” set), not from `server_default=now()` drift.
3. **Ranking inputs ≠ analytics UI:** Numeric confidence may exist **for server-side ranking**; do not expose percentages/charts to clients (see Implementation Plan).
4. **Additive first:** New columns and indexes; avoid destructive cuts until a follow-up migration explicitly drops legacy objects.

---

## 2. Table roles (target conceptual model)

| Layer | Table | Target role |
|-------|--------|----------------|
| Bucket memory | `discovery_buckets` | `prev` / `baseline` JSON, poll cadence metadata. |
| Live projection | `slot_availability` | Fast “what’s open now” for feed assembly; **`opened_at` here = projection bookkeeping** — not authoritative for Snag copy if it diverges from drop insert. |
| Compact state | `availability_state` | Open row per (bucket, slot); deleted on close; feeds metrics idempotency. |
| Product drop | `drop_events` | **Canonical row for a “drop”** shown to users; carries **eligibility evidence** + **`user_facing_opened_at`**. |
| Metrics | `venue_metrics`, `venue_rolling_metrics`, `market_metrics` | Aggregates for ranking / sparse copy drivers (existing). |
| Inbox | `user_notifications` | User state; **not** discovery truth. |

**Redundant / legacy (target):**

- **`availability_sessions`:** No writes in application code today. **Target:** stop exporting from public model surface where misleading; **Phase B migration:** `DROP TABLE` after confirming zero dependency in jobs (Task 1.3/1.5 verify + backup).
- **`feed_cache`:** Not on API hot path (`snapshot_store` serves clients). **Target:** (1) **Deprecate** for production read path; (2) either **stop writing** in a later task or restrict to **admin/debug only**; (3) optional **drop table** in a later phase if unused. **Phase A freshness** does not depend on `feed_cache`.

---

## 3. Additive schema changes (`drop_events`)

Add columns (nullable defaults for backfill in Task 1.5):

| Column | Type | Purpose |
|--------|------|---------|
| `user_facing_opened_at` | `TIMESTAMPTZ NOT NULL` (after backfill) | **Canonical** “opened” instant for UX and ranking recency. Set in application to match the poll cycle time when the slot was first detected in `added`. |
| `eligibility_evidence` | `VARCHAR(32) NOT NULL` (default `unknown` for old rows) | Enum-like string; see §4. |
| `prior_snapshot_included_slot` | `BOOLEAN NOT NULL DEFAULT false` | `true` iff `slot_id` was present in **prev** JSON immediately before this open (should be **false** for a true “new” add). |
| `prior_prev_slot_count` | `INT NULL` | Number of slot IDs in **prev** JSON before add (density of prior view). |
| `internal_opened_at` | `TIMESTAMPTZ NULL` | Optional: legacy rename path from current `opened_at` if we need to distinguish; **prefer** using `opened_at` as insert time and `user_facing_opened_at` as event time — **decision:** keep `opened_at` as DB default audit, **require** `user_facing_opened_at` for API. |

**Indexes (Task 1.4):** partial index on `(market, user_facing_opened_at DESC)` for feed hot path if queries switch to canonical time.

**Uniqueness:** Keep existing `dedupe_key` uniqueness.

---

## 4. `eligibility_evidence` values (v1)

Implement as **check constraint** or app-enforced enum (Postgres `CHECK` on allowed strings):

| Value | Meaning | Typical feed treatment (Task 3.1) |
|-------|---------|-----------------------------------|
| `nonempty_prev_delta` | `prior_prev_slot_count > 0` and `prior_snapshot_included_slot = false` | **Strongest** diff signal: slot appeared after a non-empty prior view. |
| `empty_prev_delta` | Prior existed but **empty** (`prior_prev_slot_count = 0`) and slot is new | **Ambiguous:** could be “everything was gone then appeared” or sparse poll; **gate** or down-rank unless other signals. |
| `first_poll_bucket` | No usable `prev` for this bucket (first poll after baseline) | **Weak** — default **disqualify** for “Snag true drop” or heavy down-rank. |
| `baseline_only` | Only baseline comparison available, no stable prev chain | **Weak** — same as thin history. |
| `unknown` | Backfill or legacy row | **Disqualify** or recompute from logs if possible. |

Task 3.1 formalizes predicates; schema only **stores** facts for those predicates.

---

## 5. `discovery_buckets` (additive)

| Column | Type | Purpose |
|--------|------|---------|
| `successful_poll_count` | `INT NOT NULL DEFAULT 0` | Increment after each successful poll. Used for **thin history** (`poll_count < N` → weaker evidence). |

Optional later: `last_nonempty_prev_at` — skip unless needed.

---

## 6. `slot_availability` / `availability_state`

**Target:** No new columns required for Phase A if `drop_events` carries canonical evidence. **Invariant:** When a `drop_events` row is inserted for an add, **`user_facing_opened_at`** must equal the same instant written to `slot_availability.opened_at` for that insert path (buckets.py) — **align in code** in Task 2.x.

**Long-term:** Consider collapsing duplicate venue metadata between tables; **out of scope** for first migration wave.

---

## 7. `app/db/tables.py` inventory (ops)

- Add **`user_notifications`** to **`ALL_TABLE_NAMES`** so admin/reset tooling matches reality.
- **Do not** add to `DISCOVERY_TABLE_NAMES` (not part of discovery TRUNCATE).
- **Do not** add to `FULL_RESET_TABLE_NAMES` by default — full reset would wipe user read state; if product wants “nuclear” reset, document a **separate** list or explicit flag.

---

## 8. Invariants (after a successful bucket poll)

1. **Bucket:** `discovery_buckets.scanned_at` updated; `successful_poll_count` incremented.
2. **Add path:** For each new open slot in `added`:
   - Upsert `slot_availability` / `availability_state` per current logic.
   - Insert `drop_events` with `dedupe_key` unique, `user_facing_opened_at` = detection instant, `eligibility_evidence` + prior fields populated from **actual** prev JSON before mutation.
3. **Evidence:** `prior_snapshot_included_slot` must be **false** for any row we market as “just opened” from a delta; if true, **do not insert** or mark `eligibility_evidence` accordingly (bug if both true and marketed).
4. **Close path:** Existing behavior; metrics aggregation unchanged.

---

## 9. Product phase A minimal signals (no new tables)

Continue to derive from **`venue_rolling_metrics`** / **`venue_metrics`** (typical duration, rarity, demand proxy). **Rule:** APIs return **pre-rendered short phrases** or small integers for ranking-derived badges, **not** raw `%` series for charting.

---

## 10. Migration phasing (for Task 1.3)

1. **048 (example):** Add `drop_events` columns + `discovery_buckets.successful_poll_count`; `NOT NULL` on `user_facing_opened_at` only after backfill or with server default for legacy.
2. **049:** Backfill `user_facing_opened_at` from `opened_at` where reasonable; set `eligibility_evidence='unknown'`.
3. **050:** `tables.py` + model updates; optional CHECK constraint on `eligibility_evidence`.
4. **Later:** Drop `availability_sessions`; remove or stop writing `feed_cache`.

**Breaking cuts:** None required for Phase A if columns are additive with defaults.

---

## 11. Files touched in later tasks

- `app/models/drop_event.py`, `discovery_bucket.py`
- `app/services/discovery/buckets.py` (populate new fields at insert)
- `app/services/discovery/feed.py` / API serialization (read `user_facing_opened_at`)
- `app/db/tables.py`
- `app/models/__init__.py` (export `UserNotification` if we treat as first-class)
