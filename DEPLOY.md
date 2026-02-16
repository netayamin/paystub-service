# Deploy for mobile testing

Deploy the **backend** (API + Postgres) and **frontend** (React) so you can open the app on your phone.

---

## Quick test with ngrok (no deploy) — full app (frontend + backend)

You only need **one** ngrok tunnel. The frontend (Vite) proxies `/chat` and `/resy` to your local backend, so all traffic from your phone goes through the same URL.

1. **Postgres**: `docker compose up -d db`
2. **Backend** (terminal 1): `make dev-backend` — wait until you see "BACKEND READY".
3. **Frontend** (terminal 2): `cd frontend && npm run dev` — wait until Vite is ready.
4. **ngrok** (terminal 3): `ngrok http 5173` — copy the HTTPS URL (e.g. `https://xxxx.ngrok-free.app`).
5. On your phone, open that URL (tap "Visit Site" on the ngrok interstitial if it appears).

The app and API will both work: the browser sends requests to the ngrok URL, Vite receives them and proxies `/chat` and `/resy` to the backend on port 8000. No second tunnel or env vars needed.

---

## 1. Backend on Railway (API + Postgres)

1. Go to [railway.app](https://railway.app) and sign in (e.g. GitHub).
2. **New Project** → **Deploy from GitHub** → select this repo.
3. **Add PostgreSQL**: in the project, click **+ New** → **Database** → **PostgreSQL**. Railway will set `DATABASE_URL` for you.
4. **Configure the backend service**:
   - **Root Directory**: `backend`
   - **Build Command**: `pip install poetry && poetry config virtualenvs.create false && poetry install --no-interaction --no-ansi`
   - **Start Command**: `poetry run uvicorn app.main:app --host 0.0.0.0 --port $PORT`
   - **Variables**: Railway injects `DATABASE_URL` from Postgres. Add any secrets you use locally (e.g. `RESY_API_KEY`, `RESY_AUTH_TOKEN`) from `backend/.env`.
5. **Settings** → **Networking** → **Generate Domain**. Copy the URL (e.g. `https://paystub-service-production-xxxx.up.railway.app`). This is your **backend URL**.
6. **Variables** → add:
   - `CORS_ORIGINS` = your frontend URL (you’ll set this after deploying the frontend, e.g. `https://your-app.vercel.app`).

## 2. Frontend on Vercel

1. Go to [vercel.com](https://vercel.com) and sign in (e.g. GitHub).
2. **Add New** → **Project** → import this repo.
3. **Configure**:
   - **Root Directory**: `frontend` (click **Edit** and set to `frontend`).
   - **Build Command**: `npm ci && npm run build`
   - **Output Directory**: `dist`
   - **Environment Variable**:
     - Name: `VITE_API_URL`
     - Value: your **backend URL** from Railway (no trailing slash), e.g. `https://paystub-service-production-xxxx.up.railway.app`
4. Deploy. Vercel will give you a URL like `https://paystub-resy-chat-xxx.vercel.app`. That’s your **frontend URL**.
5. In **Railway** → backend service → **Variables** → set `CORS_ORIGINS` to that frontend URL (e.g. `https://paystub-resy-chat-xxx.vercel.app`). Redeploy the backend if needed so CORS picks it up.

## 3. Test on your phone

Open the **frontend URL** (Vercel) in your phone’s browser. The app will call the Railway backend; discovery and Resy features will work if you’ve set `RESY_API_KEY` and `RESY_AUTH_TOKEN` on Railway.

---

## Alternatives

- **Render**: Use a **Web Service** for the backend (same build/start as above, connect a Render Postgres). Use a **Static Site** for the frontend; set **Build Command** to `npm run build`, **Publish Directory** to `dist`, and add `VITE_API_URL` to the frontend’s environment. Add the frontend URL to backend **Environment** as `CORS_ORIGINS`.
- **Single-server deploy**: You can instead build the frontend (`cd frontend && npm run build`), serve the `dist` folder from the FastAPI app, and deploy only the backend (with static files mounted). That requires adding static-file serving and a catch-all route in `main.py`; the split deploy above is usually simpler for “test on my phone” and keeps frontend/backend separate.
