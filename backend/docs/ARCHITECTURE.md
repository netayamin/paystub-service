# Backend architecture

This document describes how the backend is structured and how a request flows from HTTP to the Resy API. Use it to understand the codebase before scaling (new agents, tools, or features).

---

## 1. High-level request flow

```
  HTTP Request
       │
       ▼
  main.py (FastAPI app)
       │
       ▼
  api/routes/ (chat.py, resy.py)   ← thin: parse body, get db, call service/orchestrator
       │
       ▼
  orchestrator/orchestrator.py     ← routes by message to an agent
       │
       ▼
  agents/resy_agent.py             ← Pydantic AI Agent + toolsets
       │
       ▼
  toolsets/resy/tools.py          ← tools the agent can call (search, watch, notify, …)
       │
       ▼
  services/                        ← business logic + external APIs
       ├── resy/                    (Resy HTTP client)
       ├── chat_session_service
       ├── venue_snapshot_service
       ├── venue_watch_service
       ├── venue_notify_service
       └── …
       │
       ▼
  models/ + db/session.py          ← SQLAlchemy models, DB session
```

- **Routes** do not contain business logic. They validate input, get a DB session, call the orchestrator or a service, and return HTTP.
- **Orchestrator** is the single entry point for “chat”: it picks an agent by name and runs it (sync or stream).
- **Agents** are Pydantic AI agents: system prompt, model, and tools. They do not touch the DB directly; they use **deps** (e.g. `ResyDeps`: `db`, `session_id`, `last_venue_search`).
- **Tools** are the only place the agent touches the app: they receive `RunContext[ResyDeps]`, call **services**, and optionally set `deps` fields (e.g. `last_venue_search` for the stream).
- **Services** hold all business logic and external calls (Resy API, DB reads/writes). Tools are thin over services.

---

## 2. Directory layout and responsibilities

```
backend/
├── app/
│   ├── main.py                 # FastAPI app, router mount, scheduler, health
│   ├── config.py               # Settings (DB, OpenAI, Resy keys)
│   │
│   ├── api/
│   │   └── routes/
│   │       ├── chat.py         # POST /chat, POST /chat/stream, GET /chat/venues, sessions, messages, watches, …
│   │       └── resy.py         # /resy/watch (legacy watch list)
│   │
│   ├── core/
│   │   └── errors.py           # agent_error_to_http, HTTP rules for agent failures
│   │
│   ├── db/
│   │   ├── base.py             # SQLAlchemy Base
│   │   └── session.py         # engine, SessionLocal, get_db()
│   │
│   ├── models/                 # SQLAlchemy ORM (one file per table)
│   │   ├── chat_session.py
│   │   ├── venue_watch.py
│   │   ├── venue_watch_notification.py
│   │   ├── venue_search_snapshot.py
│   │   ├── venue_notify_request.py
│   │   ├── tool_call_log.py
│   │   ├── booking_attempt.py
│   │   └── watch_list.py
│   │
│   ├── orchestrator/
│   │   ├── orchestrator.py     # run(), run_stream(); routes message → agent
│   │   └── registry.py         # agent name → (agent, deps_factory); registers "resy"
│   │
│   ├── agents/
│   │   ├── deps.py             # ResyDeps(db, session_id, last_venue_search)
│   │   ├── resy_agent.py       # Agent with instructions + resy_toolset
│   │   └── resy_agent_instructions.md
│   │
│   ├── toolsets/
│   │   └── resy/
│   │       ├── __init__.py     # resy_toolset (FunctionToolset)
│   │       └── tools.py        # search_venues_with_availability, start_watch, start_venue_notify, …
│   │
│   ├── services/               # Business logic + external I/O
│   │   ├── chat_session_service.py    # get_messages, save_messages, save_last_venue_search, get_last_venue_search
│   │   ├── venue_snapshot_service.py  # Snapshot by criteria (names only); check_for_new_venues, check_specific_venues_availability, save_broad_search_snapshot
│   │   ├── venue_watch_service.py     # start_watch, run_watch_checks (specific-venue + new-venue), notifications
│   │   ├── venue_notify_service.py    # notify-when-available (Resy notify), get_my_watches
│   │   ├── tool_call_log_service.py
│   │   ├── resy_auto_book_service.py  # booking attempt + Resy book flow
│   │   ├── watch_list_service.py      # legacy hourly watch list
│   │   ├── resy_client.py             # thin wrapper (optional)
│   │   └── resy/                      # Resy API
│   │       ├── __init__.py            # search_with_availability (high-level)
│   │       ├── client.py              # HTTP (ResyClient)
│   │       └── config.py              # ResyConfig from env
│   │
│   ├── scheduler/              # Background jobs (APScheduler in main.py)
│   │   ├── venue_watch_job.py  # every 1 min → run_watch_checks
│   │   ├── venue_notify_job.py # every 1 min → venue notify checks
│   │   └── hourly_resy.py      # every 1 hour → watch list check
│   │
│   ├── data/                   # Static/curated data (no DB)
│   │   ├── infatuation_hard_to_get.py
│   │   └── nyc_hotspots.py
│   │
│   └── schemas/                # (Pydantic request/response; currently minimal, some in routes)
│
├── alembic/                    # Migrations (versions/ 001–017)
├── docs/
│   ├── ARCHITECTURE.md         # this file
│   └── RESY_BOOK.md
└── scripts/
```

