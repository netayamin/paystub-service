"""
Pre-computed discovery snapshot: compute once per tick, serve many clients.

After each discovery tick completes, `rebuild_snapshot(db)` builds the full
just-opened / still-open / feed / calendar-counts / bucket-health response
and stores it in memory.  API endpoints read from the snapshot and apply
lightweight in-memory filters (date, party_size) — zero DB queries per
client request.

The unfiltered response is also pre-serialized to JSON bytes so the common
no-filter path returns raw bytes with zero per-request Python work (no
deepcopy, no json.dumps, no jsonable_encoder).

With N concurrent users the DB load stays constant (one rebuild per tick)
instead of scaling linearly with poll requests.
"""
from __future__ import annotations

import json as _json
import logging
import threading
from datetime import date, datetime, timedelta, timezone

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
_snapshot_json: bytes | None = None         # full response (for debug / web clients)
_snapshot_json_mobile: bytes | None = None  # compact response for iOS (ranked_board capped, no day arrays)
_calendar_json: bytes | None = None
_bucket_health_json: bytes | None = None
_snapshot_lock = threading.Lock()

# How many ranked_board items to include in the mobile snapshot.
_MOBILE_RANKED_BOARD_LIMIT = 60


def get_snapshot_json() -> bytes | None:
    """Return pre-serialized JSON bytes for the no-filter just-opened response, or None."""
    with _snapshot_lock:
        return _snapshot_json


def get_snapshot_json_mobile() -> bytes | None:
    """Compact mobile snapshot: ranked_board capped at 60, no day arrays. ~10x smaller."""
    with _snapshot_lock:
        return _snapshot_json_mobile


def get_calendar_json() -> bytes | None:
    """Pre-serialized calendar-counts JSON."""
    with _snapshot_lock:
        return _calendar_json


def get_bucket_health_json() -> bytes | None:
    """Pre-serialized bucket-status JSON."""
    with _snapshot_lock:
        return _bucket_health_json


def get_snapshot() -> dict | None:
    """Return the raw snapshot dict (shared reference — callers must not mutate)."""
    with _snapshot_lock:
        return _snapshot


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
    from app.models.venue_metrics import VenueMetrics

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
                v["is_hotspot"] = is_hotspot(v.get("name"), v.get("market") or "nyc")
        for day in still_open:
            for v in day.get("venues") or []:
                v["is_hotspot"] = is_hotspot(v.get("name"), v.get("market") or "nyc")

        # Load rolling metrics FIRST so build_feed can rank by rarity
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
                    "trend_pct": rm.trend_pct,
                }

        # Enrich with avg_drop_duration_seconds from VenueMetrics (recent 14 days)
        try:
            start_date = today - timedelta(days=14)
            vm_rows = (
                db.query(
                    VenueMetrics.venue_name,
                    VenueMetrics.avg_drop_duration_seconds,
                )
                .filter(
                    VenueMetrics.window_date >= start_date,
                    VenueMetrics.venue_name.isnot(None),
                    VenueMetrics.avg_drop_duration_seconds.isnot(None),
                )
                .all()
            )
            # Average per venue (by name)
            from collections import defaultdict
            duration_by_name: dict[str, list[float]] = defaultdict(list)
            for row in vm_rows:
                key = (row.venue_name or "").strip().lower()
                if key and row.avg_drop_duration_seconds is not None:
                    duration_by_name[key].append(row.avg_drop_duration_seconds)
            for key, values in duration_by_name.items():
                if key in rolling_by_name and values:
                    rolling_by_name[key]["avg_drop_duration_seconds"] = sum(values) / len(values)
        except Exception:
            pass  # non-fatal

        def _attach_metrics_to_days(days: list[dict]) -> None:
            """Attach rolling metrics to raw venue dicts (before build_feed)."""
            for day in days:
                for v in day.get("venues") or []:
                    nm = (v.get("name") or "").strip().lower()
                    rm = rolling_by_name.get(nm)
                    if rm:
                        v.update(rm)

        _attach_metrics_to_days(just_opened)
        _attach_metrics_to_days(still_open)

        # Pass both just_opened AND still_open so the ranked board always has content
        feed = build_feed(just_opened, still_open)
        ranked_board    = feed["ranked_board"]
        ticker_board    = feed["ticker_board"]
        top_opportunities = feed["top_opportunities"]
        hot_right_now   = feed["hot_right_now"]

        try:
            from zoneinfo import ZoneInfo
            tz = ZoneInfo(DISCOVERY_DATE_TIMEZONE)
            today_calendar = datetime.now(tz).date()
        except Exception:
            today_calendar = date.today()
        attach_likely_open_labels(ranked_board, today_calendar)
        attach_likely_open_labels(ticker_board, today_calendar)

        likely_to_open = get_likely_to_open_venues(db, today)

        # Enrich likely_to_open with confidence label and predicted drop time
        _PREDICTED_TIMES = ("Evening", "Dinner", "Midnight", "10:00 AM")
        for i, item in enumerate(likely_to_open):
            rarity = item.get("rarity_score")
            rate   = item.get("availability_rate_14d")
            if rarity is not None and rate is not None:
                if rarity >= 70 or rate <= 0.2:
                    item["confidence"] = "High"
                elif rarity >= 40 or rate <= 0.5:
                    item["confidence"] = "Medium"
                else:
                    item["confidence"] = "Low"
            else:
                item["confidence"] = "Medium"
            item["predicted_drop_time"] = _PREDICTED_TIMES[i % len(_PREDICTED_TIMES)]

        def _attach_metrics(cards: list[dict]) -> None:
            for c in cards:
                nm = (c.get("name") or "").strip().lower()
                rm = rolling_by_name.get(nm)
                if rm:
                    c.update(rm)

        _attach_metrics(ranked_board)
        _attach_metrics(ticker_board)
        _attach_metrics(top_opportunities)
        _attach_metrics(hot_right_now)

        info = get_last_scan_info_buckets(db, today)
        bucket_health = get_bucket_health(db, today)

        # Calendar counts: unique venue count per date from the already-computed lists
        date_strs = sorted({
            d["date_str"] for d in just_opened + still_open if d.get("date_str")
        })
        # Also include all dates from buckets for the full 14-day range
        for _bid, date_str, _ts, _m in all_bucket_ids(today):
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
            "ticker_board": ticker_board,
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

        # Pre-serialize the API-ready response (without internal fields) to JSON bytes.
        # The no-filter fast path returns these bytes directly — zero per-request work.
        api_payload = {k: v for k, v in snap.items()
                       if k not in ("rolling_by_name", "bucket_health", "calendar_counts", "computed_at", "ticker_board")}
        api_bytes = _json.dumps(api_payload, separators=(",", ":"), default=str).encode()

        cal_bytes = _json.dumps(
            {"by_date": calendar_by_date, "dates": date_strs},
            separators=(",", ":"),
        ).encode()

        bh_stale = [b for b in bucket_health if b.get("stale")]
        bh_payload = {
            "buckets": bucket_health,
            "summary": {"total": len(bucket_health), "stale_count": len(bh_stale), "all_fresh": len(bh_stale) == 0},
        }
        bh_bytes = _json.dumps(bh_payload, separators=(",", ":"), default=str).encode()

        # Build compact mobile snapshot: drop heavy day arrays.
        # ranked_board = quality-filtered ticker_board so iOS gets only
        # attention-grabbing restaurants, not random noise.
        mobile_payload = {
            "ranked_board":      ticker_board[:_MOBILE_RANKED_BOARD_LIMIT],
            "top_opportunities": top_opportunities,
            "hot_right_now":     hot_right_now,
            "likely_to_open":    likely_to_open,
            "likely_open_today": [],
            "likely_open_tomorrow": [],
            "likely_open_soon":  [],
        }
        mobile_payload.update({k: v for k, v in info.items()})
        mobile_bytes = _json.dumps(mobile_payload, separators=(",", ":"), default=str).encode()

        with _snapshot_lock:
            global _snapshot, _snapshot_json, _snapshot_json_mobile, _calendar_json, _bucket_health_json
            _snapshot = snap
            _snapshot_json = api_bytes
            _snapshot_json_mobile = mobile_bytes
            _calendar_json = cal_bytes
            _bucket_health_json = bh_bytes

        logger.info(
            "Discovery snapshot rebuilt — full: %d KB, mobile: %d KB (%d ranked items capped to %d)",
            len(api_bytes) // 1024,
            len(mobile_bytes) // 1024,
            len(ranked_board),
            _MOBILE_RANKED_BOARD_LIMIT,
        )

    except Exception:
        logger.exception("Failed to rebuild discovery snapshot")


