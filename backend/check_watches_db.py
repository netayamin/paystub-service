#!/usr/bin/env python3
"""One-off script to check if venue_watches and venue_notify_requests tables are populated."""
import sys
from pathlib import Path

# ensure backend is on path
sys.path.insert(0, str(Path(__file__).resolve().parent))

from sqlalchemy import text
from app.db.session import SessionLocal
from app.models.venue_watch import VenueWatch


def main():
    db = SessionLocal()
    try:
        watches = db.query(VenueWatch).all()
        print("=== venue_watches ===")
        print(f"Count: {len(watches)}")
        for w in watches[:15]:
            print(f"  id={w.id} session_id={w.session_id!r} criteria_key={w.criteria_key!r} interval_minutes={w.interval_minutes}")
        if len(watches) > 15:
            print(f"  ... and {len(watches) - 15} more")

        # Use raw SQL so we don't depend on optional 'title' column (migration 011)
        result = db.execute(text("SELECT id, session_id, venue_name, status FROM venue_notify_requests"))
        notifies = result.fetchall()
        print("\n=== venue_notify_requests ===")
        print(f"Count: {len(notifies)}")
        for row in notifies[:15]:
            print(f"  id={row[0]} session_id={row[1]!r} venue_name={row[2]!r} status={row[3]!r}")
        if len(notifies) > 15:
            print(f"  ... and {len(notifies) - 15} more")
    finally:
        db.close()


if __name__ == "__main__":
    main()
