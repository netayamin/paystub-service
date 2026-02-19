# Local vs AWS — switch API and DB

## What was changed for AWS

| File | Was | Now |
|------|-----|-----|
| `backend/.env` | `DATABASE_URL=...@localhost:5432/paystub` | `DATABASE_URL=...@database-1....rds.amazonaws.com:5432/postgres` (RDS) |
| `frontend/.env` | `VITE_API_URL=http://localhost:8000` | `VITE_API_URL=http://3.142.49.156:8000` (EC2) |
| `ios/DropFeed/Info.plist` | `API_BASE_URL` (old IP) | `API_BASE_URL=http://3.142.49.156:8000` (EC2) |

So: **backend** uses RDS; **frontend and iOS** call the EC2 API.

---

## If “not working” = app can’t reach the API

The EC2 API must be reachable:

1. **Open port 8000** on the EC2 security group (Inbound: Custom TCP 8000, Source 0.0.0.0/0).
2. **Backend must be running** on EC2:
   ```bash
   ssh -i ~/Downloads/dropfeed.pem ec2-user@3.142.49.156 "cd paystub-service && sudo docker compose -f docker-compose.prod.yml ps"
   ```
   If the backend container is not running:
   ```bash
   ssh ... "cd paystub-service && sudo docker compose -f docker-compose.prod.yml up -d"
   ```

---

## Use local backend again (local dev)

Point frontend and iOS at your Mac, and backend at local Postgres:

**1. Backend (local DB)**  
In `backend/.env` set:
```env
DATABASE_URL=postgresql://paystub:paystub@localhost:5432/paystub
```
Start local DB: `make db-up`. Then run backend: `make dev-backend`.

**2. Frontend**  
In `frontend/.env` set:
```env
VITE_API_URL=http://localhost:8000
```

**3. iOS**  
In `ios/DropFeed/Info.plist` set:
```xml
<key>API_BASE_URL</key>
<string>http://127.0.0.1:8000</string>
```
(Use your Mac’s LAN IP if testing on a device, e.g. `http://192.168.1.x:8000`.)  
Then rebuild the app.

---

## Use AWS again (production)

- `backend/.env`: `DATABASE_URL` = your RDS URL (for running backend locally against RDS) or leave as-is if you only run backend on EC2.
- `frontend/.env`: `VITE_API_URL=http://3.142.49.156:8000`
- `ios/DropFeed/Info.plist`: `API_BASE_URL=http://3.142.49.156:8000`  
Rebuild iOS after changing Info.plist.
