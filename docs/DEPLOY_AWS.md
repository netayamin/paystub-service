# Deploy backend to AWS (EC2 + RDS)

Run the **backend in Docker** on a single EC2 instance and use **Amazon RDS for PostgreSQL** for the database. Postgres does **not** run in Docker on the box (avoids RAM issues on t3.micro and keeps the instance stable).

**Your EC2 (this deployment):** `18.118.55.231` — API: **http://18.118.55.231:8000**

---

## Fix EC2 – API not working (step-by-step)

Do these in order. Stop when something fixes it.

### 1. Open port 8000 in the EC2 security group (most common)

If the browser or iOS app **times out** or says **connection refused** when opening `http://18.118.55.231:8000`:

1. In **AWS Console** → **EC2** → **Instances** → click your instance (`18.118.55.231`).
2. Open the **Security** tab → click the **Security group** link (e.g. `sg-xxxxx`).
3. **Edit inbound rules** → **Add rule**:
   - **Type:** Custom TCP
   - **Port range:** 8000
   - **Source:** 0.0.0.0/0 (or “Anywhere-IPv4”)
   - **Description:** Backend API (optional)
4. **Save rules**.

Then try again: `http://18.118.55.231:8000/health` (from browser or phone). You should get JSON like `{"status":"ok",...}`.

### 2. Check that the backend is running on EC2

SSH in and run:

```bash
ssh -i /path/to/your-key.pem ec2-user@18.118.55.231
cd ~/paystub-service
docker ps
curl -s http://localhost:8000/health
```

- **`curl` returns JSON:** Backend is fine on the server. If you still can’t reach it from outside, go back to **step 1** (security group).
- **`curl` hangs or fails:** Backend or DB issue. Run:

  ```bash
  docker compose -f docker-compose.prod.yml ps
  docker compose -f docker-compose.prod.yml logs --tail=80 backend
  ```

  (If your EC2 has the older CLI: `docker-compose -f docker-compose.prod.yml logs --tail=80 backend`.)

### 3. If the backend container is Exited or Restarting

- **Database connection errors in logs:** Set `DATABASE_URL` in `backend/.env` correctly. If you use **Postgres in Docker** on the same EC2 (e.g. `docker-compose.yml` with `db`), use the host so the backend can reach the DB:
  - In `backend/.env`:  
    `DATABASE_URL=postgresql://paystub:paystub@host.docker.internal:5432/paystub`
  - And in `docker-compose.prod.yml` the backend service should have `extra_hosts: - "host.docker.internal:host-gateway"` (it already does).
- **Out of memory:** Use a larger instance (e.g. t3.small).
- After editing `.env` or fixing config:

  ```bash
  cd ~/paystub-service
  docker compose -f docker-compose.prod.yml up -d --force-recreate backend
  curl -s http://localhost:8000/health
  ```

### 4. If you use RDS (Postgres not in Docker)

- **RDS security group** must allow **PostgreSQL (5432)** from **this EC2’s security group** (or EC2 private IP). Otherwise the backend cannot connect and requests hang or fail.
- `backend/.env` must have:  
  `DATABASE_URL=postgresql://USER:PASSWORD@your-rds-endpoint.region.rds.amazonaws.com:5432/DBNAME`

---

**If http://18.118.55.231:8000/health does nothing (timeout, connection refused, or blank):**

1. **EC2 security group** — Inbound: add **Custom TCP, port 8000**, Source **0.0.0.0/0** (and keep **SSH 22**).
2. **RDS security group** — Inbound: add **PostgreSQL, port 5432**, Source = **this EC2’s security group** (e.g. `sg-xxx` for the instance). Without this, the backend cannot connect to the database and requests hang or fail.

**Backend doesn’t return a reply (timeout / no response):** Run these on EC2 to narrow it down:

```bash
cd ~/paystub-service
sudo docker-compose -f docker-compose.prod.yml ps
curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:8000/health
sudo docker-compose -f docker-compose.prod.yml logs --tail 80 backend
```

- If **container is not running** or **Exited**: check logs for crashes (e.g. `DATABASE_URL`, RDS unreachable). Restart: `sudo docker-compose -f docker-compose.prod.yml up -d --force-recreate backend`.
- If **curl to localhost:8000/health** returns `200` from EC2 but the app/iOS from outside gets no reply: **EC2 security group** — open **Custom TCP 8000** from `0.0.0.0/0`.
- If **curl to localhost:8000/health** hangs or fails: backend or DB issue. Check logs; ensure RDS security group allows EC2 on 5432 and `backend/.env` has the correct `DATABASE_URL`.
- If **/health** works but **/chat/watches/just-opened** never returns: that endpoint can be slow under load (many buckets). On a small instance, consider t3.small or increasing client timeout in the app.

