#!/usr/bin/env python3
"""Test Resy venue search API with different per_page values (e.g. 100 vs 200).
Run from backend: poetry run python scripts/test_resy_per_page.py
Or: python -m app.scripts.test_resy_per_page (from backend dir)
"""
import sys
from datetime import date, timedelta
from pathlib import Path

# backend dir (parent of scripts/)
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from app.services.resy import search_with_availability


def main():
    tomorrow = date.today() + timedelta(days=1)
    day_str = tomorrow.isoformat()
    print(f"Testing Resy venue search for {day_str}, party_size=2, time_filter=19:00")
    print()

    for per_page in (100, 200):
        result = search_with_availability(
            tomorrow,
            2,
            query="",
            time_filter="19:00",
            time_window_hours=1,
            per_page=per_page,
            max_pages=1,
        )
        if result.get("error"):
            print(f"  per_page={per_page}: ERROR — {result['error']}")
            if result.get("detail"):
                print(f"    detail: {result['detail'][:200]}")
        else:
            venues = result.get("venues") or []
            print(f"  per_page={per_page}: OK — {len(venues)} venues returned")
    print()
    print("If both show OK, the API accepts per_page=200. Use 200 in discovery for a fuller snapshot.")


if __name__ == "__main__":
    main()
    sys.exit(0)
