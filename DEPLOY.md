# Deploy / test on a phone (iOS + API)

The product is the **native iOS app** in `ios/` talking to the **FastAPI** backend. There is no web frontend in this repo.

## Quick test with ngrok (local Mac)

1. **Postgres**: `docker compose up -d db`
2. **Backend**: `make dev-backend` — wait for **BACKEND READY**.
3. **ngrok**: `ngrok http 8000` — copy the HTTPS URL.
4. **iOS**: set `API_BASE_URL` to that URL (see `ios/README.md`, `make ios-phone`, or Xcode inject). Rebuild/run on device.

## Hosted API (e.g. Railway, EC2, Render)

- Deploy the **`backend/`** service only (Poetry + `uvicorn app.main:app --host 0.0.0.0 --port $PORT`).
- Set **`DATABASE_URL`**, **`RESY_API_KEY`**, **`RESY_AUTH_TOKEN`**, and other vars from `backend/.env.example`.
- Point the iOS app’s **`API_BASE_URL`** at the public API origin (HTTPS recommended).

Optional: set **`CORS_ORIGINS`** in backend `.env` only if you still use browser tools hitting the API from another origin.

## API reference

- Interactive: **`GET /docs`** on the running server.
- Table of routes the app uses: **`backend/docs/API_IOS.md`**.
