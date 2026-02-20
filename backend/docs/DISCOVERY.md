# Discovery: rolling 14-day snapshots and hot drops

## Goal

We maintain a **rolling 14-day window** of availability snapshots. The **original** snapshot per date (first successful scan) is stored and never overwritten. Every 1 minute we re-scan (skipping if the previous run is still in progress), overwrite the **current** snapshot, and surface **just opened** — venues in the current scan that were not in the original (tables that opened since baseline).

**Product alignment (Resy Snapshot Monitor):**
- 14-day window, anchor times **3:00 PM** and **7:00 PM** — each is a **time range**: the Resy client returns availability **±2 hours** around the anchor (so 3pm → ~1pm–5pm, 7pm → ~5pm–9pm). Party sizes **2–5**.
- First run per date = baseline (original). Every 1 minute: re-scan (skip if previous run still in progress), overwrite current; compare to original.
- "Just opened" = venue in current but not in original; we keep first-seen time (hot_drops_json) so the UI shows "X min ago" until the venue drops.
- We compare at **slot level**: `slot_id = hash(provider, venue_id, actual_time)` where `actual_time` is the reservation start (e.g. `"2026-02-18 20:30:00"`). Baseline is "restaurants and their times" — each (venue, time) is one slot. New since baseline = `C - B`; added since last poll = `C - P`; drops (fresh) = `(C - P) ∩ (C - B)`.

## Flow

1. **Window**  
   Dates covered: `[today, today+1, ..., today+13]`. We **prune** any stored row with `date_str < today` so the table only holds the current window.

2. **Each scan run (every 30 seconds)**  
   For each date in the window:
   - Fetch current availability from Resy: **3pm and 7pm** anchor times with **±2h** window (Resy returns a range around each), **per_page=200**, **max_pages=2**, party sizes 2–4. Merge by venue.
   - **Original snapshot**: `previous_venues_json` is set only on the **first** successful scan for that date and is **never overwritten**. Every run we only update `venues_json` (current), `scanned_at`, and `hot_drops_json`.
   - After all dates, delete rows where `date_str < today`.

3. **Hot drops (comparison)**  
   For each date, **just opened** = venues in `venues_json` whose name is **not** in the **original** snapshot (`previous_venues_json`). `hot_drops_json` stores `[{ "name", "detected_at" }]` so we keep first-seen time; we only show venues still in current.

### Baselines without blocking the server

We want a **baseline snapshot** per bucket, then compare each **next run** to it (and to the previous run) to see what’s new. To keep the backend responsive on small instances:

- **No baseline step in the main tick.** Each tick only: prune old buckets, ensure all 28 bucket rows exist (INSERT if missing), then dispatch up to N “ready” buckets to a **thread pool** for polling. The main thread never calls Resy.
- **First poll = baseline.** When a bucket is polled for the first time (or has `baseline_slot_ids_json` NULL), `run_poll_for_bucket` sets `baseline = prev = curr` and returns. So the first successful poll establishes the baseline; subsequent polls compute drops as `(curr − prev) ∩ (curr − baseline)`.
- **Result:** The API stays responsive (no long Resy/DB work in the request-handling process), and we still get the same semantics: baseline once, then compare every run to baseline and previous.

The **sliding-window job** (daily) still baselines the 2 new-day buckets so they’re warm; optional and only 2 Resy calls per day.

## Light profile (small instances, e.g. t3.micro)

Discovery is configurable via **environment variables** so the same code can run with less load on a 1 GB instance. Set these in `backend/.env` (or EC2) to reduce memory and API usage:

| Env var | Default | Light suggestion | Effect |
|--------|---------|-------------------|--------|
| `DISCOVERY_DATE_TIMEZONE` | America/New_York | — | Timezone for "today" (window start and pruning). Ensures users see today's results when server is UTC. |
| `DISCOVERY_WINDOW_DAYS` | 14 | 7 | Fewer buckets (7 days × slots). |
| `DISCOVERY_TIME_SLOTS` | 15:00,19:00 | 19:00 | Only prime-time slot → half the buckets. |
| `DISCOVERY_PARTY_SIZES` | 2,4 | 2 | One party size → half the Resy calls per bucket. |
| `DISCOVERY_MAX_CONCURRENT_BUCKETS` | 8 | 2 | Fewer buckets in flight → lower memory spike. |
| `DISCOVERY_BUCKET_COOLDOWN_SECONDS` | 30 | 45 | Slightly less frequent re-poll per bucket. |
| `DISCOVERY_RESY_PER_PAGE` | 100 | 50 | Fewer venues per Resy request. |
| `DISCOVERY_RESY_MAX_PAGES` | 5 | 2 | Cap Resy results per search (e.g. 100 venues max per party size). |

