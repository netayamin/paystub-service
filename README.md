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

## Development (backend + frontend)

Use **two terminals** so you can see the backend running and its logs:

**Terminal 1 — Backend** (you’ll see “BACKEND READY” when it’s up):

```bash
make dev-backend
```

**Terminal 2 — Frontend** (then open http://localhost:5173):

```bash
cd frontend && npm run dev
```

Or run both in one terminal (mixed logs): `make dev-all`.

## Database: clear and rebuild

To wipe all data and recreate the schema from migrations (no valuable data kept):

```bash
make db-reset   # requires: make db-up first so Postgres is running
```

Then restart the backend; discovery will run a fresh initial snapshot on startup.

## Database: migrate local to AWS

**Schema only** (empty RDS or EC2 DB, apply migrations):

1. Set `DATABASE_URL` in `backend/.env` to your DB URL (RDS or `postgresql://paystub:paystub@EC2_IP:5432/paystub` if EC2 exposes 5432).
2. Run: `make migrate`

**Schema + data — EC2 (recommended, no port exposure):**  
Copy your local DB into the Postgres container on EC2:

1. Local Postgres running: `make db-up`
2. Run: `make sync-db-to-ec2`  
   This dumps your local DB and prints exact steps: **scp** the dump to EC2, then **SSH** and run the **docker compose cp** + **pg_restore** commands it shows. Finally restart the backend on EC2.

**Schema + data — direct (RDS or EC2 with 5432 open):**

1. Keep local Postgres running (`make db-up`).
2. If using EC2: temporarily add `ports: - "5432:5432"` under the `db` service in `docker-compose.prod.yml` on EC2, open port 5432 in the EC2 security group, and restart: `docker compose -f docker-compose.prod.yml up -d`.
3. Run: `REMOTE_DATABASE_URL='postgresql://paystub:paystub@EC2_OR_RDS_HOST:5432/paystub' make db-to-aws`
4. Remove the `ports` line and close 5432 in the security group when done.

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
