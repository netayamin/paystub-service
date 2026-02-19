# Backend architecture

This document describes how the backend is structured and how a request flows from HTTP to the Resy API. **No chat or agent** — watches, discovery, and Resy only.

For the OOP/SOLID design principles we follow (DRY, SRP, DI, Open Closed, etc.), see **[DESIGN_PRINCIPLES.md](DESIGN_PRINCIPLES.md)**. For production hardening (concurrency, idempotency, retention, outbox), see **[PRODUCTION_HARDENING.md](PRODUCTION_HARDENING.md)**.

---

## 1. High-level request flow

```
  HTTP Request
       │
       ▼
  main.py (FastAPI app)
       │
       ├── /chat/*          → api/routes/watches.py   (watches, availability, booking logs, admin)
       ├── /chat/watches/*  → api/routes/discovery.py (feed, just-opened, health, debug)  [same prefix]
       └── /resy/*          → api/routes/resy.py     (legacy watch list)
       │
       ▼
  api/routes: thin — parse body, get db, call service
       │
       ▼
  services / models + db
```

- **Routes** do not contain business logic. They validate input, get a DB session, call a service, and return HTTP.
- **Routes are split by domain**: **watches** (list watches, availability, watch CRUD, booking logs, admin), **discovery** (feed, just-opened, discovery-health, db-debug, discovery-debug), **resy** (legacy watch list).
- **Services** hold all business logic and external I/O (Resy API, discovery buckets, DB reads/writes).

---

## 2. Directory layout (clean backend structure)

```
backend/
├── app/
│   ├── main.py                    # FastAPI app, CORS, router mount, scheduler, /health
│   ├── config.py                  # Settings (DB, OpenAI, Resy)
│   │
│   ├── api/
│   │   └── routes/                # HTTP layer — one module per domain
│   │       ├── watches.py         # GET /watches, /watches/availability, watch CRUD, /booking-errors, /logs, /admin/clear-db
│   │       ├── discovery.py       # GET /watches/feed, /just-opened, /discovery-health, /db-debug, /discovery-debug
│   │       └── resy.py            # GET/POST /resy/watch (legacy watch list)
│   │
│   ├── core/
│   │   ├── constants.py           # Scheduler job IDs, discovery interval
│   │   └── errors.py              # HTTP error helpers
│   │
│   ├── db/
│   │   ├── base.py                # SQLAlchemy Base
│   │   └── session.py             # engine, SessionLocal, get_db()
│   │
│   ├── models/                    # SQLAlchemy ORM (one file per table)
│   │   ├── chat_session.py        # (kept for DB clear; no chat UI)
│   │   ├── discovery_bucket.py
│   │   ├── drop_event.py
│   │   ├── venue_watch.py
│   │   ├── venue_watch_notification.py
│   │   ├── venue_search_snapshot.py
│   │   ├── venue_notify_request.py
│   │   ├── tool_call_log.py
│   │   ├── booking_attempt.py
│   │   └── watch_list.py
│   │
│   ├── services/                  # Business logic + external I/O
│   │   ├── discovery/             # 14-day drops pipeline (bucket + slot_id + drop_events)
│   │   │   ├── __init__.py        # get_just_opened, get_discovery_debug, get_last_scan_info, fast_checks, heartbeat
│   │   │   ├── buckets.py         # bucket_id, slot_id, fetch, baseline, poll, get_feed, get_just_opened_from_buckets, health
│   │   │   └── scan.py            # set/get_discovery_job_heartbeat, get_discovery_fast_checks
│   │   ├── resy/                  # Resy API
│   │   │   ├── __init__.py        # search_with_availability
│   │   │   ├── client.py          # ResyClient HTTP
│   │   │   └── config.py          # ResyConfig from env
│   │   ├── chat_session_service.py
│   │   ├── venue_snapshot_service.py
│   │   ├── venue_watch_service.py
│   │   ├── venue_notify_service.py
│   │   ├── watch_list_service.py
│   │   ├── tool_call_log_service.py
│   │   ├── resy_auto_book_service.py
│   │   ├── admin_service.py       # clear_resy_db (drop_events, discovery_buckets, …)
│   │   └── resy_client.py         # thin re-export
│   │
│   ├── scheduler/                 # Background jobs (APScheduler in main.py)
│   │   ├── discovery_bucket_job.py # every 30s → poll 28 buckets, emit drops (skip if running); daily sliding window (prune + baseline new day)
│   │   ├── venue_watch_job.py     # every 1 min → run_watch_checks
│   │   ├── venue_notify_job.py    # every 1 min → run_venue_notify_checks
│   │   └── hourly_resy.py         # every 1 hour → watch list check
│   │
│   ├── data/                      # Static/curated data (no DB)
│   │   ├── infatuation_hard_to_get.py
│   │   └── nyc_hotspots.py
│   │
│   ├── schemas/                   # Pydantic request/response (minimal; some in routes)
│   └── static/
│       └── chat_test.html
│
├── alembic/                       # Migrations
├── docs/
│   ├── ARCHITECTURE.md            # this file
│   ├── DISCOVERY.md
│   ├── DISCOVERY_BLUEPRINT.md
│   └── RESY_BOOK.md
└── scripts/
```

