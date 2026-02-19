#!/usr/bin/env python3
"""Reconcile drop_events: remove NEW_DROP rows whose slot is no longer in the bucket's prev_slot_ids.
Use after fixing the 'always delete on close' bug to clean existing orphan rows.
Run from backend: poetry run python scripts/reconcile_drop_events.py
"""
import json
import sys
from pathlib import Path

backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from app.db.session import SessionLocal
from app.models.discovery_bucket import DiscoveryBucket
from app.models.drop_event import DropEvent


def _parse_slot_ids_json(js: str | None) -> set[str]:
    if not js:
        return set()
    try:
        return set(json.loads(js))
    except (TypeError, json.JSONDecodeError):
        return set()


def main():
    db = SessionLocal()
    try:
        buckets = db.query(DiscoveryBucket).filter(DiscoveryBucket.prev_slot_ids_json.isnot(None)).all()
        total_removed = 0
        for row in buckets:
            curr_set = _parse_slot_ids_json(row.prev_slot_ids_json)
            q = db.query(DropEvent).filter(DropEvent.bucket_id == row.bucket_id)
            if curr_set:
                q = q.filter(DropEvent.slot_id.notin_(list(curr_set)))
            n = q.delete(synchronize_session=False)
            total_removed += n
        db.commit()
        print(f"Reconciled {len(buckets)} buckets: removed {total_removed} orphan NEW_DROP rows.")
    except Exception as e:
        db.rollback()
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        db.close()


if __name__ == "__main__":
    main()
