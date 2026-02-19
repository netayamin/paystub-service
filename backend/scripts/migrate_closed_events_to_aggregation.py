#!/usr/bin/env python3
"""
One-time migration: take all existing CLOSED events in drop_events, write them into
venue_metrics and market_metrics, then remove those CLOSED and their corresponding
NEW_DROP rows from drop_events. (Obsolete after event_type column is dropped: we no
longer persist CLOSED rows.)

Usage: cd backend && poetry run python scripts/migrate_closed_events_to_aggregation.py [--dry-run]
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.db.session import SessionLocal
from app.models.drop_event import DropEvent
from app.services.aggregation import aggregate_closed_events_into_metrics


def main():
    parser = argparse.ArgumentParser(description="Migrate existing CLOSED events to aggregation and remove from drop_events")
    parser.add_argument("--dry-run", action="store_true", help="Only report counts, do not write or delete")
    args = parser.parse_args()

    db = SessionLocal()
    try:
        # drop_events no longer has event_type; this script is a no-op after that migration
        if not hasattr(DropEvent, "event_type"):
            print("drop_events no longer has event_type; nothing to migrate.")
            return
        closed = db.query(DropEvent).filter(DropEvent.event_type == "CLOSED").all()
        n_closed = len(closed)
        if n_closed == 0:
            print("No CLOSED events in drop_events. Nothing to migrate.")
            return

        # Pairs (bucket_id, slot_id) for which we will delete NEW_DROP rows
        closed_pairs = list({(e.bucket_id, e.slot_id) for e in closed})
        closed_ids = [e.id for e in closed]

        from sqlalchemy import tuple_
        new_drop_matching = (
            db.query(DropEvent)
            .filter(tuple_(DropEvent.bucket_id, DropEvent.slot_id).in_(closed_pairs))
            .count()
        )

        print(f"Found {n_closed} CLOSED events and {new_drop_matching} matching NEW_DROP rows to remove.")

        if args.dry_run:
            print("Dry run: no changes made.")
            return

        # 1) Write CLOSED into aggregation tables
        print("Writing CLOSED events into venue_metrics and market_metrics ...")
        aggregate_closed_events_into_metrics(db, closed)
        print("Done aggregating.")

        # 2) Delete CLOSED rows
        deleted_closed = db.query(DropEvent).filter(DropEvent.id.in_(closed_ids)).delete(synchronize_session=False)
        db.commit()
        print(f"Deleted {deleted_closed} CLOSED rows.")

        # 3) Delete NEW_DROP rows for those (bucket_id, slot_id); batch to avoid huge IN list
        batch_size = 500
        deleted_new = 0
        for i in range(0, len(closed_pairs), batch_size):
            batch = closed_pairs[i : i + batch_size]
            n = (
                db.query(DropEvent)
                .filter(tuple_(DropEvent.bucket_id, DropEvent.slot_id).in_(batch))
                .delete(synchronize_session=False)
            )
            deleted_new += n
        db.commit()
        print(f"Deleted {deleted_new} NEW_DROP rows (slots that had been closed).")
        print("Migration done. drop_events is now smaller; aggregation tables are up to date.")
    finally:
        db.close()


if __name__ == "__main__":
    main()