---

## 3. Venue / watch / notify (no chat)

- **venue_snapshot_service**: Names per criteria for diffing; used by **check_for_new_venues** and **check_specific_venues_availability**.
- **venue_watch_service**: Interval watches; scheduler runs `run_watch_checks` every minute.
- **venue_notify_service**: Resy notify-when-available plus `get_my_watches` for the UI.
- **chat_session** table is still cleared by admin; no chat UI.

---

## 4. Venue / watch / notify boundaries

- **venue_snapshot_service**: Stores **names only** per criteria key for diffing. Used by:
  - **check_for_new_venues**: broad search → diff vs last snapshot → “new names”.
  - **check_specific_venues_availability**: per-venue search by name → snapshot of who’s available.
  - **save_broad_search_snapshot**: called from the **search_venues_with_availability** tool so the same run that fills the sidebar also updates the snapshot for compare.
- **venue_watch_service**: “Jobs” (interval watches). Two modes:
  - **Specific-venues**: list of names; every N min run `check_specific_venues_availability`; notify when any get availability.
  - **New-venues**: criteria only; every N min run `check_for_new_venues`; notify when new names appear.
- **venue_notify_service**: Resy “notify when available” (one-off or per-venue alerts), plus `get_my_watches` for the UI (interval watches + notify requests + notifications).
- **chat_session_service**: Message history and **last venue search** per session (same list as stream/sidebar; also used by GET `/chat/venues`).

---

## 5. Background jobs (scheduler)

All jobs are registered in **main.py** `lifespan`:

| Job id           | Interval | Function                     | Purpose                                      |
|------------------|----------|------------------------------|----------------------------------------------|
| `venue_watch`    | 1 min    | `run_venue_watch_checks`     | Run all interval watches (specific + new)   |
| `venue_notify`   | 1 min    | `run_venue_notify_checks_job`| Process notify-when-available checks         |
| `resy_hourly`    | 1 hour   | `run_hourly_check`           | Legacy watch list                            |

Each job creates its own DB session (e.g. `SessionLocal()` in the job module), runs the service function, then closes the session.

---

## 6. External dependencies

- **Resy**: All Resy HTTP is in **services/resy/** (`client.py` + `__init__.py`). Keys in `config.settings.resy_api_key`, `resy_auth_token`.
- **DB**: PostgreSQL. URL in `config.settings.database_url`. Migrations: `alembic upgrade head`.

---

## 7. How to extend

- **New API route**: Add a route in `api/routes/watches.py`, `discovery.py`, or `resy.py` (by domain); keep the handler thin (parse, get_db, call service, return).
- **New background job**: Add a function in `scheduler/`, then in **main.py** `lifespan` add `_scheduler.add_job(...)`.

---

## 8. Monitoring discovery (next run + health)

To see **when the next discovery check runs** and that everything is healthy, use one of these:

| Endpoint | What you get |
|----------|----------------|
| **GET /chat/watches/discovery-health** | **next_scan_at** (UTC ISO of next 2‑min bucket run), **fast_checks** (job_alive, feed_updating), **bucket_health** (28 buckets with last_scan_at). Best single place to monitor. |
| **GET /chat/watches/just-opened** | **next_scan_at** + just-opened drops and last_scan_at. |
| **GET /chat/watches/db-debug** | **next_scan_at**, job_heartbeat, discovery_buckets summary, fast_checks, and hints. |

- **next_scan_at**: When the discovery bucket job is scheduled to run next (every 30 seconds).
- **job_alive**: True if the job has written a heartbeat within the last few minutes.
- **feed_updating**: True if the most recent bucket scan is recent (feed is being updated).
- **bucket_health**: Per-bucket last_scan_at so you can see all 28 buckets are being scanned.

---

## 9. Summary

| Layer        | Role |
|-------------|------|
| **api/routes** | HTTP in/out; no business logic. |
| **services** | All business logic and I/O (DB, Resy, discovery, watch, notify). |
| **models**   | SQLAlchemy tables. |
| **scheduler** | Periodic jobs that call services with their own DB session. |
