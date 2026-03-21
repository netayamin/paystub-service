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


def build_just_missed_payload(db: Session, *, now: datetime | None = None) -> list[dict]:
    """Deduplicate by venue_id or name; newest first; cap JUST_MISSED_FEED_LIMIT."""
    now_utc = now or datetime.now(timezone.utc)
    prune_stale_missed_rows(db, now=now_utc)
    cutoff = now_utc - timedelta(minutes=JUST_MISSED_WITHIN_MINUTES)
    rows = (
        db.query(RecentMissedDrop)
        .filter(RecentMissedDrop.gone_at >= cutoff)
        .order_by(RecentMissedDrop.gone_at.desc())
        .limit(80)
        .all()
    )
    seen: set[str] = set()
    out: list[dict] = []
    for r in rows:
        key = ((r.venue_id or "").strip().lower() or (r.venue_name or "").strip().lower())
        if not key or key in seen:
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
