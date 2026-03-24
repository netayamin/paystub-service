"""
Discovery API — routes used by the iOS app (and ops via /docs).

See ``backend/docs/API_IOS.md`` for the full client contract.
"""
import json
import logging
from datetime import date, datetime, timezone, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, Request, Response
from sqlalchemy.orm import Session

from app.core.constants import (
    DISCOVERY_BUCKET_JOB_ID,
    DISCOVERY_JUST_OPENED_LIMIT,
    DISCOVERY_POLL_INTERVAL_SECONDS,
    DISCOVERY_ROLLING_METRICS_LIMIT,
    JUST_OPENED_WITHIN_MINUTES,
    LIVE_FEED_WINDOW_MINUTES,
)
from app.core.discovery_config import DISCOVERY_DATE_TIMEZONE
from app.core.hotspots import is_hotspot
from app.db.session import get_db
from app.models.discovery_bucket import DiscoveryBucket
from app.models.notify_preference import NotifyPreference
from app.models.venue_rolling_metrics import VenueRollingMetrics
from app.services.discovery.buckets import (
    all_bucket_ids,
    get_just_opened_from_buckets,
    get_last_scan_info_buckets,
    get_likely_to_open_venues,
    get_still_open_from_buckets,
    window_start_date,
)
from app.services.discovery.feed import (
    attach_likely_open_labels,
    build_feed,
    sanitize_feed_cards_for_client,
    snag_feed_meta,
)
from app.services.discovery.feed_display import attach_feed_card_display_fields
from app.services.discovery.follow_activity import follow_activity_timeline, follow_status_for_recipient
from app.services.discovery.likely_open_scoring import enrich_likely_open_item
from app.services.discovery.snapshot_store import (
    filter_inventory_for_drops,
    filter_snapshot_for_request,
    get_snapshot,
    get_snapshot_json,
    get_snapshot_json_mobile,
)

router = APIRouter()
logger = logging.getLogger(__name__)


def _next_scan_iso(request: Request) -> str:
    """Next discovery bucket job run time (UTC ISO). Fallback if scheduler not ready."""
    try:
        scheduler = getattr(request.app.state, "scheduler", None)
        if not scheduler:
            return (datetime.now(timezone.utc) + timedelta(seconds=DISCOVERY_POLL_INTERVAL_SECONDS)).isoformat()
        job = scheduler.get_job(DISCOVERY_BUCKET_JOB_ID)
        if job and getattr(job, "next_run_time", None):
            at = job.next_run_time
            if at.tzinfo is None:
                at = at.replace(tzinfo=timezone.utc)
            return at.isoformat()
    except Exception:
        pass
    return (datetime.now(timezone.utc) + timedelta(seconds=DISCOVERY_POLL_INTERVAL_SECONDS)).isoformat()



def _normalize_venue(name: str | None) -> str:
    if not name:
        return ""
    return name.strip().lower()


def _recipient_id(request: Request) -> str:
    return (request.headers.get("X-Recipient-Id") or "default").strip() or "default"


@router.get("/watches")
async def get_venue_watches(request: Request, db: Session = Depends(get_db)):
    """
    User's notify list: saved (include) and excluded (removed from default hotlist).
    Effective notify list = (hotlist ∪ watches) − excluded.
    """
    rid = _recipient_id(request)
    includes = (
        db.query(NotifyPreference)
        .filter(NotifyPreference.recipient_id == rid, NotifyPreference.preference == "include")
        .all()
    )
    excludes = (
        db.query(NotifyPreference)
        .filter(NotifyPreference.recipient_id == rid, NotifyPreference.preference == "exclude")
        .all()
    )
    # Frontend expects venue_name (display); we store normalized. Return display as title-case of normalized for includes; for hotlist we don't store display name so use normalized as-is (frontend can capitalize).
    watches = [{"id": r.id, "venue_name": r.venue_name_normalized} for r in includes]
    excluded = [{"id": r.id, "venue_name": r.venue_name_normalized} for r in excludes]
    return {"watches": watches, "excluded": excluded}


