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


_last_rolling_refresh_at: datetime | None = None
_ROLLING_REFRESH_INTERVAL_SECONDS = 300  # recompute rolling metrics every 5 minutes


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
    from app.services.discovery.feed import (
        attach_likely_open_labels,
        build_feed,
        sanitize_feed_cards_for_client,
        snag_feed_meta,
    )
    from app.services.discovery.feed_display import attach_feed_card_display_fields
    from app.services.discovery.likely_open_scoring import enrich_likely_open_item
    from app.models.venue_rolling_metrics import VenueRollingMetrics
    from app.models.venue_metrics import VenueMetrics

    try:
        today = window_start_date()

        # Periodically refresh open-drop counts and rolling metrics so the feed
        # isn't stuck on stale data from the daily 7:05 AM job.
        global _last_rolling_refresh_at
        now_utc = datetime.now(timezone.utc)
        should_refresh = (
            _last_rolling_refresh_at is None
            or (now_utc - _last_rolling_refresh_at).total_seconds() >= _ROLLING_REFRESH_INTERVAL_SECONDS
        )
        if should_refresh:
            try:
                from app.services.aggregation import (
                    aggregate_open_drops_into_metrics,
                    compute_venue_rolling_metrics,
                )
                aggregate_open_drops_into_metrics(db, today)
                compute_venue_rolling_metrics(db, today)
                _last_rolling_refresh_at = now_utc
                logger.info("Periodic rolling metrics refresh completed")
            except Exception as e:
                logger.warning("Periodic rolling metrics refresh failed: %s", e)

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

        # Load rolling metrics FIRST so build_feed can rank by rarity.
        # Restrict to the latest as_of_date so we never mix stale rows from
        # an older computation window with current ones.
        from sqlalchemy import func as _sqlfunc
        from collections import defaultdict
        latest_as_of = (
            db.query(_sqlfunc.max(VenueRollingMetrics.as_of_date))
            .scalar()
        )
        # Do NOT filter on venue_name — venues with no name but a valid venue_id
        # are still matchable by ID and should not be silently dropped.
        rolling_query = db.query(VenueRollingMetrics)
        if latest_as_of is not None:
            rolling_query = rolling_query.filter(
                VenueRollingMetrics.as_of_date == latest_as_of
            )
        rolling_rows = (
            rolling_query
            .order_by(VenueRollingMetrics.computed_at.desc())
            .limit(DISCOVERY_ROLLING_METRICS_LIMIT)
            .all()
        )

        def _metrics_dict(rm: VenueRollingMetrics) -> dict:
            return {
                "rarity_score": rm.rarity_score,
                "availability_rate_14d": rm.availability_rate_14d,
                "days_with_drops": rm.days_with_drops,
                "drop_frequency_per_day": rm.drop_frequency_per_day,
                "trend_pct": rm.trend_pct,
            }

        # Primary index: venue_id (stable Resy ID — survives name changes)
        rolling_by_id: dict[str, dict] = {}
        # Fallback index: normalised venue name
        rolling_by_name: dict[str, dict] = {}
        for rm in rolling_rows:
            vid = (rm.venue_id or "").strip()
            if vid and vid not in rolling_by_id:
                rolling_by_id[vid] = _metrics_dict(rm)
            nm = (rm.venue_name or "").strip().lower()
            if nm and nm not in rolling_by_name:
                rolling_by_name[nm] = _metrics_dict(rm)

        # Enrich with avg_drop_duration_seconds from VenueMetrics (recent 14 days).
        # Also build by venue_id so the speed signal can be matched by ID.
        try:
            start_date = today - timedelta(days=14)
            vm_rows = (
                db.query(
                    VenueMetrics.venue_id,
                    VenueMetrics.venue_name,
                    VenueMetrics.avg_drop_duration_seconds,
                )
                .filter(
                    VenueMetrics.window_date >= start_date,
                    VenueMetrics.avg_drop_duration_seconds.isnot(None),
                )
                .all()
            )
            duration_by_id: dict[str, list[float]] = defaultdict(list)
            duration_by_name: dict[str, list[float]] = defaultdict(list)
            for row in vm_rows:
                vid = (row.venue_id or "").strip()
                nm = (row.venue_name or "").strip().lower()
                val = row.avg_drop_duration_seconds
                if val is not None:
                    if vid:
                        duration_by_id[vid].append(val)
                    if nm:
                        duration_by_name[nm].append(val)
            for vid, values in duration_by_id.items():
                if vid in rolling_by_id and values:
                    rolling_by_id[vid]["avg_drop_duration_seconds"] = sum(values) / len(values)
            for nm, values in duration_by_name.items():
                if nm in rolling_by_name and values:
                    rolling_by_name[nm]["avg_drop_duration_seconds"] = sum(values) / len(values)
        except Exception:
            pass  # non-fatal

        def _lookup_metrics(venue_id: str | None, name: str | None) -> dict | None:
            """Return rolling metrics dict: venue_id match first, name fallback."""
            vid = (venue_id or "").strip()
            if vid and vid in rolling_by_id:
                return rolling_by_id[vid]
            nm = (name or "").strip().lower()
            if nm and nm in rolling_by_name:
                return rolling_by_name[nm]
            return None

        def _attach_metrics_to_days(days: list[dict]) -> None:
            """Attach rolling metrics to raw venue dicts (before build_feed)."""
            for day in days:
                for v in day.get("venues") or []:
                    rm = _lookup_metrics(v.get("venue_id"), v.get("name"))
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

        for i, item in enumerate(likely_to_open):
            enrich_likely_open_item(item, i)

        from app.services.discovery.recent_missed import build_just_missed_payload

        just_missed = build_just_missed_payload(db, now=now_utc)

        def _attach_metrics(cards: list[dict]) -> None:
            for c in cards:
                rm = _lookup_metrics(c.get("venue_id"), c.get("name"))
                if rm:
                    c.update(rm)

        _attach_metrics(ranked_board)
        _attach_metrics(ticker_board)
        _attach_metrics(top_opportunities)
        _attach_metrics(hot_right_now)

        _now_disp = datetime.now(timezone.utc)
        attach_feed_card_display_fields(ranked_board, _now_disp)
        attach_feed_card_display_fields(ticker_board, _now_disp)
        attach_feed_card_display_fields(top_opportunities, _now_disp)
        attach_feed_card_display_fields(hot_right_now, _now_disp)

        sanitize_feed_cards_for_client(ranked_board)
        sanitize_feed_cards_for_client(ticker_board)
        sanitize_feed_cards_for_client(top_opportunities)
        sanitize_feed_cards_for_client(hot_right_now)

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

        feed_meta = snag_feed_meta()

        snap = {
            "just_opened": just_opened,
            "still_open": still_open,
            "ranked_board": ranked_board,
            "ticker_board": ticker_board,
            "top_opportunities": top_opportunities,
            "hot_right_now": hot_right_now,
            "likely_to_open": likely_to_open,
            "just_missed": just_missed,
            "likely_open_today": [],
            "likely_open_tomorrow": [],
            "likely_open_soon": [],
            "feed_meta": feed_meta,
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
            "feed_meta":         feed_meta,
            "ranked_board":      ticker_board[:_MOBILE_RANKED_BOARD_LIMIT],
            "top_opportunities": top_opportunities,
            "hot_right_now":     hot_right_now,
            "likely_to_open":    likely_to_open,
            "just_missed":       just_missed,
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

    def _filter_just_missed(items: list[dict]) -> list[dict]:
        if not mkt_set:
            return items
        return [x for x in items if (x.get("market") or "nyc") in mkt_set]

    rb = _filter_cards(snap["ranked_board"])
    top = _filter_cards(snap["top_opportunities"])
    hrn = _filter_cards(snap["hot_right_now"])
    sanitize_feed_cards_for_client(rb)
    sanitize_feed_cards_for_client(top)
    sanitize_feed_cards_for_client(hrn)

    return {
        "just_opened": _filter_days(snap["just_opened"]),
        "still_open": _filter_days(snap["still_open"]),
        "ranked_board": rb,
        "top_opportunities": top,
        "hot_right_now": hrn,
        "likely_to_open": _filter_likely_to_open(snap.get("likely_to_open", [])),
        "just_missed": _filter_just_missed(snap.get("just_missed", [])),
        "likely_open_today": [],
        "likely_open_tomorrow": [],
        "likely_open_soon": [],
        "feed_meta": snap.get("feed_meta"),
        "last_scan_at": snap.get("last_scan_at"),
        "total_venues_scanned": snap.get("total_venues_scanned", 0),
    }


def _venue_matches_party(v: dict, ps_set: set[int]) -> bool:
    available = v.get("party_sizes_available") or []
    if not available:
        return True
    return bool(set(available) & ps_set)
