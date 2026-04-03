# Backend local dev — when “nothing works”

**HTTP routes used by the iOS app:** see [`API_IOS.md`](./API_IOS.md) (also **GET /docs** when the server is running).

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

## `/health` won’t open in the browser

1. **Is the server running?** After `make dev-backend` you must see **`Uvicorn running on http://0.0.0.0:8000`** (or `127.0.0.1:8000`). If that terminal exited or shows a Python traceback, fix that first — the site only works while that process is alive.

2. **iPhone vs Mac:** `http://127.0.0.1:8000` means “this device.” On your **phone**, that’s the phone itself, not your Mac — it will fail. Use **Safari on the Mac** where uvicorn runs, or point the app at **your Mac’s LAN IP** or **EC2** (`ios/README.md`).

3. **Port in use / wrong app:** Check what holds 8000: `lsof -iTCP:8000 -sTCP:LISTEN`. You should see `Python`/`uvicorn`. If something else is there, stop it or change the port in `make dev-backend`.

4. **Quick test (Mac Terminal):**  
   `curl -s http://127.0.0.1:8000/health`  
   If this works but the browser doesn’t, try **`http://localhost:8000/health`** or disable VPN/proxy for localhost.

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
| **`[Errno 48] Address already in use`** (port 8000) | Something else is already bound to 8000 (often an old uvicorn). From repo root: **`make backend-kill-8000`** then **`make dev-backend`**. Or use another port: **`make dev-backend PORT=8001`** (and point `API_BASE_URL` at that port). |
| App starts but `/chat/...` errors | Open `/docs` and try `/health`. If DB is down, `/health` will show `database.connected: false`. |
| Discovery empty / no drops | Normal without Resy keys; set `RESY_API_KEY` and `RESY_AUTH_TOKEN` in `.env` for live scanning. |

## iPhone + Mac API

Backend must listen on **all interfaces** (already set in `make dev-backend`: `--host 0.0.0.0`). Set `API_BASE_URL` to `http://YOUR_MAC_LAN_IP:8000` for same-Wi‑Fi testing, or use your hosted API (e.g. EC2). See `ios/README.md`.
