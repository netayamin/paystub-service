# API surface for the iOS app (Snag / DropFeed)

All paths are relative to the API origin (e.g. `https://your-host` or `http://127.0.0.1:8000`).

FastAPI auto-generates API UIs when the server is running:

- **`GET /docs`** — Swagger UI (expand endpoints, "Try it out", send requests)
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
| POST | `/auth/request-code` | Send SMS OTP |
| POST | `/auth/verify-code` | Exchange OTP for access token |
| POST | `/auth/complete-profile` | Save name / email after verify |

---

## Feed — live activity (Home tab)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/feed/live` | Slots that **opened** in the last ~10 min (`LIVE_FEED_WINDOW_MINUTES`); `still_open` is always empty here |
| GET | `/feed/new-drops` | Lightweight "new since" list used by push alerts |
| GET | `/feed/follows/status` | Per-venue last-drop hints (Saved tab) |
| GET | `/feed/follows/activity` | Activity timeline (Saved tab) |

Query params on `/feed/live`: optional `party_sizes`, `mobile`, `debug`, `_t` (cache-bust). No date filter — it's always the live 10-minute window.

Windows: `live_feed_window_minutes` (default 10) and `just_opened_inventory_minutes` (default 30) appear on **`GET /health`** under `discovery`.

---

## Explore — full calendar inventory

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/explore/drops` | All bookable inventory for given days — requires `dates=YYYY-MM-DD,...`; optional `party_sizes`. Returns `just_opened` + `still_open` day buckets. |

---

## Watches — saved venues

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/watches` | Saved watches + excluded list |
| POST | `/watches` | Add a venue watch |
| DELETE | `/watches/{watch_id}` | Remove a watch |
| POST | `/watches/exclude` | Exclude a venue from push notifications |
| DELETE | `/watches/exclude/{exclude_id}` | Remove an exclusion |

Headers: `X-Recipient-Id` (optional; defaults to `default` for dev).

---

## Push & analytics

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/push/register` | Register APNs device token |
| POST | `/events/behavior` | Batch product / analytics events |

---

## Operations (not used by the iOS app)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/discovery/health` | Discovery job heartbeat, `feed_updating`, per-bucket `baseline_count`, `stale`, `stale_bucket_count` |
| GET | `/discovery/baseline` | Per-bucket baseline counts; add `?include_slot_ids=1` for full hash lists (huge) |

Legacy aliases (same handlers): **`GET /chat/watches/discovery-health`**, **`GET /chat/watches/baseline`**.

Other removed surfaces: web `frontend/`, `/chat-ui`, `resy-test`, `feed-item-debug`, DB admin posts, etc.