@router.post("/watches")
async def add_venue_watch(request: Request, db: Session = Depends(get_db)):
    """Add a venue to your notify list (include)."""
    body = await request.json() if request.headers.get("content-type", "").startswith("application/json") else {}
    name = (body.get("venue_name") or "").strip()
    if not name:
        return Response(status_code=400, content='{"error": "venue_name required"}', media_type="application/json")
    rid = _recipient_id(request)
    norm = _normalize_venue(name)
    existing = (
        db.query(NotifyPreference)
        .filter(NotifyPreference.recipient_id == rid, NotifyPreference.venue_name_normalized == norm)
        .first()
    )
    if existing:
        if existing.preference == "exclude":
            existing.preference = "include"
            db.commit()
            return {"id": existing.id, "venue_name": norm}
        return {"id": existing.id, "venue_name": norm}
    row = NotifyPreference(recipient_id=rid, venue_name_normalized=norm, preference="include")
    db.add(row)
    db.commit()
    db.refresh(row)
    return {"id": row.id, "venue_name": norm}


@router.delete("/watches/{watch_id:int}")
async def remove_venue_watch(request: Request, watch_id: int, db: Session = Depends(get_db)):
    """Remove a venue from your saved list (include)."""
    rid = _recipient_id(request)
    row = (
        db.query(NotifyPreference)
        .filter(NotifyPreference.id == watch_id, NotifyPreference.recipient_id == rid, NotifyPreference.preference == "include")
        .first()
    )
    if not row:
        return Response(status_code=404, content='{"error": "not found"}', media_type="application/json")
    db.delete(row)
    db.commit()
    return {"ok": True}


@router.post("/watches/exclude")
async def add_venue_exclude(request: Request, db: Session = Depends(get_db)):
    """Remove a venue from default hotlist notifications (exclude)."""
    body = await request.json() if request.headers.get("content-type", "").startswith("application/json") else {}
    name = (body.get("venue_name") or "").strip()
    if not name:
        return Response(status_code=400, content='{"error": "venue_name required"}', media_type="application/json")
    rid = _recipient_id(request)
    norm = _normalize_venue(name)
    existing = (
        db.query(NotifyPreference)
        .filter(NotifyPreference.recipient_id == rid, NotifyPreference.venue_name_normalized == norm)
        .first()
    )
    if existing:
        if existing.preference == "include":
            existing.preference = "exclude"
            db.commit()
            return {"id": existing.id, "venue_name": norm}
        return {"id": existing.id, "venue_name": norm}
    row = NotifyPreference(recipient_id=rid, venue_name_normalized=norm, preference="exclude")
    db.add(row)
    db.commit()
    db.refresh(row)
    return {"id": row.id, "venue_name": norm}


@router.delete("/watches/exclude/{exclude_id:int}")
async def remove_venue_exclude(request: Request, exclude_id: int, db: Session = Depends(get_db)):
    """Add a venue back to default hotlist notifications (remove from excluded)."""
    rid = _recipient_id(request)
    row = (
        db.query(NotifyPreference)
        .filter(NotifyPreference.id == exclude_id, NotifyPreference.recipient_id == rid, NotifyPreference.preference == "exclude")
        .first()
    )
    if not row:
        return Response(status_code=404, content='{"error": "not found"}', media_type="application/json")
    db.delete(row)
    db.commit()
    return {"ok": True}


@router.get("/feed/follows/status")
async def follows_status(
    request: Request,
    db: Session = Depends(get_db),
    recent_within_hours: float = Query(48, ge=1, le=168),
):
    """
    Per venue on the effective notify list (hotlist ∪ saved − excludes): last drop_events time
    and whether that was within `recent_within_hours`. Uses X-Recipient-Id like venue-watches.
    """
    rid = _recipient_id(request)
    return follow_status_for_recipient(
        db, rid, recent_within_hours=float(recent_within_hours), market="nyc"
    )


@router.get("/feed/follows/activity")
async def follows_activity(
    request: Request,
    db: Session = Depends(get_db),
    limit: int = Query(40, ge=1, le=200),
):
    """
    Lightweight activity timeline from persisted in-app notifications (type new_drop).
    """
    rid = _recipient_id(request)
    return follow_activity_timeline(db, rid, limit=limit)