---

## 3. Chat and stream flow (detail)

1. **Client** sends `POST /chat/stream` with `{ message, session_id? }`.
2. **chat.py** gets `db` via `get_db()`, resolves `session_id` (or creates one), loads `message_history = get_messages(db, session_id)`.
3. **orchestrator.run_stream** is called with `(message, db, message_history=..., session_id=...)`.
4. **Orchestrator** calls `_route(message)` → `"resy"`, then `registry.get("resy")` → `(agent, deps_factory)`. It builds `deps = deps_factory(db, session_id)` and runs `agent.run_stream_events(message, deps=deps, message_history=...)`.
5. **Agent** (Pydantic AI) may call tools; each tool receives `ctx: RunContext[ResyDeps]` (so `ctx.deps` is the same `ResyDeps` instance). Tools call **services** and may set `ctx.deps.last_venue_search`.
6. **Orchestrator** maps agent events to a simple protocol:
   - `PartStartEvent` / `PartDeltaEvent` (text) → `("text", content)`
   - `AgentRunResultEvent` → if `deps.last_venue_search` set → `("venues", list)`, then `("result", result)`.
7. **chat.py** turns these into SSE: `data: {"content": "..."}`, `data: {"venues": [...]}`, `data: {"done": true, "session_id": "..."}`. On `("result", ...)` it calls `save_messages(db, session_id, payload.all_messages_json())`.
8. **DB**: Messages and (when the tool ran) `last_venue_search` are persisted per session; the frontend can also GET `/chat/venues?session_id=...` to get the last search for the sidebar.

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

- **OpenAI**: Used by the agent (model). Key in `config.settings.openai_api_key`.
- **Resy**: All Resy HTTP is in **services/resy/** (`client.py` + `__init__.py`). Keys in `config.settings.resy_api_key`, `resy_auth_token`.
- **DB**: PostgreSQL. URL in `config.settings.database_url`. Migrations: `alembic upgrade head`.

---

## 7. How to extend

- **New agent**: Add an agent in `agents/`, register it in `orchestrator/registry.py`, and (if needed) change `_route()` in `orchestrator.py` to return its name for certain messages.
- **New tool**: Add a function in `toolsets/resy/tools.py` (or a new toolset), add it to the toolset’s list, and implement it by calling **services** and optionally setting `ctx.deps` fields.
- **New API route**: Add a route in `api/routes/chat.py` or `resy.py`; keep the handler thin (parse, get_db, call service/orchestrator, return).
- **New background job**: Add a function in `scheduler/`, then in **main.py** `lifespan` add `_scheduler.add_job(...)`.

---

## 8. Summary

| Layer        | Role |
|-------------|------|
| **api/routes** | HTTP in/out; no business logic. |
| **orchestrator** | Single entry for chat; routes to one agent; normalizes agent events to a simple stream. |
| **agents**   | Pydantic AI agent (prompt, model, tools); no DB, only deps. |
| **toolsets** | Tools the agent calls; thin over **services**; may set `deps` for the stream. |
| **services** | All business logic and I/O (DB, Resy, snapshot, watch, notify). |
| **models**   | SQLAlchemy tables. |
| **scheduler** | Periodic jobs that call services with their own DB session. |

Keeping this layering consistent will make it easier to scale (e.g. add another agent or another external API) without duplicating logic or mixing HTTP, orchestration, and business logic.
