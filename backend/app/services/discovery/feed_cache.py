"""
Materialized feed cache: precompute just-opened + feed segments after each poll.
API reads from cache for fast responses.
"""
import json
import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy.orm import Session

from app.models.feed_cache import FeedCache
from app.services.discovery.buckets import get_just_opened_from_buckets, get_still_open_from_buckets, window_start_date
from app.services.discovery.feed import build_feed

logger = logging.getLogger(__name__)

CACHE_KEY_DEFAULT = "default"
CACHE_STALE_MINUTES = 10  # Use cache if updated within this; else recompute


def refresh_feed_cache(db: Session) -> None:
    """
    Compute full feed (default params: no filters) and upsert into feed_cache.
    Call after run_poll_all_buckets.
    """
    from app.core.constants import JUST_OPENED_WITHIN_MINUTES

    today = window_start_date()
    just_opened = get_just_opened_from_buckets(
        db,
        limit_events=5000,
        date_filter=None,
        time_slots=None,
        party_sizes=None,
        time_after_min=None,
        time_before_min=None,
        opened_within_minutes=JUST_OPENED_WITHIN_MINUTES,
    )
    still_open = get_still_open_from_buckets(
        db,
        today,
        date_filter=None,
        time_slots=None,
        party_sizes=None,
        time_after_min=None,
        time_before_min=None,
        exclude_opened_within_minutes=JUST_OPENED_WITHIN_MINUTES,
    )
    feed = build_feed(just_opened, still_open)
    from app.services.discovery.buckets import get_last_scan_info_buckets

    info = get_last_scan_info_buckets(db, today)
    payload = {
        "just_opened": just_opened,
        "still_open": still_open,
        "ranked_board": feed["ranked_board"],
        "top_opportunities": feed["top_opportunities"],
        "hot_right_now": feed["hot_right_now"],
        **info,
    }
    row = db.query(FeedCache).filter(FeedCache.cache_key == CACHE_KEY_DEFAULT).first()
    now = datetime.now(timezone.utc)
    if row:
        row.payload_json = json.dumps(payload)
        row.updated_at = now
    else:
        db.add(FeedCache(cache_key=CACHE_KEY_DEFAULT, payload_json=json.dumps(payload), updated_at=now))
    db.commit()
    logger.debug("Feed cache refreshed")


def get_feed_cache(db: Session) -> dict | None:
    """
    Return cached feed payload if present and not stale.
    Returns None if cache miss or stale.
    """
    row = db.query(FeedCache).filter(FeedCache.cache_key == CACHE_KEY_DEFAULT).first()
    if not row or not row.payload_json:
        return None
    cutoff = datetime.now(timezone.utc) - timedelta(minutes=CACHE_STALE_MINUTES)
    updated = row.updated_at
    if updated and updated.tzinfo is None:
        updated = updated.replace(tzinfo=timezone.utc)
    if updated is None or updated < cutoff:
        return None
    try:
        return json.loads(row.payload_json)
    except (TypeError, json.JSONDecodeError):
        return None
