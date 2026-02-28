"""
Discovery: rolling 14-day availability and drops (bucket pipeline only).

- discovery_buckets: 28 buckets (date × 15:00/20:30); baseline/prev slot_id sets.
- drop_events: emitted when a slot opens (drops = (curr - prev) ∩ (curr - baseline)).
- No legacy discovery_scans (table dropped in migration 024).
"""

from datetime import date

from app.services.discovery.buckets import (
    get_bucket_health,
    get_discovery_debug_buckets,
    get_feed,
    get_feed_item_debug,
    get_just_opened_from_buckets,
    get_last_scan_info_buckets,
    get_still_open_from_buckets,
    window_start_date,
)
from app.services.discovery.scan import (
    get_discovery_fast_checks,
    get_discovery_job_heartbeat,
    set_discovery_job_heartbeat,
)


def get_just_opened(db):
    """API alias: same shape as legacy; built from drop_events."""
    return get_just_opened_from_buckets(db)


def get_last_scan_info(db):
    """API alias: last_scan_at and total_venues_scanned from discovery_buckets."""
    return get_last_scan_info_buckets(db, window_start_date())


def get_discovery_debug(db, **_kwargs):
    """API alias: bucket_health + recent drops sample."""
    return get_discovery_debug_buckets(db, window_start_date())


__all__ = [
    "get_bucket_health",
    "get_discovery_debug",
    "get_discovery_fast_checks",
    "get_discovery_job_heartbeat",
    "get_feed",
    "get_feed_item_debug",
    "get_just_opened",
    "get_last_scan_info",
    "get_still_open_from_buckets",
    "set_discovery_job_heartbeat",
]