**Example light `.env` block** (paste into `backend/.env` on EC2 or local):

```env
DISCOVERY_WINDOW_DAYS=7
DISCOVERY_TIME_SLOTS=19:00
DISCOVERY_PARTY_SIZES=2
DISCOVERY_MAX_CONCURRENT_BUCKETS=2
DISCOVERY_RESY_PER_PAGE=50
DISCOVERY_RESY_MAX_PAGES=2
```

Omit any variable to keep the default. On a larger instance (e.g. t3.small), use defaults or increase concurrency/results for fuller coverage.

## Data model and scale (bucket + drop_events)

- **We do not store a “venues” table.** We store:
  - **discovery_buckets**: 28 rows (14 days × 2 time slots). Each row holds `baseline_slot_ids_json` and `prev_slot_ids_json` (arrays of slot_id hashes). No venue names in buckets.
  - **drop_events**: One row per “drop” (a slot that opened since baseline). Each row has `venue_id`, `venue_name`, and `payload_json` (full venue snapshot for that slot). Same venue can appear in many events (different dates/times).
- **“How many venues saved?”** = distinct `venue_id` in `drop_events`. Exposed in `GET /chat/watches/db-debug` as `db.unique_venues_in_drop_events`.
- **Scalability**: (1) **Buckets** — fixed 28 rows; JSON size per row is ~hundreds of slot_ids (fine). (2) **drop_events** — **unbounded**: every poll that sees a new slot inserts a row; there is no retention/cleanup. Over weeks this can reach tens of thousands of rows. Just-opened and still-open APIs use `limit_events` (500–5000) so reads stay bounded; writes and table size grow until you reset or add retention (e.g. delete events older than N days).
- **Retention**: `drop_events` are pruned every run: we delete rows for dates before today (we only care about today and future). Same for `discovery_buckets`. No unbounded growth.
- **Target scale:** For a CQRS-style design (projection + event log, soft state, sessions, retention), see [SCALABLE_DISCOVERY_ARCHITECTURE.md](SCALABLE_DISCOVERY_ARCHITECTURE.md).

## Code layout

- **`app/services/discovery/`**  
  - `scan.py` — `run_scan()`, `get_hot_drops()`, `_just_opened_venues()`, `_previous_venue_names()`, `_prune_old_scans()`.  
  - `__init__.py` — re-exports `run_discovery_scan`, `get_just_opened` (aliases for API/scheduler).

- **`app/models/discovery_scan.py`**  
  One row per date: `date_str` (PK), `venues_json`, `previous_venues_json`, `hot_drops_json` (first-seen per venue), `scanned_at`.

- **`app/scheduler/discovery_scan_job.py`**  
  Calls the discovery bucket job every 30 seconds (interval set in `DISCOVERY_POLL_INTERVAL_SECONDS`).

- **API**  
  `GET /chat/watches/just-opened` returns `{ "just_opened": get_just_opened(db), "next_scan_at": "…" }`.

## Debugging: see what’s in the DB

**Fast checks (do in order):** (1) Confirm job alive — `GET /chat/watches/discovery-health` → `job_alive` / `is_job_running`; check worker logs around the run time (e.g. 8:36 PM ET). No job runner table or Redis lock. (2) Hit `just-opened` and `discovery-debug` — empty just-opened + known openings = feed not updating; frozen discovery-debug = not progressing. (3) Stuck on one date — in logs, last "Discovery scan fetching date YYYY-MM-DD" with no "Discovery scan date ... done" after it = stuck on that date.

Use these to verify discovery is running and inspect DB state:

