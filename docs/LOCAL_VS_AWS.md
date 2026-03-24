# Local vs AWS — switch API and DB

> The web **frontend** was removed; this repo is **iOS + API**. Use `ios/DropFeed/Info.plist` → `API_BASE_URL`.

## What was changed for AWS

| File | Was | Now |
|------|-----|-----|
| `backend/.env` | `DATABASE_URL=...@localhost:5432/paystub` | `DATABASE_URL=...@database-1....rds.amazonaws.com:5432/postgres` (RDS) |
| `ios/DropFeed/Info.plist` | `API_BASE_URL` (local) | `API_BASE_URL=http://YOUR_EC2:8000` or ngrok HTTPS |

So: **backend** uses RDS; **iOS** calls the EC2 (or ngrok) API.

---

## If “not working” = app can’t reach the API

The EC2 API must be reachable:

1. **Open port 8000** on the EC2 security group (Inbound: Custom TCP 8000, Source as needed).
2. **Backend must be running** on EC2 (see your `docker-compose.prod.yml` or deploy docs).

---

## Use local backend again (local dev)

**1. Backend (local DB)**  
In `backend/.env` set:
```env
DATABASE_URL=postgresql://paystub:paystub@localhost:5432/paystub
```
Start local DB: `make db-up`. Then run backend: `make dev-backend`.

**2. iOS**  
In `ios/DropFeed/Info.plist` set `API_BASE_URL` to `http://127.0.0.1:8000` (simulator) or your Mac’s LAN IP / ngrok URL (device). Rebuild the app.

---

## Use AWS again (production)

- `backend/.env` on the server: `DATABASE_URL` = RDS URL.
- `ios/DropFeed/Info.plist`: production API origin. Rebuild iOS after changing it.

See also **`backend/docs/API_IOS.md`** for all HTTP paths the app uses.
