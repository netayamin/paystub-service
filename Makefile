.PHONY: setup install dev dev-backend dev-all db-up db-down db-reset migrate migrate-metrics

setup: install
	cp backend/.env.example backend/.env
	@echo "Edit backend/.env if needed, then: make db-up && make migrate"

install:
	cd backend && poetry install
	cd frontend && npm install

# Run backend only (port 8000). You should see "BACKEND READY" in this terminal when it starts.
dev: dev-backend

# Expose backend via ngrok (use when phone is not on same WiFi).
# Run: make dev-backend (Terminal 1), then either:
#   make ngrok        — foreground; copy the https URL into Info.plist API_BASE_URL and rebuild iOS
#   make ngrok-ios    — start ngrok in background and set API_BASE_URL in Info.plist; then rebuild iOS
ngrok:
	@echo "Exposing backend on port 8000. Copy the https URL and set API_BASE_URL in Info.plist, then rebuild iOS."
	ngrok http 8000

# Start ngrok in background and set ios/DropFeed/Info.plist API_BASE_URL to the ngrok HTTPS URL. Then rebuild the app.
ngrok-ios:
	@chmod +x scripts/ngrok-ios.sh 2>/dev/null || true
	./scripts/ngrok-ios.sh

dev-backend:
	@echo "Starting backend on http://127.0.0.1:8000 (use http://YOUR_MAC_IP:8000 on device)..."
	cd backend && poetry run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Run backend + frontend with one command. Open http://localhost:5173 (Vite proxies /chat to 8000).
dev-all:
	cd frontend && npm run dev:all

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