| What | How |
|------|-----|
| **Fast checks** | `GET /chat/watches/discovery-health` — job_alive, feed_updating, log_hint. |
| **Quick overview** | `GET /chat/watches/db-debug` — discovery row count, last scan time, fast_checks, job heartbeat. |
| **Per-date detail** | `GET /chat/watches/discovery-debug` — per-date `venues_count`, `original_venues_count`, `hot_drops_count`, `scanned_at`, and a **sample of just opened** (name + `detected_at` + `minutes_ago`). |
| **CLI** | From `backend`: `poetry run python scripts/discovery_debug.py` — same data as discovery-debug, printed to the terminal. |

Example:

```bash
# Quick check (backend running)
curl -s http://127.0.0.1:8000/chat/watches/db-debug | jq

# Full per-date + hot drops sample
curl -s http://127.0.0.1:8000/chat/watches/discovery-debug | jq
```

**Refresh baselines in place (live-safe):** `POST /chat/watches/refresh-discovery-baselines` — re-runs baseline for all 28 buckets **without deleting any data**. Overwrites each bucket's baseline and prev with a fresh snapshot (current Resy search area). Use after changing the search bounding box; drop_events and history stay. Safe for production.

**Reset buckets (nuclear):** `POST /chat/watches/reset-discovery-buckets` — deletes all `discovery_buckets` and `drop_events`. Next job run creates new baselines. Use only when you want a full wipe.

**When to refresh (not reset):** After changing the Resy search area (e.g. bounding box in `app/services/resy/config.py` or `RESY_SEARCH_BOX_EXPAND_DEGREES`), run a reset so baselines are re-taken with the new area. Otherwise existing baselines were built from the old search area and you’ll get a burst of false “drops” for venues that are just newly inside the box.

**What happens after a reset:** On the next discovery job run (within ~1 min), the job (1) creates 28 buckets, (2) runs baseline for each (fetches current Resy availability and sets baseline = prev = curr), (3) runs the normal poll (no drops yet). So "just opened" and "still open" stay empty until slots open *after* that new baseline.

**Monitoring buckets (no refresh needed):** To see whether baselines are filled and when each bucket was last scanned, use:

- **`GET /chat/watches/bucket-status`** — Returns all 28 buckets with `bucket_id`, `date_str`, `time_slot`, `last_scan_at`, `baseline_count`, `stale`, plus a `summary` (total, stale_count, all_fresh). Use this to poll or open in a tab for live monitoring.
- **`GET /chat/watches/discovery-health`** — Same `bucket_health` array plus job heartbeat, next_scan_at, and critical/stale alerts.

**View initial snapshot:** `GET /chat/watches/baseline` — per-bucket `baseline_count`, `baseline_slot_ids`, `baseline_scanned_at`. When running the refresh script, progress is printed per bucket: `[1/28] 2026-02-13_15:00 — filled with N slots`.

**All buckets must run every time.** The discovery job is scheduled **every 30 seconds** and polls all 28 buckets **in parallel** (run completes in ~1–2 min). If the previous run is still in progress, the next run is **skipped** to avoid overlap and extra Resy load. Each bucket is therefore re-scanned every 30s–2 min. Any bucket that fails is **retried once**. If a bucket still fails after retry, the job sets `job_heartbeat.error` and logs at ERROR. Stale buckets (not scanned in 4+ hours) are excluded from API results.

**Stale buckets:** Buckets not scanned in the last **4 hours** (`STALE_BUCKET_HOURS`) are **excluded** from just-opened and still-open. `GET /chat/watches/discovery-health` returns `bucket_health` (each with `stale: true/false`), `stale_bucket_count`, `stale_bucket_ids`, and **`all_buckets_fresh`** (true only when no stale buckets). If any bucket is stale, the response also includes **`critical: true`** and a **`message`** explaining that this is a major issue and to check job_heartbeat and logs.

**Just-opened filters:** `GET /chat/watches/just-opened` accepts `dates`, `time_slots=15:00,19:00`, and `party_sizes=2,3,4,5`. Backend filters just-opened and still-open by date, time bucket (3pm/7pm), and party size so opened, hotspots, and rest all respect person count and time on the server.

### Debugging date filtering (just-opened / still-open)

Filtering by calendar dates is done on the backend via `?dates=YYYY-MM-DD,YYYY-MM-DD`. To verify it’s correct:

