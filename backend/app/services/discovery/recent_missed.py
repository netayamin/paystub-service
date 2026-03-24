"""Persist and query recently closed slots for the mobile feed \"just_missed\" strip."""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone
from typing import Any

from sqlalchemy.orm import Session

from app.models.recent_missed_drop import RecentMissedDrop

logger = logging.getLogger(__name__)

JUST_MISSED_WITHIN_MINUTES = 90
JUST_MISSED_PRUNE_HOURS = 6
JUST_MISSED_FEED_LIMIT = 12


def venue_identity_key(venue_id: str | None, name: str | None) -> str:
    """Stable key matching `build_just_missed_payload` dedupe (venue_id else name, lowercased)."""
    return ((venue_id or "").strip().lower() or (name or "").strip().lower())


def collect_bookable_venue_keys(
    just_opened: list[dict] | None,
    still_open: list[dict] | None,
) -> set[str]:
    """Venues that still have at least one open slot in discovery day lists."""
    keys: set[str] = set()
    for days in (just_opened or [], still_open or []):
        for day in days:
            for v in day.get("venues") or []:
                if not isinstance(v, dict):
                    continue
                k = venue_identity_key(v.get("venue_id"), v.get("name"))
                if k:
                    keys.add(k)
    return keys


def record_closed_slots_as_missed(
    db: Session,
    closed_rows: list[Any],
    *,
    market: str,
    now: datetime,
) -> None:
    """Insert one row per closed slot (same venue may appear multiple times — UI dedupes)."""
    batch: list[RecentMissedDrop] = []
    for row in closed_rows:
        vn = (getattr(row, "venue_name", None) or "").strip()
        if not vn:
            continue
        mkt = getattr(row, "market", None) or market
        batch.append(
            RecentMissedDrop(
                venue_id=getattr(row, "venue_id", None),
                venue_name=vn,
                image_url=getattr(row, "image_url", None),
                neighborhood=getattr(row, "neighborhood", None),
                market=mkt,
                slot_time=getattr(row, "slot_time", None),
                gone_at=now,
            )
        )
    if not batch:
        return
    try:
        db.add_all(batch)
    except Exception as e:
        logger.debug("recent_missed_drops add_all failed: %s", e)


def prune_stale_missed_rows(db: Session, *, now: datetime | None = None) -> int:
    cutoff = (now or datetime.now(timezone.utc)) - timedelta(hours=JUST_MISSED_PRUNE_HOURS)
    try:
        return (
            db.query(RecentMissedDrop)
            .filter(RecentMissedDrop.gone_at < cutoff)
            .delete(synchronize_session=False)
        )
    except Exception as e:
        logger.warning("prune recent_missed_drops failed: %s", e)
        return 0


def build_just_missed_payload(
    db: Session,
    *,
    now: datetime | None = None,
    exclude_bookable_keys: set[str] | None = None,
    within_minutes: int | None = None,
) -> list[dict]:
    """Deduplicate by venue_id or name; newest first; cap JUST_MISSED_FEED_LIMIT.

    If ``exclude_bookable_keys`` is set (from just_opened + still_open), venues that
    still have availability are omitted — a single closed slot must not imply \"just missed\"
    for the whole venue while other slots remain bookable.

    ``within_minutes`` overrides the lookback window (default ``JUST_MISSED_WITHIN_MINUTES``).
    """
    now_utc = now or datetime.now(timezone.utc)
    prune_stale_missed_rows(db, now=now_utc)
    minutes = within_minutes if within_minutes is not None and within_minutes > 0 else JUST_MISSED_WITHIN_MINUTES
    cutoff = now_utc - timedelta(minutes=minutes)
    # When excluding many rows, scan deeper so the strip can still fill up to the cap.
    query_limit = 200 if exclude_bookable_keys else 80
    rows = (
        db.query(RecentMissedDrop)
        .filter(RecentMissedDrop.gone_at >= cutoff)
        .order_by(RecentMissedDrop.gone_at.desc())
        .limit(query_limit)
        .all()
    )
    seen: set[str] = set()
    out: list[dict] = []
    exc = exclude_bookable_keys or set()
    for r in rows:
        key = venue_identity_key(r.venue_id, r.venue_name)
        if not key or key in seen:
            continue
        if key in exc:
            seen.add(key)
            continue
        seen.add(key)
        ga = r.gone_at
        out.append(
            {
                "venue_id": r.venue_id,
                "name": r.venue_name,
                "image_url": r.image_url,
                "neighborhood": r.neighborhood,
                "gone_at": ga.isoformat() if ga else None,
                "slot_time": r.slot_time,
                "market": r.market,
            }
        )
        if len(out) >= JUST_MISSED_FEED_LIMIT:
            break
    return out