def _first_time_from_venue(venue: dict) -> str:
    """Extract first time as HH:MM from venue availability_times."""
    times = venue.get("availability_times") or []
    if not times:
        return "—"
    t = times[0]
    if not isinstance(t, str):
        return "—"
    if " " in t:
        t = t.split(" ", 1)[1]
    return t[:5] if len(t) >= 5 else t


def _parse_since(since: str | None) -> datetime | None:
    """Parse ISO8601 since param for new-drops; return None if missing/invalid."""
    if not since or not since.strip():
        return None
    try:
        # Support with or without Z / timezone
        s = since.strip().replace("Z", "+00:00")
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except (ValueError, TypeError):
        return None


@router.get("/feed/new-drops")
async def new_drops(
    db: Session = Depends(get_db),
    since: str | None = None,
):
    """
    New restaurants (just opened) across all buckets for notifications.
    Returns only drops detected *after* `since` (ISO8601) so clients get "new the moment they happen".
    If `since` is omitted, returns all drops in the configured window (``JUST_OPENED_WITHIN_MINUTES``).
    Poll every 10–15 s and pass the previous response's `at` as `since` for the next request.
    """
    since_dt = _parse_since(since)
    # If client sent since= but we couldn't parse it, return no drops (avoid leaking full list)
    if since is not None and since.strip() and since_dt is None:
        return {"drops": [], "at": datetime.now(timezone.utc).isoformat()}
    try:
        # Use snapshot for just-opened data (zero DB queries); fall back to DB if not yet built
        snap = get_snapshot()
        if snap is not None:
            just_opened = snap.get("just_opened_inventory") or snap.get("just_opened") or []
        else:
            just_opened = get_just_opened_from_buckets(
                db,
                limit_events=500,
                date_filter=None,
                opened_within_minutes=JUST_OPENED_WITHIN_MINUTES,
            )
        drops = []
        for day in just_opened:
            date_str = day.get("date_str") or ""
            for v in day.get("venues") or []:
                detected_at = v.get("detected_at")
                if since_dt is not None:
                    # Only return drops we can prove are new: must have detected_at and be after since
                    if not detected_at:
                        continue
                    try:
                        dt = datetime.fromisoformat(detected_at.replace("Z", "+00:00"))
                        if dt.tzinfo is None:
                            dt = dt.replace(tzinfo=timezone.utc)
                        if dt <= since_dt:
                            continue
                    except (ValueError, TypeError):
                        continue
                name = (v.get("name") or "").strip() or "Venue"
                name_slug = name.replace(" ", "-")
                drop_id = f"just-opened-{date_str}-{name_slug}"
                time_str = _first_time_from_venue(v)
                resy_url = v.get("resy_url")
                slots = [{"date_str": date_str, "time": time_str, "resyUrl": resy_url}]
                drops.append({
                    "id": drop_id,
                    "name": name,
                    "date_str": date_str,
                    "time": time_str if time_str != "—" else None,
                    "resy_url": resy_url,
                    "detected_at": detected_at,
                    "image_url": v.get("image_url"),
                    "slots": slots,
                    "is_hotspot": is_hotspot(name),
                })
        return {"drops": drops, "at": datetime.now(timezone.utc).isoformat()}
    except Exception as e:
        logger.warning("new_drops failed: %s", e, exc_info=True)
        return {"drops": [], "at": datetime.now(timezone.utc).isoformat(), "error": str(e)}


def _parse_ints(value: str | None) -> list[int] | None:
    """Parse comma-separated ints; return None if empty or invalid."""
    if not value or not value.strip():
        return None
    out = []
    for s in value.split(","):
        s = s.strip()
        if not s:
            continue
        try:
            out.append(int(s))
        except ValueError:
            continue
    return out if out else None


