#!/usr/bin/env python3
"""Print discovery debug: bucket health, last scan, recent drops sample.

Run from backend: poetry run python scripts/discovery_debug.py

Or with backend running: curl -s http://127.0.0.1:8000/chat/watches/discovery-debug | jq
"""
import sys
from pathlib import Path

backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from app.db.session import SessionLocal
from app.services.discovery import get_discovery_debug


def main():
    db = SessionLocal()
    try:
        out = get_discovery_debug(db)
        summary = out.get("summary", {})
        print("Discovery (bucket pipeline) debug")
        print("==================================")
        print(f"Last scan:        {summary.get('last_scan_at') or 'never'}")
        print(f"Buckets:         {summary.get('buckets_count', 0)}")
        print(f"Total slots:     {summary.get('total_venues_scanned', 0)}")
        print()
        print("Recent drops sample (name, minutes_ago):")
        for s in out.get("hot_drops_sample") or []:
            name = (s.get("name") or "?")[:50]
            ma = s.get("minutes_ago")
            ago = f"{ma}m ago" if ma is not None else "—"
            print(f"  - {name}  {ago}")
        print()
        print("API: GET http://127.0.0.1:8000/chat/watches/discovery-debug")
        print("Health: GET http://127.0.0.1:8000/chat/watches/discovery-health")
    finally:
        db.close()


if __name__ == "__main__":
    main()
    sys.exit(0)
