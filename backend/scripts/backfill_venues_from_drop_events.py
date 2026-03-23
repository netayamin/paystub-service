#!/usr/bin/env python3
"""One-off: merge historical drop_events into `venues` (image, neighborhood, resy_url, name, market).

Scans all rows with a venue_id in chronological order; for each field, the latest event that *provides*
that field wins (so we do not wipe an image when a newer event has no payload image).

By default only fills NULL columns on existing venues and creates missing venue rows — use --overwrite
to replace non-null values from the merged snapshot (use with care).

Run from backend directory:
  poetry run python scripts/backfill_venues_from_drop_events.py
  poetry run python scripts/backfill_venues_from_drop_events.py --dry-run
"""
from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from sqlalchemy import or_

from app.db.session import SessionLocal
from app.models.drop_event import DropEvent
from app.models.venue import Venue
from app.services.discovery.venue_profile import venue_profile_from_payload


def _merge_event_into(
    acc: dict[str, str | None],
    *,
    venue_name: str | None,
    neighborhood_col: str | None,
    payload: dict | None,
    market: str | None,
) -> None:
    """Update acc in place: only set keys when this row supplies a value (latest row wins per key)."""
    if venue_name and str(venue_name).strip():
        acc["venue_name"] = str(venue_name).strip()[:256]
    img, nb_payload, resy = venue_profile_from_payload(payload)
    if img:
        acc["image_url"] = img
    if resy:
        acc["resy_url"] = resy
    if neighborhood_col and str(neighborhood_col).strip():
        acc["neighborhood"] = str(neighborhood_col).strip()[:128]
    elif nb_payload:
        acc["neighborhood"] = nb_payload
    if market and str(market).strip():
        acc["market"] = str(market).strip()[:32]


def collect_merged_by_venue(db, yield_per: int) -> dict[str, dict[str, str | None]]:
    """Stream drop_events ordered by opened_at ascending; last writer per field wins."""
    q = (
        db.query(DropEvent)
        .filter(
            DropEvent.venue_id.isnot(None),
            or_(
                DropEvent.payload_json.isnot(None),
                DropEvent.neighborhood.isnot(None),
                DropEvent.venue_name.isnot(None),
                DropEvent.market.isnot(None),
            ),
        )
        .order_by(DropEvent.opened_at.asc())
    )
    merged: dict[str, dict[str, str | None]] = defaultdict(
        lambda: {
            "venue_name": None,
            "image_url": None,
            "neighborhood": None,
            "resy_url": None,
            "market": None,
        }
    )
    n_events = 0
    for ev in q.yield_per(yield_per):
        n_events += 1
        vid = str(ev.venue_id).strip()
        if not vid:
            continue
        payload: dict | None = None
        raw = ev.payload_json
        if raw and str(raw).strip():
            try:
                parsed = json.loads(raw)
                payload = parsed if isinstance(parsed, dict) else None
            except (json.JSONDecodeError, TypeError):
                payload = None
        _merge_event_into(
            merged[vid],
            venue_name=ev.venue_name,
            neighborhood_col=ev.neighborhood,
            payload=payload,
            market=ev.market,
        )
    return dict(merged), n_events


def apply_to_venues(
    db,
    merged: dict[str, dict[str, str | None]],
    *,
    dry_run: bool,
    overwrite: bool,
) -> tuple[int, int, int]:
    """Returns (created, updated, unchanged)."""
    now = datetime.now(timezone.utc)
    created = updated = unchanged = 0
    for vid, pdata in merged.items():
        row = db.query(Venue).filter(Venue.venue_id == vid).first()
        if not row:
            if dry_run:
                created += 1
                continue
            db.add(
                Venue(
                    venue_id=vid,
                    venue_name=pdata.get("venue_name"),
                    image_url=pdata.get("image_url"),
                    neighborhood=pdata.get("neighborhood"),
                    resy_url=pdata.get("resy_url"),
                    market=pdata.get("market"),
                )
            )
            created += 1
            continue

        changed = False
        for col in ("venue_name", "image_url", "neighborhood", "resy_url", "market"):
            new_val = pdata.get(col)
            if not new_val:
                continue
            cur = getattr(row, col)
            if overwrite or not cur:
                if cur != new_val:
                    setattr(row, col, new_val)
                    changed = True
        if changed:
            row.last_seen_at = now
            updated += 1
        else:
            unchanged += 1

    if not dry_run:
        db.commit()
    return created, updated, unchanged


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--dry-run", action="store_true", help="Scan and print counts only; no DB writes.")
    p.add_argument(
        "--yield-per",
        type=int,
        default=2000,
        metavar="N",
        help="ORM stream batch size (default 2000).",
    )
    p.add_argument(
        "--overwrite",
        action="store_true",
        help="Set venue fields from merged history even when already populated.",
    )
    args = p.parse_args()

    db = SessionLocal()
    try:
        merged, n_events = collect_merged_by_venue(db, args.yield_per)
        print(f"Scanned {n_events} drop_events → {len(merged)} distinct venue_id values.")
        created, updated, unchanged = apply_to_venues(
            db, merged, dry_run=args.dry_run, overwrite=args.overwrite
        )
        mode = "DRY-RUN: would " if args.dry_run else ""
        print(
            f"{mode}create {created} venues, update {updated}, leave unchanged {unchanged} "
            f"(overwrite={'on' if args.overwrite else 'off'})."
        )
    except Exception as e:
        db.rollback()
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        db.close()


if __name__ == "__main__":
    main()