@router.get("/explore/drops")
async def list_drops(
    request: Request,
    response: Response,
    dates: str,
    party_sizes: str | None = None,
    db: Session = Depends(get_db),
):
    """
    **Explore tab:** all bookable inventory for the given calendar days (NYC only).

    Requires comma-separated ``dates=YYYY-MM-DD,...``. Optional ``party_sizes``.
    Returns ``just_opened`` + ``still_open`` day buckets.
    """
    date_filter = [s.strip() for s in dates.split(",") if s.strip()]
    party_size_list = _parse_ints(party_sizes)
    try:
        if not date_filter:
            raise HTTPException(
                status_code=422,
                detail="Provide at least one date: dates=YYYY-MM-DD[,YYYY-MM-DD,...]",
            )
        snap = get_snapshot()
        if snap is not None:
            payload = filter_inventory_for_drops(
                snap,
                date_filter=date_filter,
                party_sizes=party_size_list,
            )
            payload["next_scan_at"] = _next_scan_iso(request)
            return Response(
                content=json.dumps(payload, separators=(",", ":"), default=str).encode(),
                media_type="application/json",
                headers={"Cache-Control": "no-store, no-cache, must-revalidate, max-age=0"},
            )
        today = window_start_date()
        time_slot_list = None
        info = get_last_scan_info_buckets(db, today)
        just_opened = get_just_opened_from_buckets(
            db,
            limit_events=DISCOVERY_JUST_OPENED_LIMIT,
            date_filter=date_filter,
            time_slots=time_slot_list,
            party_sizes=party_size_list,
            opened_within_minutes=JUST_OPENED_WITHIN_MINUTES,
        )
        still_open = get_still_open_from_buckets(
            db,
            today,
            date_filter=date_filter,
            time_slots=time_slot_list,
            party_sizes=party_size_list,
            exclude_opened_within_minutes=JUST_OPENED_WITHIN_MINUTES,
        )
        for day in just_opened:
            for v in day.get("venues") or []:
                v["is_hotspot"] = is_hotspot(v.get("name"), v.get("market") or "nyc")
        for day in still_open:
            for v in day.get("venues") or []:
                v["is_hotspot"] = is_hotspot(v.get("name"), v.get("market") or "nyc")
        payload = {**info, "just_opened": just_opened, "still_open": still_open, "next_scan_at": _next_scan_iso(request)}
        return Response(
            content=json.dumps(payload, separators=(",", ":"), default=str).encode(),
            media_type="application/json",
            headers={"Cache-Control": "no-store, no-cache, must-revalidate, max-age=0"},
        )
    except HTTPException:
        raise
    except Exception as e:
        logger.warning("list_drops failed: %s", e, exc_info=True)
        return {
            "just_opened": [],
            "still_open": [],
            "last_scan_at": None,
            "total_venues_scanned": 0,
            "next_scan_at": _next_scan_iso(request),
            "error": str(e),
        }


