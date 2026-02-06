# Resy Booking Agent

Backend service with an AI agent that books NYC restaurants via Resy: find hotspots, search availability, book reservations, and add venues to an **hourly watch list** that checks for new spots every hour.

## Stack

- **Python 3.11+**, **FastAPI**, **Uvicorn**
- **PostgreSQL**, **SQLAlchemy 2**, **Alembic**
- **pydantic-ai**, **OpenAI** (Resy booking agent)
- **httpx** (Resy API client), **APScheduler** (hourly check)
- **Maxim AI** (optional: tracing and evaluation)

## Resy credentials (no official public API)

Resy does not publish a public API. Use credentials from your browser:

1. Log in at [resy.com](https://resy.com).
2. Open DevTools → Network. Visit a restaurant page and try to find a time.
3. Find requests to `api.resy.com`. In request headers you need:
   - **RESY_API_KEY** — from `Authorization: ResyAPI api_key="..."`
   - **RESY_AUTH_TOKEN** — from `x-resy-auth-token`

Add them to `backend/.env`:

```bash
RESY_API_KEY=your_key
RESY_AUTH_TOKEN=your_token
```

## Quick start

```bash
# From project root
cd paystub-service
cp backend/.env.example backend/.env   # add OPENAI_API_KEY, RESY_API_KEY, RESY_AUTH_TOKEN

# Start Postgres
docker compose up -d db

# Backend: install, migrate, run
cd backend && poetry install && poetry run alembic upgrade head
poetry run uvicorn app.main:app --reload --port 8000
```

## Endpoints

- **POST /chat** — Chat with the Resy agent (body: `{"message": "...", "session_id": "optional"}`).  
  The agent can: list NYC hotspots, search availability, book, add to watch list, show watch list.
- **GET /resy/watch** — List venues on the hourly watch list.
- **POST /resy/watch** — Add a venue to the watch list (body: `{"venue_id": 35676, "party_size": 2, "preferred_slot": "dinner", "notify_only": true}`).
- **GET /health** — Health check.

## Hourly check

A background job runs **every hour**. For each venue on the watch list it:

- Checks Resy for availability (today and tomorrow).
- If **notify_only** is true: logs when slots are found (you can add webhook/email later).
- If **notify_only** is false: attempts to book the first available slot.

## NYC hotspots

Curated list of NYC “hardest” reservations is in `backend/app/data/nyc_hotspots.py`. Venue IDs are placeholders except Cote (35676); replace with real Resy venue IDs from resy.com URLs or network requests.

## Example chat prompts

- “What are the NYC hotspots / hardest reservations?”
- “Any availability at Cote tomorrow for 2?”
- “Search Carbone next Friday for 4 people.”
- “Watch Cote for me every hour and notify when something opens.”
- “What’s on my watch list?”
- “Book Cote for 2025-02-01 at 19:00 for 2.”

## Project layout

```
backend/
├── app/
│   ├── main.py              # FastAPI + scheduler
│   ├── config.py            # Settings (Resy, OpenAI)
│   ├── agents/resy_agent.py # Resy booking agent
│   ├── toolsets/resy/       # list_nyc_hotspots, search_availability, book, watch list
│   ├── services/resy_client.py   # Resy API (find, book)
│   ├── services/watch_list_service.py
│   ├── data/nyc_hotspots.py # NYC venue list
│   ├── scheduler/hourly_resy.py  # Hourly watch list check
│   └── api/routes/          # chat, resy (watch)
├── alembic/
└── pyproject.toml
```
