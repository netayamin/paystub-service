# Backend HTTP port (override if 8000 is busy: make dev-backend PORT=8001)
PORT ?= 8000

.PHONY: setup install dev dev-backend db-up db-down db-reset migrate migrate-metrics ios-phone backend-doctor backend-kill-8000

setup: install
	cp backend/.env.example backend/.env
	@echo "Edit backend/.env if needed, then: make db-up && make migrate"

install:
	cd backend && poetry install

# Run backend only (port 8000). You should see "BACKEND READY" in this terminal when it starts.
dev: dev-backend

# Print steps for testing the iOS app on a real phone against your Mac (same Wi‑Fi).
ios-phone:
	@echo ""
	@echo "iPhone + Mac API (same Wi‑Fi)"
	@echo "-----------------------------"
	@echo "1) Set ios/DropFeed/Info.plist → API_BASE_URL to http://YOUR_MAC_LAN_IP:8000"
	@echo "2) Terminal (repo root):  make dev-backend   (listens on 0.0.0.0:8000)"
	@echo "3) Xcode: Product → Run on your iPhone"
	@echo "4) Optional: AUTH_OTP_FIXED=123456 in backend/.env for easy sign-in"
	@echo ""
	@echo "Production: point API_BASE_URL at your EC2 API (e.g. http://x.x.x.x:8000) — no Mac needed."
	@echo ""

# Quick checks: Postgres on 5432, DATABASE_URL, app import. Run if the backend won't start.
backend-doctor:
	@chmod +x scripts/backend-doctor.sh 2>/dev/null || true
	@./scripts/backend-doctor.sh

# Free port 8000 when uvicorn says "Address already in use" (kills whatever is listening there).
backend-kill-8000:
	@P=$$(lsof -tiTCP:8000 -sTCP:LISTEN 2>/dev/null); \
	if [ -n "$$P" ]; then echo "Killing PID(s) on port 8000: $$P"; kill -9 $$P; else echo "Nothing listening on port 8000."; fi

dev-backend:
	@echo "Starting backend on http://127.0.0.1:$(PORT) (use http://YOUR_MAC_IP:$(PORT) on device)..."
	cd backend && poetry run uvicorn app.main:app --reload --host 0.0.0.0 --port $(PORT)

db-up:
	docker compose up -d db

db-down:
	docker compose down

# Wipe DB and rebuild from migrations (no data kept). Requires db to be up.
db-reset:
	cd backend && poetry run alembic downgrade base && poetry run alembic upgrade head

migrate:
	cd backend && poetry run alembic upgrade head

# Run migrations then aggregate drop_events into venue_metrics, market_metrics, venue_rolling_metrics. Use this so drops show in metrics.
migrate-metrics: migrate
	cd backend && poetry run python scripts/run_aggregate_metrics.py

# Migrate schema to remote DB: set DATABASE_URL in backend/.env to your AWS RDS URL, then run this.
migrate-remote:
	cd backend && poetry run alembic upgrade head

# Copy local DB (schema + data) to remote. Set REMOTE_DATABASE_URL (RDS or EC2:5432 if exposed).
# Example: REMOTE_DATABASE_URL='postgresql://user:pass@xxx.rds.amazonaws.com:5432/paystub' make db-to-aws
db-to-aws:
	@chmod +x scripts/migrate-db-to-aws.sh 2>/dev/null || true
	./scripts/migrate-db-to-aws.sh

# Dump local DB and print instructions to copy + restore on EC2 (no need to expose 5432 on EC2).
sync-db-to-ec2:
	@chmod +x scripts/sync-local-db-to-ec2.sh 2>/dev/null || true
	./scripts/sync-local-db-to-ec2.sh
