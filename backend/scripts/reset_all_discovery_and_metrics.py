#!/usr/bin/env python3
"""
Full reset: truncate all discovery + metrics + feed_cache + venues.
Use this so the new "venue had 0" logic starts from a clean DB — next discovery run will set baselines and only emit drops for venues that had no availability before.

Keeps: push_tokens, notify_preferences, alembic_version.

Run from backend dir (with backend stopped to avoid connection conflicts):
  cd backend && poetry run python scripts/reset_all_discovery_and_metrics.py

Or with backend running (uses its own DB connection):
  cd backend && poetry run python scripts/reset_all_discovery_and_metrics.py
"""
import sys
from pathlib import Path

backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from app.db.session import SessionLocal
from app.services.admin_service import reset_all_discovery_and_metrics


def main():
    print("Full reset: truncating discovery + metrics + feed_cache + venues ...")
    db = SessionLocal()
    try:
        result = reset_all_discovery_and_metrics(db)
        if result.get("ok"):
            print("Done. Truncated tables:", result.get("truncated", []))
            print()
            print("Next discovery job run will create fresh buckets and use the new")
            print('"venue had 0" logic (only show spots that had no availability before).')
            print("Restart the backend so the scheduler starts with a clean in-memory state.")
        else:
            print("Error:", result.get("error"), file=sys.stderr)
            sys.exit(1)
    except Exception as e:
        db.rollback()
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        db.close()


if __name__ == "__main__":
    main()
