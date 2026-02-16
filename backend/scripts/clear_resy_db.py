#!/usr/bin/env python3
"""Clear all Resy / watchlist / chat data and remind to restart backend for a fully fresh scheduler.
Run from backend: poetry run python scripts/clear_resy_db.py
Or: python -m backend.scripts.clear_resy_db (from repo root with backend on path)
"""
import sys
from pathlib import Path

# Ensure backend is on path when run as script
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from app.db.session import SessionLocal
from app.services.admin_service import clear_resy_db


def main():
    db = SessionLocal()
    try:
        deleted = clear_resy_db(db)
        print("Database cleared. Rows deleted:")
        for table, count in deleted.items():
            print(f"  {table}: {count}")
        print()
        print("Restart the backend server so the scheduler starts completely fresh.")
    except Exception as e:
        db.rollback()
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        db.close()


if __name__ == "__main__":
    main()
