# Deploy / test on a phone (iOS + API)

The product is the **native iOS app** in `ios/` talking to the **FastAPI** backend. There is no web frontend in this repo.

## Quick test on a physical iPhone (local Mac)

1. **Postgres**: `docker compose up -d db`
2. **Backend**: `make dev-backend` — wait for **BACKEND READY** (listens on `0.0.0.0:8000`).
3. **iOS**: set `ios/DropFeed/Info.plist` → `API_BASE_URL` to `http://YOUR_MAC_LAN_IP:8000` (same Wi‑Fi as the phone). Rebuild/run on device. See `make ios-phone`.

## Hosted API (e.g. Railway, EC2, Render)

- Deploy the **`backend/`** service only (Poetry + `uvicorn app.main:app --host 0.0.0.0 --port $PORT`).
- Set **`DATABASE_URL`**, **`RESY_API_KEY`**, **`RESY_AUTH_TOKEN`**, and other vars from `backend/.env.example`.
- Point the iOS app’s **`API_BASE_URL`** at the public API origin (HTTPS recommended).

Optional: set **`CORS_ORIGINS`** in backend `.env` only if you still use browser tools hitting the API from another origin.

## API reference

- Interactive: **`GET /docs`** on the running server.
- Table of routes the app uses: **`backend/docs/API_IOS.md`**.
