#!/usr/bin/env python3
"""Run OpenTable test in a subprocess. Prints one JSON line to stdout.

Used by GET /chat/watches/opentable-test so the main server never runs the
blocking OpenTable HTTP call. Run from backend: poetry run python scripts/opentable_test_standalone.py
"""
import json
import sys
from datetime import date
from pathlib import Path

backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))


def main() -> int:
    try:
        from app.services.providers import get_provider

        today_str = date.today().isoformat()
        provider = get_provider("opentable")
        slots = provider.search_availability(today_str, "19:30", [2, 4])
    except Exception as e:
        out = {"ok": False, "error": str(e), "hint": "OpenTable GQL may be rate-limited or changed."}
        print(json.dumps(out))
        return 1

    sample = []
    for s in (slots or [])[:5]:
        payload = getattr(s, "payload", None) or {}
        sample.append({
            "name": getattr(s, "venue_name", ""),
            "venue_id": getattr(s, "venue_id", ""),
            "book_url": (payload.get("book_url") or payload.get("resy_url")) or None,
        })
    out = {
        "ok": True,
        "request": "today, 19:30, party=[2,4]",
        "result": {"slot_count": len(slots) if slots else 0, "sample": sample},
    }
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
