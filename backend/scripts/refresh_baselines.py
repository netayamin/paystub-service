#!/usr/bin/env python3
"""
Refresh discovery baselines in place (current Resy search bounding box).
Overwrites each bucket's baseline and prev with a fresh fetch. No data deleted.
Run: cd backend && poetry run python scripts/refresh_baselines.py
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.db.session import SessionLocal
from app.services.discovery.buckets import refresh_baselines_for_all_buckets, window_start_date


def main():
    print("Refreshing baselines for all buckets (current lat/lng box)...")
    db = SessionLocal()
    try:

        def on_progress(bid: str, i: int, total: int, slot_count: int) -> None:
            print(f"  [{i}/{total}] {bid} — filled with {slot_count} slots")

        result = refresh_baselines_for_all_buckets(
            db, window_start_date(), progress_callback=on_progress
        )
        print(f"Done. buckets_refreshed={result['buckets_refreshed']}, buckets_total={result['buckets_total']}, errors={result['errors']}")
        if result["errors"]:
            sys.exit(1)
    finally:
        db.close()


if __name__ == "__main__":
    main()
