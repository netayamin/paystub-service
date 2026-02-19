#!/usr/bin/env python3
"""Delete all CLOSED rows from drop_events (safety net + one-off cleanup).
Run from backend: poetry run python scripts/delete_closed_drop_events.py
Or: python -m backend.scripts.delete_closed_drop_events (from repo root with backend on path)
"""
import sys
from pathlib import Path

backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from app.db.session import SessionLocal
from app.services.discovery.buckets import delete_closed_drop_events


def main():
    db = SessionLocal()
    try:
        total = delete_closed_drop_events(db, batch_size=50_000)
        print(f"Deleted {total} CLOSED drop_events.")
    except Exception as e:
        db.rollback()
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        db.close()


if __name__ == "__main__":
    main()