---

## Stale feed / no live updates (same results every time)

If the app or API keeps returning the same just-opened results and never seems to update:

1. **Run the discovery diagnostic** (on EC2 after SSH, or from your Mac with your EC2 IP):
   ```bash
   cd ~/paystub-service
   bash scripts/ec2-diagnose-discovery.sh
   ```
   From Mac (replace with your EC2 IP):
   ```bash
   BASE_URL=http://18.118.55.231:8000 bash scripts/ec2-diagnose-discovery.sh
   ```
   This prints: health, **last_scan_at**, **feed_updating**, job_alive, stale buckets, and compares snapshot vs DB (debug=1).

2. **Interpret the output:**
   - **last_scan_at is missing or very old:** The discovery job is not updating the DB (scheduler not running, or every bucket is failing). Check backend logs (step 3).
   - **feed_updating is false:** Scans are not completing within the last 10 minutes — either the job isn’t running or Resy/DB is slow or failing.
   - **stale_bucket_count > 0:** Some buckets haven’t been scanned in 4+ hours; feed excludes them. Usually means the job crashed or Resy credentials are wrong.
   - **Snapshot and debug=1 counts both 0:** DB has no just-opened data. Either discovery never ran successfully (e.g. no RESY_API_KEY / RESY_AUTH_TOKEN in `backend/.env` on EC2), or Resy is returning no availability for the polled dates.

3. **Check backend logs on EC2:**
   ```bash
   docker compose -f docker-compose.prod.yml logs --tail=150 backend
   ```
   Look for: `Discovery bucket job tick`, `Snapshot rebuild failed`, Resy/HTTP errors, or `DATABASE_URL`/connection errors. If the job runs every ~5s you should see periodic discovery activity; if not, the scheduler may not have started.

4. **Confirm env on EC2:** Backend must have Resy and DB set:
   ```bash
   grep -E '^DATABASE_URL|^RESY_' backend/.env | sed 's/=.*/=***/'
   ```
   If any are missing, add them and restart: `docker compose -f docker-compose.prod.yml up -d --force-recreate backend`.

5. **Optional – force fresh data for one request:** Call the API with `?debug=1` to bypass the in-memory snapshot and read from the DB. If debug=1 returns different/newer data than without, the snapshot isn’t being rebuilt (e.g. job not finishing buckets); if both are the same and old, the DB isn’t being updated (discovery job or Resy issue).

---

## How deploy works (quick reference)

- **What “deploy” does:** Updates the code on EC2, rebuilds the backend Docker image, runs DB migrations, and restarts the backend container so the API serves the latest version.
- **Two ways to deploy:**
  1. **From your Mac:** `EC2_KEY=/path/to/your.pem ./scripts/deploy-to-ec2.sh` — SSHs into EC2 and runs the deploy steps there.
  2. **GitHub Actions:** Push to `main` (or run “Deploy to AWS” from the Actions tab). The workflow SSHs to EC2 and runs the same steps. Requires repo secrets: `EC2_HOST`, `EC2_SSH_KEY`.
- **Check what’s running:** `GET http://YOUR_EC2_IP:8000/health` returns `{"status":"ok","version":"abc123"}` — the version is the git short commit so you can confirm the deploy.
- **"No space left on device" during build:** SSH into EC2 and run `cd ~/paystub-service && bash scripts/ec2-free-disk.sh` (stops backend, prunes Docker + build cache, shows disk). Then run the deploy again from your Mac. The deploy script also prunes before each build; if the instance is very small (e.g. 8 GB), consider increasing the root volume in AWS (e.g. to 12–16 GB).

---

## Architecture

- **EC2**: runs only the backend container (uvicorn). Use **t3.small** (2 GB). t3.micro (1 GB) will OOM under discovery load.
- **RDS PostgreSQL**: managed database in the same region/VPC. EC2 connects via `DATABASE_URL`.

---

## Do it in 4 steps

### Step 1 – Create RDS PostgreSQL (AWS Console)

