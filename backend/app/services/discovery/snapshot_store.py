"""
Pre-computed discovery snapshot: compute once per tick, serve many clients.

After each discovery tick completes, `rebuild_snapshot(db)` builds the full
just-opened / still-open / feed / calendar-counts / bucket-health response
and stores it in memory.  API endpoints read from the snapshot and apply
lightweight in-memory filters (date, party_size) — zero DB queries per
client request.

With N concurrent users the DB load stays constant (one rebuild per tick)
instead of scaling linearly with poll requests.
"""
from __future__ import annotations

import copy
import logging
import threading
from datetime import date, datetime, timezone

from sqlalchemy.orm import Session

from app.core.constants import (
    DISCOVERY_JUST_OPENED_LIMIT,
    DISCOVERY_ROLLING_METRICS_LIMIT,
    JUST_OPENED_WITHIN_MINUTES,
)
from app.core.discovery_config import DISCOVERY_DATE_TIMEZONE
from app.core.nyc_hotspots import is_hotspot

logger = logging.getLogger(__name__)

_snapshot: dict | None = None
_snapshot_lock = threading.Lock()


def get_snapshot() -> dict | None:
    """Return a deep copy of the current snapshot, or None if not yet built."""
    with _snapshot_lock:
        if _snapshot is None:
            return None
        return copy.deepcopy(_snapshot)


def rebuild_snapshot(db: Session) -> None:
    """Recompute the full discovery snapshot from DB.  Called after each tick."""
    from app.services.discovery.buckets import (
        all_bucket_ids,
        get_bucket_health,
        get_just_opened_from_buckets,
        get_likely_to_open_venues,
        get_still_open_from_buckets,
        window_start_date,
        get_last_scan_info_buckets,
    )
    from app.services.discovery.feed import attach_likely_open_labels, build_feed
    from app.models.venue_rolling_metrics import VenueRollingMetrics

    try:
        today = window_start_date()

        just_opened = get_just_opened_from_buckets(
            db,
            limit_events=DISCOVERY_JUST_OPENED_LIMIT,
            date_filter=None,
            time_slots=None,
            party_sizes=None,
            opened_within_minutes=JUST_OPENED_WITHIN_MINUTES,
        )
        still_open = get_still_open_from_buckets(
            db,
            today,
            date_filter=None,
            time_slots=None,
            party_sizes=None,
            exclude_opened_within_minutes=JUST_OPENED_WITHIN_MINUTES,
        )

        for day in just_opened:
            for v in day.get("venues") or []:
                v["is_hotspot"] = is_hotspot(v.get("name"))
        for day in still_open:
            for v in day.get("venues") or []:
                v["is_hotspot"] = is_hotspot(v.get("name"))

        feed = build_feed(just_opened, [])
        ranked_board = feed["ranked_board"]
        top_opportunities = feed["top_opportunities"]
        hot_right_now = feed["hot_right_now"]

        try:
            from zoneinfo import ZoneInfo
            tz = ZoneInfo(DISCOVERY_DATE_TIMEZONE)
            today_calendar = datetime.now(tz).date()
        except Exception:
            today_calendar = date.today()
        attach_likely_open_labels(ranked_board, today_calendar)

        likely_to_open = get_likely_to_open_venues(db, today)

        rolling_rows = (
            db.query(VenueRollingMetrics)
            .filter(VenueRollingMetrics.venue_name.isnot(None))
            .order_by(VenueRollingMetrics.computed_at.desc())
            .limit(DISCOVERY_ROLLING_METRICS_LIMIT)
            .all()
        )
        rolling_by_name: dict[str, dict] = {}
        for rm in rolling_rows:
            key = (rm.venue_name or "").strip().lower()
            if key and key not in rolling_by_name:
                rolling_by_name[key] = {
                    "rarity_score": rm.rarity_score,
                    "availability_rate_14d": rm.availability_rate_14d,
                    "days_with_drops": rm.days_with_drops,
                    "drop_frequency_per_day": rm.drop_frequency_per_day,
                }

        def _attach_metrics(cards: list[dict]) -> None:
            for c in cards:
                nm = (c.get("name") or "").strip().lower()
                rm = rolling_by_name.get(nm)
                if rm:
                    c.update(rm)

        _attach_metrics(ranked_board)
        _attach_metrics(top_opportunities)
        _attach_metrics(hot_right_now)

        info = get_last_scan_info_buckets(db, today)
        bucket_health = get_bucket_health(db, today)

        # Calendar counts: unique venue count per date from the already-computed lists
        date_strs = sorted({
            d["date_str"] for d in just_opened + still_open if d.get("date_str")
        })
        # Also include all dates from buckets for the full 14-day range
        for _bid, date_str, _ts in all_bucket_ids(today):
            if date_str not in date_strs:
                date_strs.append(date_str)
        date_strs = sorted(set(date_strs))

        def _unique_venue_keys(venues: list[dict]) -> set[str]:
            return {
                str(v.get("venue_id") or v.get("name") or "")
                for v in (venues or []) if isinstance(v, dict)
            } - {""}

        jo_by_date = {d["date_str"]: d.get("venues") or [] for d in just_opened}
        so_by_date = {d["date_str"]: d.get("venues") or [] for d in still_open}
        calendar_by_date = {}
        for ds in date_strs:
            keys = _unique_venue_keys(jo_by_date.get(ds, [])) | _unique_venue_keys(so_by_date.get(ds, []))
            calendar_by_date[ds] = len(keys)

        snap = {
            "just_opened": just_opened,
            "still_open": still_open,
            "ranked_board": ranked_board,
            "top_opportunities": top_opportunities,
            "hot_right_now": hot_right_now,
            "likely_to_open": likely_to_open,
            "likely_open_today": [],
            "likely_open_tomorrow": [],
            "likely_open_soon": [],
            "bucket_health": bucket_health,
            "calendar_counts": {"by_date": calendar_by_date, "dates": date_strs},
            "rolling_by_name": rolling_by_name,
            **info,
            "computed_at": datetime.now(timezone.utc).isoformat(),
        }

        with _snapshot_lock:
            global _snapshot
            _snapshot = snap

        logger.info("Discovery snapshot rebuilt: %d just-opened days, %d still-open days",
                     len(just_opened), len(still_open))

    except Exception:
        logger.exception("Failed to rebuild discovery snapshot")


