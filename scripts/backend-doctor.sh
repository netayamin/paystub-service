#!/usr/bin/env bash
# Quick checks: Postgres port, DB session, app import. Run from repo root: ./scripts/backend-doctor.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== 1. Port 5432 (PostgreSQL) =="
if command -v nc >/dev/null 2>&1; then
  if nc -z localhost 5432 2>/dev/null; then
    echo "    OK: something is listening on localhost:5432"
  else
    echo "    FAIL: nothing on localhost:5432"
    echo "    Fix:  docker compose up -d db   (from repo root)"
    exit 1
  fi
else
  echo "    SKIP: nc not installed; check Postgres yourself"
fi

echo "== 2. Backend DB connection =="
cd "$ROOT/backend"
if ! poetry run python -c "
from sqlalchemy import text
from app.db.session import SessionLocal
db = SessionLocal()
try:
    db.execute(text('SELECT 1'))
    print('    OK: DATABASE_URL connects')
finally:
    db.close()
" 2>&1; then
  echo "    Fix: copy backend/.env.example to backend/.env, run docker compose up -d db, then:"
  echo "          cd backend && poetry run alembic upgrade head"
  exit 1
fi

echo "== 3. App import =="
if poetry run python -c "from app.main import app; print('    OK:', app.title)" 2>&1; then
  :
else
  exit 1
fi

echo ""
echo "All checks passed. Start the server:"
echo "  make dev-backend"
echo "Then: curl -s http://127.0.0.1:8000/health | python3 -m json.tool"