1. Go to **RDS** → **Create database**.
2. **Engine**: PostgreSQL 15 (or 16).
3. **Templates**: Free tier (or Dev/Test) if available; otherwise “Dev/Test” for low cost.
4. **DB instance identifier**: e.g. `paystub-db`.
5. **Master username**: e.g. `paystub` (or keep `postgres`).
6. **Master password**: set a strong password and save it.
7. **Instance configuration**: e.g. **db.t3.micro** (or db.t4g.micro) for minimal cost.
8. **Storage**: 20 GB gp3 is fine.
9. **Connectivity**:
   - **VPC**: use the **same VPC** as your EC2 instance (you’ll create EC2 in Step 2, or create RDS in default VPC and launch EC2 in the same VPC).
   - **Public access**: **Yes** only if you need to run migrations from your Mac. Otherwise **No** and run migrations from EC2.
   - **VPC security group**: create new. We’ll add a rule to allow **PostgreSQL (5432)** from the EC2 security group or from the EC2 private IP.
10. Create the database. Note the **Endpoint** (e.g. `paystub-db.xxxxx.us-east-2.rds.amazonaws.com`).

**Create a database and user** (if you didn’t use `paystub` as master user):

- Connect to RDS (e.g. from EC2 or with “Public access” from your machine) and run:
  - `CREATE DATABASE paystub;`
  - If needed: `CREATE USER paystub WITH PASSWORD '...'; GRANT ALL ON DATABASE paystub TO paystub;`
- Or use the master user and create only the database: `CREATE DATABASE paystub;` then use URL `postgresql://masteruser:masterpass@endpoint:5432/paystub`.

**Security group (RDS):** Inbound rule: Type **PostgreSQL**, Port **5432**, Source = EC2’s security group ID or EC2 private IP/32 (e.g. `10.0.1.50/32`). This limits access to your app server only.

---

### Step 2 – Launch EC2 (in AWS Console)

1. **EC2** → **Launch instance**.
2. **Name:** `paystub-backend`.
3. **AMI:** Amazon Linux 2023.
4. **Instance type:** **t3.small** (2 GB). t3.micro (1 GB) will OOM with discovery polling.
5. **Key pair:** Create or select; download the `.pem` file.
6. **Network:** Same VPC as RDS. **Security group:** allow **SSH (22)** and **Custom TCP 8000** (source: 0.0.0.0/0 for testing; restrict later).
7. **Storage:** 8 GB.
8. Launch.

---

### Step 3 – Set DATABASE_URL and secrets on your machine (before first deploy)

On your Mac, in the repo:

```bash
cd paystub-service
cp backend/.env.example backend/.env
```

Edit `backend/.env` and set:

- **DATABASE_URL**: your RDS URL, e.g.  
  `postgresql://paystub:YOUR_RDS_PASSWORD@paystub-db.xxxxx.us-east-2.rds.amazonaws.com:5432/paystub`
- **OPENAI_API_KEY**, **RESY_API_KEY**, **RESY_AUTH_TOKEN** (and any other secrets you use).

You’ll copy this file to EC2 or paste its contents there so the backend container can use it.

---

### Step 4 – Deploy on EC2 (one command from your Mac)

From your Mac (replace key path with yours):

```bash
ssh -i /path/to/your-key.pem ec2-user@3.142.49.156
```

On the EC2 instance, run:

```bash
git clone https://github.com/netayamin/paystub-service.git && cd paystub-service && bash scripts/ec2-bootstrap.sh
```

Before or right after the first run, put your real `backend/.env` on the server (with **DATABASE_URL** pointing at RDS and all secrets). For example, from your Mac:

```bash
scp -i /path/to/your-key.pem backend/.env ec2-user@3.142.49.156:~/paystub-service/backend/.env
```

Or on EC2:

```bash
nano backend/.env
# Paste DATABASE_URL=postgresql://...@your-rds-endpoint:5432/paystub
# and OPENAI_API_KEY=..., RESY_API_KEY=..., RESY_AUTH_TOKEN=...
```

Then run migrations (once) and restart the backend:

```bash
cd ~/paystub-service
sudo docker compose -f docker-compose.prod.yml run --rm backend alembic upgrade head
sudo docker compose -f docker-compose.prod.yml up -d
```

Your API will be at **http://3.142.49.156:8000**. Use that as the base URL in the iOS app.

---

## Summary checklist

| Step | What |
|------|------|
| 1 | Create RDS PostgreSQL (same VPC as EC2), note endpoint, allow 5432 from EC2 SG. |
| 2 | Launch EC2 (same VPC), open SSH (22) and 8000. |
| 3 | Set `backend/.env` with `DATABASE_URL` (RDS), OPENAI_API_KEY, RESY_*. |
| 4 | On EC2: clone repo, run `scripts/ec2-bootstrap.sh`, copy/paste `.env`, run migrations, `docker compose -f docker-compose.prod.yml up -d`. |

---

## Backend not running on EC2 (start / restart)