1. **No filter (all dates):**
   ```bash
   curl -s "http://127.0.0.1:8000/chat/watches/just-opened?debug=1" | jq '._debug'
   ```
   Check `just_opened_dates`, `still_open_dates`, and `*_per_date` counts.

2. **With filter:** pick one or two dates that appear above, then:
   ```bash
   curl -s "http://127.0.0.1:8000/chat/watches/just-opened?dates=2026-02-12,2026-02-13&debug=1" | jq '._debug'
   ```
   - `date_filter_sent` should be `["2026-02-12", "2026-02-13"]`.
   - `just_opened_dates` and `still_open_dates` must only contain those dates (or subsets if no data for a date).
   - For each date in `*_per_date`, counts should match the same date in the unfiltered response.

3. **Sanity:** Unfiltered total venue count per date should be ≥ filtered count for that date; filtered response must not contain any date not in `date_filter_sent`.

Backend logs: after each successful scan you’ll see `Discovery scan DB written at <UTC> (<N> dates, <M> venues)` and `Discovery scan finished: ...`. Per date: "Discovery scan fetching date YYYY-MM-DD (N/14)" then "Discovery scan date ... done (M venues)" or "Resy error".

## Invariants and feed-item debug

- **Emitted set:** `drops = (curr - prev) ∩ (curr - baseline)`. So `baseline_echo = |emitted ∩ baseline|` and `prev_echo = |emitted ∩ prev|` must be **0**.
- Per bucket poll we log and return these counts; last run is in `GET /chat/watches/db-debug` → `job_heartbeat.last_poll_invariants` (and in the app Debug panel). If `baseline_echo_total > 0` we log ERROR.
- **Readiness = baseline initialized:** We emit only when `baseline_slot_ids_json` is not `None`. `"[]"` is initialized (empty baseline); we do normal diff and can emit. Rows created by `ensure_buckets` have null baseline; `run_poll_for_bucket` initializes them (baseline=prev=curr) on first run, then subsequent runs emit.
- **Feed-item debug:** `GET /chat/watches/feed-item-debug?event_id=N` or `?slot_id=...&bucket_id=...` returns `in_baseline`, `in_prev`, `in_curr` (optional `fetch_curr=1`), `emitted_at`, `reason`. If `in_baseline: true` → baseline echo bug.
- **Still open:** Only slots that (1) we emitted (in drop_events), (2) are still in prev, and (3) are **not** in baseline. So venues that were available in the initial snapshot never appear in "still open".
- **Pro sanity tests:** (1) Run 2 polls back-to-back — second should emit ~0. (2) Pick 20 feed items, call feed-item-debug; none should have `in_baseline: true`. (3) Same slot in feed again 1–2 min later → dedupe/slot_id/prev bug.

## No Redis; one Postgres; job runs in-process

- **No Redis.** There is no Celery, RQ, arq, or dramatiq. No `CELERY_BROKER_URL` or Redis broker. Discovery state (baseline/prev, drop_events) lives only in Postgres. The blueprint doc once mentioned Redis as a future option; the current implementation does not use it.
- **Job runner:** APScheduler (`BackgroundScheduler`) in the same process as the FastAPI app. Jobs call `SessionLocal()` and use the same `settings.database_url` as the API. So the job and the API use the same Postgres — no “second DB” or env mismatch. If you reset and nothing changed, confirm the backend process you hit (e.g. `curl localhost:8000`) is the same one that runs the scheduler (same `DATABASE_URL` / `.env`).
- **Health dump and “22 vs 28” / null baselines:** `discovery_buckets_count` is the raw table row count. `bucket_health` always has 28 entries (one per `all_bucket_ids(today)`). If you see `baseline_count: 0` and `last_scan_at: null` for some buckets, that usually means: (1) that bucket’s row wasn’t created yet, or (2) baseline wasn’t initialized and the poll for that bucket hasn’t completed yet, or (3) you sampled mid-run. If the table count is 22 instead of 28, either six buckets failed during ensure/poll (check logs and `run_poll_all_buckets` errors) or prune removed old dates and the next run hasn’t added the new day yet (expected 28 after a full run).

## Dependencies

- Resy: `app/services/resy` (`search_with_availability`).
- Resy URL helper: `app/services/venue_watch_service._resy_venue_url` (for booking links).