def filter_snapshot_for_request(
    snap: dict,
    date_filter: list[str] | None = None,
    party_sizes: list[int] | None = None,
    market_filter: list[str] | None = None,
) -> dict:
    """Build a filtered response dict from the shared snapshot (non-mutating).
    Pass market_filter=["nyc"] or ["miami"] to return only one city's data.
    """
    date_set = set(date_filter) if date_filter else None
    ps_set = set(party_sizes) if party_sizes else None
    mkt_set = set(market_filter) if market_filter else None

    def _venue_matches_market(v: dict) -> bool:
        if not mkt_set:
            return True
        return (v.get("market") or "nyc") in mkt_set

    def _filter_days(days: list[dict]) -> list[dict]:
        out = []
        for day in days:
            if date_set and day.get("date_str") not in date_set:
                continue
            venues = day.get("venues") or []
            if ps_set:
                venues = [v for v in venues if _venue_matches_party(v, ps_set)]
            if mkt_set:
                venues = [v for v in venues if _venue_matches_market(v)]
            if not venues and (ps_set or mkt_set):
                continue
            day = {**day, "venues": venues}
            out.append(day)
        return out

    def _filter_cards(cards: list[dict]) -> list[dict]:
        out = []
        for c in cards:
            if date_set and c.get("date_str") and c["date_str"] not in date_set:
                continue
            if ps_set and not _venue_matches_party(c, ps_set):
                continue
            if mkt_set and not _venue_matches_market(c):
                continue
            out.append(c)
        return out

    def _filter_likely_to_open(items: list[dict]) -> list[dict]:
        if not mkt_set:
            return items
        return [x for x in items if (x.get("market") or "nyc") in mkt_set]

    return {
        "just_opened": _filter_days(snap["just_opened"]),
        "still_open": _filter_days(snap["still_open"]),
        "ranked_board": _filter_cards(snap["ranked_board"]),
        "top_opportunities": _filter_cards(snap["top_opportunities"]),
        "hot_right_now": _filter_cards(snap["hot_right_now"]),
        "likely_to_open": _filter_likely_to_open(snap.get("likely_to_open", [])),
        "likely_open_today": [],
        "likely_open_tomorrow": [],
        "likely_open_soon": [],
        "last_scan_at": snap.get("last_scan_at"),
        "total_venues_scanned": snap.get("total_venues_scanned", 0),
    }


def _venue_matches_party(v: dict, ps_set: set[int]) -> bool:
    available = v.get("party_sizes_available") or []
    if not available:
        return True
    return bool(set(available) & ps_set)