If the API at `http://<EC2_IP>:8000` doesn’t respond or the backend isn’t running:

1. **SSH into EC2** (use your key and public IP, e.g. `3.19.238.117` or your current instance):

   ```bash
   ssh -i /path/to/your-key.pem ec2-user@YOUR_EC2_PUBLIC_IP
   ```

2. **Go to the repo** (if you already cloned it):

   ```bash
   cd ~/paystub-service
   ```

   If the repo isn’t there, clone and bootstrap first:

   ```bash
   git clone https://github.com/netayamin/paystub-service.git && cd paystub-service && bash scripts/ec2-bootstrap.sh
   ```

3. **Ensure `backend/.env` has RDS and secrets** (DATABASE_URL, RESY_*, etc.). From your Mac you can copy it:

   ```bash
   scp -i /path/to/your-key.pem backend/.env ec2-user@YOUR_EC2_PUBLIC_IP:~/paystub-service/backend/.env
   ```

   Or on EC2: `nano backend/.env` and set `DATABASE_URL=postgresql://postgres:PASSWORD@database-2.xxxxx.rds.amazonaws.com:5432/postgres`.

4. **Start or restart the backend** (from EC2, in `~/paystub-service`):

   ```bash
   sudo docker compose -f docker-compose.prod.yml up -d --build
   ```

   To only restart (no rebuild):

   ```bash
   sudo docker compose -f docker-compose.prod.yml restart backend
   ```

5. **Check it’s running**:

   ```bash
   sudo docker compose -f docker-compose.prod.yml ps
   curl -s http://localhost:8000/health
   ```

   From your browser: `http://YOUR_EC2_PUBLIC_IP:8000/health`

6. **If it exits or fails (or status is "Restarting")**, check logs:

   ```bash
   # Use docker-compose (hyphen) if your EC2 has the older Docker CLI
   sudo docker-compose -f docker-compose.prod.yml logs --tail=100 backend
   ```

   Common causes: wrong or missing `DATABASE_URL`, RDS security group not allowing EC2 (port 5432 from EC2’s security group), or out-of-memory on t3.micro (try t3.small).

---

## Backend in restart loop ("Restarting (1)")

If `docker-compose -f docker-compose.prod.yml ps` shows the backend as **Restarting**:

1. **See why it’s crashing** (on EC2):

   ```bash
   cd ~/paystub-service
   sudo docker-compose -f docker-compose.prod.yml logs --tail=80 backend
   ```

   (If that fails, use: `sudo docker logs paystub-service-backend-1 --tail 80`)

2. **Typical fixes:**

   - **Database unreachable** (connection refused / timeout):  
     - If you use **RDS**: set `DATABASE_URL` in `backend/.env` to your RDS URL and ensure the RDS security group allows inbound 5432 from this EC2’s security group.  
     - If you use the **Postgres container** on the same EC2 (e.g. from `docker-compose.yml`): from the backend container, `localhost` is the container itself, not the host. Use the host’s IP so the backend can reach the db container:
       - Add to `docker-compose.prod.yml` under `backend:`:
         ```yaml
         extra_hosts:
           - "host.docker.internal:host-gateway"
         ```
         Then in `backend/.env`:  
         `DATABASE_URL=postgresql://paystub:paystub@host.docker.internal:5432/paystub`
       - Or use the EC2 private IP (e.g. `172.31.16.12`) in `DATABASE_URL` instead of `host.docker.internal` if your Docker doesn’t support `host-gateway`.
   - **Missing or invalid env**: ensure `backend/.env` has all required vars (e.g. `DATABASE_URL`, Resy keys if used).
   - **Out of memory**: use a larger instance (e.g. t3.small).

3. **Restart after editing**:

   ```bash
   sudo docker-compose -f docker-compose.prod.yml up -d --force-recreate backend
   curl -s http://localhost:8000/health
   ```

---

## Running migrations

- **Schema migrations (Alembic)** — from your Mac if RDS is reachable, or on EC2 (lightweight):

  **From your Mac** (RDS has public access and your IP allowed on port 5432):

  ```bash
  cd paystub-service
  REMOTE_DATABASE_URL='postgresql://paystub:pass@your-rds-endpoint:5432/paystub' make db-to-aws
  ```

  **On EC2** (if RDS is private):

  ```bash
  cd ~/paystub-service
  sudo docker compose -f docker-compose.prod.yml run --rm backend alembic upgrade head
  ```

