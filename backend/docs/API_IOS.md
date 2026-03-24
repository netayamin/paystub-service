# API surface for the iOS app (Snag / DropFeed)

All paths are relative to the API origin (e.g. `https://your-host` or `http://127.0.0.1:8000`).  
The app uses the **`/chat`** prefix for product APIs.

FastAPI auto-generates API UIs when the server is running:

- **`GET /docs`** — Swagger UI (expand endpoints, “Try it out”, send requests)
- **`GET /redoc`** — ReDoc (single-page reference, often easier to scan)
- **`GET /openapi.json`** — raw schema (Postman, codegen, etc.)

---

## Health & meta

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/health` | Liveness, DB connectivity, discovery config |
| GET | `/` | JSON pointer to `/docs`, `/redoc`, `/health` |

---

## Auth (phone login)

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/chat/auth/request-code` | Send SMS OTP |
| POST | `/chat/auth/verify-code` | Exchange code for access token |
| POST | `/chat/auth/complete-profile` | Save name / email after verify |

---

## Discovery & feed (primary data)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/chat/watches/just-opened` | **Home / Feed:** live activity — slots that **opened** in the last ~10 minutes (`LIVE_FEED_WINDOW_MINUTES`); `still_open` is empty. Closures in that window appear in `just_missed`. |
| GET | `/chat/watches/drops` | **Explore:** full bookable inventory for given days — requires `dates=YYYY-MM-DD,...`; optional `party_sizes`, `market`. Returns `just_opened` + `still_open` day buckets (client merges like before). |
| GET | `/chat/watches/new-drops` | Lightweight “new since” list for alerts (uses full inventory window server-side). |

Query params on `just-opened`: optional `dates`, `party_sizes`, `_t` (cache-bust).  
Optional: `mobile`, `debug`, `market` (see OpenAPI).

Windows: `just_opened_inventory_minutes` (default 30) + `live_feed_window_minutes` (default 10) appear on **`GET /health`** under `discovery`.

---

## Saved venues & hotlist

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/chat/watches/hotlist` | Curated hotspot names per market |
| GET | `/chat/venue-watches` | Saved watches + excluded list |
| POST | `/chat/venue-watches` | Add watch |
| DELETE | `/chat/venue-watches/{watch_id}` | Remove watch |
| POST | `/chat/venue-watches/exclude` | Exclude from hotlist |
| DELETE | `/chat/venue-watches/exclude/{exclude_id}` | Remove exclusion |

---

## Follows / activity (Saved tab)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/chat/watches/follows/status` | Per-venue last-drop hints |
| GET | `/chat/watches/follows/activity` | Activity timeline |

Headers: `X-Recipient-Id` (optional; default recipient for dev).

---

## Push & analytics

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/chat/push/register` | Register APNs device token |
| POST | `/chat/notifications/behavior-events` | Batch product/analytics events |

---

## Removed from this repo (iOS-only backend)

The following are **not** exposed anymore (were web/debug/admin or unused by the app):

- Web React app under `frontend/` (removed).
- `/chat-ui` HTML test page.
- Discovery debug/test routes (`resy-test`, `discovery-health`, `feed-item-debug`, DB admin posts, etc.).

If you need operational tooling, use **`/docs`**, **`/health`**, logs, and direct DB access.