def filter_snapshot_for_request(
    snap: dict,
    date_filter: list[str] | None = None,
    party_sizes: list[int] | None = None,
) -> dict:
    """Apply date and party-size filters to a snapshot copy (in-memory, no DB)."""
    date_set = set(date_filter) if date_filter else None
    ps_set = set(party_sizes) if party_sizes else None

    def _filter_days(days: list[dict]) -> list[dict]:
        out = []
        for day in days:
            if date_set and day.get("date_str") not in date_set:
                continue
            if ps_set:
                filtered_venues = [
                    v for v in (day.get("venues") or [])
                    if _venue_matches_party(v, ps_set)
                ]
                day = {**day, "venues": filtered_venues}
            out.append(day)
        return out

    def _filter_cards(cards: list[dict]) -> list[dict]:
        out = []
        for c in cards:
            if date_set and c.get("date_str") and c["date_str"] not in date_set:
                continue
            if ps_set and not _venue_matches_party(c, ps_set):
                continue
            out.append(c)
        return out

    snap["just_opened"] = _filter_days(snap["just_opened"])
    snap["still_open"] = _filter_days(snap["still_open"])
    snap["ranked_board"] = _filter_cards(snap["ranked_board"])
    snap["top_opportunities"] = _filter_cards(snap["top_opportunities"])
    snap["hot_right_now"] = _filter_cards(snap["hot_right_now"])
    return snap


def _venue_matches_party(v: dict, ps_set: set[int]) -> bool:
    available = v.get("party_sizes_available") or []
    if not available:
        return True
    return bool(set(available) & ps_set)
