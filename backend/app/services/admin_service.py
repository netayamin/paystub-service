"""
Admin: clear discovery tables. Scheduler state is in-memory; restart backend for a fully fresh scheduler.
Current DB tables (only these exist): discovery_buckets, drop_events, venues, feed_cache (see app.db.tables).
"""
import logging

from sqlalchemy import text
from sqlalchemy.orm import Session

from app.db.tables import DISCOVERY_TABLE_NAMES
from app.models.discovery_bucket import DiscoveryBucket
from app.models.drop_event import DropEvent

logger = logging.getLogger(__name__)


def clear_resy_db(db: Session) -> dict[str, int]:
    """
    Delete all rows from discovery tables (discovery_buckets, drop_events only).
    Returns dict of table -> deleted count.
    Scheduler runs in-process; restart the backend server for a completely fresh scheduler.
    """
    deleted: dict[str, int] = {}
    deleted["drop_events"] = db.query(DropEvent).delete()
    deleted["discovery_buckets"] = db.query(DiscoveryBucket).delete()
    db.commit()
    return deleted


def reset_discovery_buckets(db: Session) -> dict[str, int]:
    """
    Delete all discovery_buckets and drop_events only. Next discovery job run will
    create fresh buckets and set baseline from the first poll. Watches/chat are untouched.
    Uses TRUNCATE for speed when possible; falls back to DELETE if not.
    """
    logger.info("reset_discovery_buckets: starting")
    deleted: dict[str, int] = {}
    try:
        # TRUNCATE is near-instant; DELETE can hang on large tables (e.g. 20k+ drop_events)
        tables = ", ".join(DISCOVERY_TABLE_NAMES)
        db.execute(text(f"TRUNCATE TABLE {tables} RESTART IDENTITY CASCADE"))
        db.commit()
        for t in DISCOVERY_TABLE_NAMES:
            deleted[t] = -1  # unknown count with TRUNCATE
        logger.info("reset_discovery_buckets: done (TRUNCATE)")
    except Exception as e:
        db.rollback()
        logger.warning("reset_discovery_buckets: TRUNCATE failed (%s), using DELETE", e)
        deleted["drop_events"] = db.query(DropEvent).delete()
        deleted["discovery_buckets"] = db.query(DiscoveryBucket).delete()
        db.commit()
        logger.info("reset_discovery_buckets: done (DELETE) drop_events=%s discovery_buckets=%s", deleted["drop_events"], deleted["discovery_buckets"])
    return deleted