- **Empty iOS feed but `/health` is ok:** `/health` only checks that Postgres accepts a connection. If **`/explore/drops`** returns an error like `relation "discovery_buckets" does not exist`, Alembic never created discovery tables on that database — run the command above and confirm it exits **0**. The GitHub deploy workflow runs the same migration step; if it failed in the past, fix `DATABASE_URL` in `backend/.env` on EC2 and re-run migrations.

---

## Copying local DB data to RDS (full dump/restore)

If you need to **copy all data** from your local Postgres to RDS (e.g. first-time seed or sync), run the restore **from your Mac**, not from EC2.

**Why EC2 crashes:** The EC2 instance is a **t3.micro (1 GB RAM)**. Running `pg_restore` on EC2 (e.g. after SCPing the dump and using a Docker container to restore to RDS) is very memory- and CPU-heavy. Together with the backend container, the instance can run out of memory and crash or become unresponsive.

**Do this instead:**

1. **Install PostgreSQL client tools on your Mac** (if you don’t have them):
   ```bash
   brew install libpq
   echo 'export PATH="/opt/homebrew/opt/libpq/bin:$PATH"' >> ~/.zshrc
   source ~/.zshrc
   ```

2. **Allow your Mac to reach RDS** (temporarily): In AWS RDS → your DB → Connectivity, set **Public access** to Yes. In the RDS **security group**, add an inbound rule: PostgreSQL, port 5432, Source = your IP (or 0.0.0.0/0 only for the migration). Remove or restrict after the restore.

3. **Run the migration script from your Mac** (dump + restore both run locally; EC2 is not involved):
   ```bash
   cd paystub-service
   REMOTE_DATABASE_URL='postgresql://paystub:YOUR_RDS_PASSWORD@your-rds-endpoint.region.rds.amazonaws.com:5432/paystub' ./scripts/migrate-db-to-aws.sh
   ```

4. **(Optional)** Run Alembic on the remote DB to ensure schema is current:
   ```bash
   cd backend && DATABASE_URL='postgresql://...' poetry run alembic upgrade head
   ```

5. Lock RDS back down: set Public access to No and/or remove your IP from the security group if you no longer need direct access.

---

## Auto-deploy on push (GitHub Actions)

1. In GitHub: **Settings** → **Secrets and variables** → **Actions** → add:
   - **EC2_HOST** – EC2 public IP.
   - **EC2_SSH_KEY** – full contents of your `.pem` file.

2. On EC2, ensure the repo is cloned in `~/paystub-service` and `git pull` works (for private repos, use a deploy key or HTTPS token).

3. Push to `main` – the workflow SSHs in, runs `git pull` and `docker compose -f docker-compose.prod.yml up -d --build`.

You can also run the workflow manually: **Actions** → **Deploy to AWS** → **Run workflow**.

### Deploy fails: `docker build` — Docker Hub timeout (`registry-1.docker.io` i/o timeout)

The build on EC2 runs `docker build`, which must pull the base image over **HTTPS (443)**. A timeout to `registry-1.docker.io` means the instance cannot complete that request in time (blocked outbound, no NAT in a private subnet, or Docker Hub congestion).

**Checks (on EC2 after SSH):**

```bash
curl -sI --max-time 15 https://registry-1.docker.io/v2/
curl -sI --max-time 15 https://public.ecr.aws/v2/
```

- If **both** time out: fix **outbound** access — security group allows egress (default “All traffic” to `0.0.0.0/0` is fine), and if the instance is in a **private** subnet, attach a **NAT Gateway** (or use a public subnet with a public IP for this box).
- If Docker Hub fails but **public.ecr.aws** works: the **Dockerfile** in this repo uses `FROM public.ecr.aws/docker/library/python:3.11-slim` so the first pull does not depend on Docker Hub. Re-run the workflow after pulling that image once:  
  `sudo docker pull public.ecr.aws/docker/library/python:3.11-slim`

**Quick retry:** Sometimes the failure is transient — re-run the failed job in **Actions**.

---

## Security (recommended)

- Prefer **HTTPS**: put Cloudflare in front, or nginx + Let’s Encrypt on the same EC2.
- Restrict **Security groups**: allow 8000 (or 80/443) only from your IP or Cloudflare; allow 5432 only from EC2.
- Keep **backend/.env** out of Git; create it only on the server.

---

## Cost (with credits)

- **EC2** t3.micro: free tier 750 h/month for 12 months; then a few $/month.
- **RDS** db.t3.micro: often free tier for 12 months (750 hours); then low cost.
- With **$100 credits**, one small EC2 + small RDS should stay within credit for a long time.

Set a **billing alert** in AWS (e.g. when forecast > $5) to avoid surprises.
