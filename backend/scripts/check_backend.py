#!/usr/bin/env python3
"""
Quick checks so the backend can start. Run from repo root or backend/:
  poetry run python scripts/check_backend.py
  # or from repo root:
  cd backend && poetry run python scripts/check_backend.py
"""
import os
import sys
from pathlib import Path

# Run from backend/
backend_dir = Path(__file__).resolve().parent.parent
os.chdir(backend_dir)
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

def main():
    errors = []

    # 1) .env
    env_file = backend_dir / ".env"
    if not env_file.exists():
        errors.append("backend/.env missing. Copy from backend/.env.example and set DATABASE_URL, etc.")
    else:
        print("OK  .env exists")

    # 2) DB connection (optional but common failure)
    try:
        from app.config import settings
        from sqlalchemy import text
        from app.db.session import engine
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        print("OK  Database connection (DATABASE_URL)")
    except Exception as e:
        errors.append(f"Database: {e}")
        print("FAIL Database:", e)

    # 3) App import (catches missing deps, bad imports)
    try:
        from app.main import app
        print("OK  App import (app.main)")
    except Exception as e:
        errors.append(f"App import: {e}")
        print("FAIL App import:", e)
        if errors:
            print("\nFix the above, then run:")
            print("  make dev-backend   # from repo root")
            print("  # or: cd backend && poetry run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000")
        return 1

    # 4) Port 8000
    try:
        import socket
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind(("127.0.0.1", 8000))
        print("OK  Port 8000 is free")
    except OSError:
        errors.append("Port 8000 is in use. Stop the other process or use another port (e.g. --port 8001).")
        print("FAIL Port 8000 is in use")

    if errors:
        print("\n---")
        for e in errors:
            print("•", e)
        print("\nThen start backend: make dev-backend  (from repo root)")
        return 1

    print("\nAll checks passed. Start with: make dev-backend")
    return 0

if __name__ == "__main__":
    sys.exit(main())
