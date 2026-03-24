# Backend local dev — when “nothing works”

## Minimal flow (Mac)

1. **Postgres running** on `localhost:5432` with DB `paystub` / user `paystub` / password `paystub`:

   ```bash
   # From repo root
   docker compose up -d db
   ```

   Wait until healthy (`docker compose ps`). If port 5432 is already in use, stop the other Postgres or change `DATABASE_URL` in `backend/.env`.

2. **Env file**

   ```bash
   cp backend/.env.example backend/.env
   # Edit backend/.env only if your DB URL differs
   ```

3. **Dependencies + schema**

   ```bash
   cd backend && poetry install
   poetry run alembic upgrade head
   ```

4. **Start API**

   ```bash
   # From repo root
   make dev-backend
   ```

   You should see **`BACKEND READY`** and `http://127.0.0.1:8000` in the terminal.

5. **Sanity check**

   ```bash
   curl -s http://127.0.0.1:8000/health | python3 -m json.tool
   ```

   `status` should be `ok` and `database.connected` should be `true`.

## Repo helper

From **repo root**:

```bash
make backend-doctor
```

This checks port 5432, DB connectivity, and that the app imports.

## Typical errors

| Symptom | Fix |
|--------|-----|
| `Connection refused` / `could not connect to server` (5432) | Run `docker compose up -d db` (or start your Postgres). |
| `password authentication failed` / `database "paystub" does not exist` | Match `DATABASE_URL` in `backend/.env` to your Postgres user/db, or use the compose defaults. |
| `alembic.util.exc.CommandError` / missing tables | Run `cd backend && poetry run alembic upgrade head`. |
| `Address already in use` on 8000 | Stop the other process: `lsof -i :8000` then kill it, or use another port: `uvicorn app.main:app --host 0.0.0.0 --port 8001`. |
| App starts but `/chat/...` errors | Open `/docs` and try `/health`. If DB is down, `/health` will show `database.connected: false`. |
| Discovery empty / no drops | Normal without Resy keys; set `RESY_API_KEY` and `RESY_AUTH_TOKEN` in `.env` for live scanning. |

## iPhone + ngrok

Backend must listen on **all interfaces** (already set in `make dev-backend`: `--host 0.0.0.0`). Then ngrok: `ngrok http 8000`. See `ios/README.md`.