@router.get("/feed/live")
async def list_just_opened(
    request: Request,
    response: Response,
    db: Session = Depends(get_db),
    party_sizes: str | None = None,
    debug: str | None = None,
    mobile: str | None = None,
):
    """**Home feed (live):** slots that **opened** in the last ``LIVE_FEED_WINDOW_MINUTES`` (default 10).

    ``still_open`` is always empty — full calendar inventory for Explore is at
    ``GET /explore/drops?dates=YYYY-MM-DD,...``.

    Serves from pre-computed snapshot when possible.

    **`debug=1`:** Bypasses snapshot; hits DB directly. Adds `_debug` key — not a stable contract.
    """
    try:
        is_debug = debug and str(debug).strip() in ("1", "true", "yes")
        is_mobile = bool(mobile and str(mobile).strip() in ("1", "true", "yes"))
        party_size_list = _parse_ints(party_sizes)
        has_filters = bool(party_size_list)

        # Mobile fast path: compact pre-serialized snapshot (zero DB queries, ~10x smaller)
        if is_mobile and not has_filters and not is_debug:
            raw = get_snapshot_json_mobile()
            if raw is not None:
                return Response(
                    content=raw,
                    media_type="application/json",
                    headers={"Cache-Control": "no-store, no-cache, must-revalidate, max-age=0"},
                )

        # Full fast path: no filters → return pre-serialized JSON bytes directly
        # (skips deepcopy, jsonable_encoder, json.dumps — sub-millisecond)
        if not has_filters and not is_debug:
            raw = get_snapshot_json()
            if raw is not None:
                return Response(
                    content=raw,
                    media_type="application/json",
                    headers={"Cache-Control": "no-store, no-cache, must-revalidate, max-age=0"},
                )

        # Filtered path: lightweight in-memory filtering on shared snapshot (no deepcopy)
        snap = get_snapshot()
        if snap is not None and not is_debug:
            filtered = filter_snapshot_for_request(snap, party_sizes=party_size_list)
            filtered["next_scan_at"] = _next_scan_iso(request)
            if (filtered.get("total_venues_scanned") or 0) == 0:
                filtered["zero_venues_hint"] = (
                    "Resy returned no open slots for the scanned dates/times. "
                    "Check RESY_API_KEY / RESY_AUTH_TOKEN in backend/.env and discovery logs."
                )
            import json as _json
            return Response(
                content=_json.dumps(filtered, separators=(",", ":"), default=str).encode(),
                media_type="application/json",
                headers={"Cache-Control": "no-store, no-cache, must-revalidate, max-age=0"},
            )

        # Fallback: first startup before snapshot is built, or debug mode — query DB directly
        today = window_start_date()
        response.headers["X-Discovery-Today"] = today.isoformat()
        info = get_last_scan_info_buckets(db, today)
        # Full inventory for just_missed exclusions (same as snapshot /drops).
        jo_inv = get_just_opened_from_buckets(
            db,
            limit_events=DISCOVERY_JUST_OPENED_LIMIT,
            date_filter=None,
            time_slots=None,
            party_sizes=None,
            opened_within_minutes=JUST_OPENED_WITHIN_MINUTES,
        )
        so_inv = get_still_open_from_buckets(
            db,
            today,
            date_filter=None,
            time_slots=None,
            party_sizes=None,
            exclude_opened_within_minutes=JUST_OPENED_WITHIN_MINUTES,
        )
        # Home feed: only very recent opens; Explore uses GET /explore/drops.
        just_opened = get_just_opened_from_buckets(
            db,
            limit_events=DISCOVERY_JUST_OPENED_LIMIT,
            date_filter=None,
            time_slots=None,
            party_sizes=party_size_list,
            opened_within_minutes=LIVE_FEED_WINDOW_MINUTES,
        )
        still_open: list[dict] = []
        for day in just_opened:
            for v in day.get("venues") or []:
                v["is_hotspot"] = is_hotspot(v.get("name"), v.get("market") or "nyc")

        # Load rolling metrics FIRST so build_feed ranks by rarity_score
        rolling_rows = (
            db.query(VenueRollingMetrics)
            .filter(VenueRollingMetrics.venue_name.isnot(None))
            .order_by(VenueRollingMetrics.computed_at.desc())
            .limit(DISCOVERY_ROLLING_METRICS_LIMIT)
            .all()
        )
        rolling_by_name: dict[str, VenueRollingMetrics] = {}
        for rm in rolling_rows:
            key = (rm.venue_name or "").strip().lower()
            if key and key not in rolling_by_name:
                rolling_by_name[key] = rm

        def _attach_metrics_raw(days: list[dict]) -> None:
            for day in days:
                for v in day.get("venues") or []:
                    nm = (v.get("name") or "").strip().lower()
                    rm = rolling_by_name.get(nm)
                    if rm:
                        v["rarity_score"] = rm.rarity_score
                        v["availability_rate_14d"] = rm.availability_rate_14d
                        v["days_with_drops"] = rm.days_with_drops
                        v["drop_frequency_per_day"] = rm.drop_frequency_per_day
                        v["trend_pct"] = rm.trend_pct

        _attach_metrics_raw(just_opened)

        feed = build_feed(just_opened, still_open)
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

        for i, item in enumerate(likely_to_open):
            item["name"] = item.get("venue_name") or item.get("name") or ""
            enrich_likely_open_item(item, i)

        from app.services.discovery.recent_missed import (
            build_just_missed_payload,
            collect_bookable_venue_keys,
        )

        _bookable_keys = collect_bookable_venue_keys(jo_inv, so_inv)
        just_missed = build_just_missed_payload(
            db,
            exclude_bookable_keys=_bookable_keys,
            within_minutes=LIVE_FEED_WINDOW_MINUTES,
        )

        def _attach_metrics(cards: list[dict]) -> None:
            for c in cards:
                nm = (c.get("name") or "").strip().lower()
                rm = rolling_by_name.get(nm)
                if rm:
                    c["rarity_score"] = rm.rarity_score
                    c["availability_rate_14d"] = rm.availability_rate_14d
                    c["days_with_drops"] = rm.days_with_drops
                    c["drop_frequency_per_day"] = rm.drop_frequency_per_day
                    c["trend_pct"] = rm.trend_pct

        _attach_metrics(ranked_board)
        _attach_metrics(top_opportunities)
        _attach_metrics(hot_right_now)

        _now_disp = datetime.now(timezone.utc)
        attach_feed_card_display_fields(ranked_board, _now_disp)
        attach_feed_card_display_fields(top_opportunities, _now_disp)
        attach_feed_card_display_fields(hot_right_now, _now_disp)

        sanitize_feed_cards_for_client(ranked_board)
        sanitize_feed_cards_for_client(top_opportunities)
        sanitize_feed_cards_for_client(hot_right_now)

        if is_debug:
            from app.services.discovery.eligibility import (
                qualified_for_home_feed,
                rank_strength_multiplier,
            )

            def _attach_rank_debug(cards: list[dict]) -> None:
                for c in cards:
                    ev = c.get("eligibility_evidence")
                    polls = c.get("bucket_successful_poll_count")
                    c["_debug_rank"] = {
                        "eligibility_evidence": ev,
                        "bucket_successful_poll_count": polls,
                        "rank_strength_multiplier": rank_strength_multiplier(ev),
                        "qualified_home_feed_if_jo_only": qualified_for_home_feed(ev, polls),
                    }

            _attach_rank_debug(ranked_board)
            _attach_rank_debug(top_opportunities)
            _attach_rank_debug(hot_right_now)

        payload = {
            "just_opened": just_opened,
            "still_open": still_open,
            "ranked_board": ranked_board,
            "top_opportunities": top_opportunities,
            "hot_right_now": hot_right_now,
            "feed_meta": snag_feed_meta(),
            "likely_to_open": likely_to_open,
            "just_missed": just_missed,
            **info,
            "next_scan_at": _next_scan_iso(request),
        }
        if (info.get("total_venues_scanned") or 0) == 0:
            payload["zero_venues_hint"] = (
                "Resy returned no open slots for the scanned dates/times. "
                "Check RESY_API_KEY / RESY_AUTH_TOKEN in backend/.env and discovery logs."
            )
        if debug and str(debug).strip() in ("1", "true", "yes"):
            just_opened_by_date = {d["date_str"]: len(d.get("venues") or []) for d in just_opened}
            bucket_ids = [bid for bid, _d, _t, _m in all_bucket_ids(today)]
            rows = db.query(DiscoveryBucket).filter(DiscoveryBucket.bucket_id.in_(bucket_ids)).all()
            def _baseline_empty(js: str | None) -> bool:
                if not js or not js.strip() or js.strip() == "[]":
                    return True
                try:
                    arr = json.loads(js)
                    return not (isinstance(arr, list) and len(arr) > 0)
                except Exception:
                    return True
            empty_baseline_buckets = [r.bucket_id for r in rows if _baseline_empty(r.baseline_slot_ids_json)]
            payload["_debug"] = {
                "just_opened_dates": list(just_opened_by_date.keys()),
                "just_opened_per_date": just_opened_by_date,
                "buckets_with_empty_baseline": len(empty_baseline_buckets),
                "buckets_with_empty_baseline_ids": empty_baseline_buckets[:5],
            }
        return payload
    except Exception as e:
        logger.warning("list_just_opened failed: %s", e, exc_info=True)
        return {"just_opened": [], "still_open": [], "last_scan_at": None, "total_venues_scanned": 0, "next_scan_at": _next_scan_iso(request)}


